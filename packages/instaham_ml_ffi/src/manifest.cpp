#include "manifest.h"

#include <algorithm>
#include <fstream>
#include <sstream>

#include "include/instaham_ml.h"
#include "third_party/nlohmann_json/single_include/nlohmann/json.hpp"
#include "util/sha256.h"

namespace instaham_ml {
namespace {

using json = nlohmann::json;

std::string dirname_of(const std::string& path) {
  size_t pos = path.find_last_of("/\\");
  return pos == std::string::npos ? std::string(".") : path.substr(0, pos);
}

std::string join_path(const std::string& dir, const std::string& rel) {
  if (dir.empty()) return rel;
  char last = dir.back();
  if (last == '/' || last == '\\') return dir + rel;
  return dir + "/" + rel;
}

// Verifies `abs_path`'s sha256 against `expected` (already-lowercase hex, per the schema's
// `^[0-9a-f]{64}$` pattern). Empty `expected` means "not referenced" and always passes.
bool verify_hash(const std::string& abs_path, const std::string& expected, std::string* error) {
  if (expected.empty()) return true;
  std::string actual = hex_digest_of_file(abs_path);
  if (actual.empty()) {
    *error = "could not read file for hash verification: " + abs_path;
    return false;
  }
  if (actual != expected) {
    *error = "sha256 mismatch for " + abs_path + " (manifest says " + expected + ", file is " +
             actual + ")";
    return false;
  }
  return true;
}

// docs/plan-phase/3-manifest-pipeline.md: the canonical feature order per family, kept in
// C++ (not just trusted from the manifest) because the manifest is an asset that can be
// swapped without a rebuild -- the native side must still refuse a vector whose order does
// not match the graph it is about to run. Mirrors ML/export/common.py's FEATURE_FAMILIES.
const std::vector<std::string>& baseline5_order() {
  static const std::vector<std::string> kOrder = {"RA", "LC", "BL", "BW", "E"};
  return kOrder;
}
const std::vector<std::string>& chen16_noheight_order() {
  static const std::vector<std::string> kOrder = {
      "mask_area", "convex_hull_area", "difference", "dif_mask",   "body_curve",
      "perimeter", "outline_curve",    "longest",    "shortest",   "Hu_1",
      "Hu_2",      "Hu_3",             "Hu_4",       "Hu_5",       "Hu_6",
      "Hu_7"};
  return kOrder;
}
// Returns nullptr for an unrecognised family -- load_weight() turns that into a load failure
// rather than silently accepting an arbitrary order.
const std::vector<std::string>* canonical_order_for_family(const std::string& family) {
  if (family == "baseline5") return &baseline5_order();
  if (family == "chen16_noheight") return &chen16_noheight_order();
  return nullptr;
}

// Fallback `dimension` for a manifest fragment predating this field entirely (no
// "dimension" key anywhere under feature_domain). Every manifest ML/export/export_xgboost.py
// writes from here on emits `dimension` explicitly per entry (it is data, not a compiled-in
// table -- docs/plan-phase/3-manifest-pipeline.md), so this only exists to make a
// pre-phase-3 baseline5 fragment gate exactly as it always did: RA as an area, LC/BL/BW as
// lengths, E (eccentricity, scale-invariant) as dimensionless -- mirroring
// ML/export/export_xgboost.py's _BASELINE5_FEATURE_META/_CHEN16_FEATURE_META tables.
std::string default_dimension_for(const std::string& family, const std::string& name) {
  if (family == "baseline5") {
    if (name == "RA") return "area";
    if (name == "E") return "dimensionless";
    return "linear";  // LC, BL, BW
  }
  if (family == "chen16_noheight") {
    if (name == "mask_area" || name == "convex_hull_area" || name == "difference") {
      return "area";
    }
    if (name == "perimeter" || name == "longest" || name == "shortest") return "linear";
    return "dimensionless";  // dif_mask, body_curve, outline_curve, Hu_1..Hu_7
  }
  return "linear";
}

bool load_class_names(const std::string& path, std::vector<std::string>* out, std::string* error) {
  std::ifstream f(path);
  if (!f) {
    *error = "could not open classes.json: " + path;
    return false;
  }
  json j;
  try {
    f >> j;
  } catch (const std::exception& e) {
    *error = std::string("classes.json parse error: ") + e.what();
    return false;
  }
  size_t max_idx = 0;
  for (auto& [name, idx] : j.items()) {
    max_idx = std::max(max_idx, size_t(idx.get<int>()));
  }
  out->assign(max_idx + 1, std::string());
  for (auto& [name, idx] : j.items()) {
    (*out)[idx.get<int>()] = name;  // never hardcode indices (AGENTS.md rule 1)
  }
  return true;
}

bool load_classifier(const json& j, const std::string& key, const std::string& base_dir,
                      ClassifierCapability* out, std::string* error, int* error_code_out) {
  if (!j.contains(key)) {
    out->available = false;
    return true;  // capability simply absent from this manifest -- not an error
  }
  const json& cap = j.at(key);
  out->available = cap.value("available", false);
  if (!out->available) return true;

  if (!cap.contains("model") || !cap.contains("class_map")) {
    *error = key + ": missing model/class_map block";
    *error_code_out = INSTAHAM_ML_ERR_MANIFEST;
    return false;
  }
  const json& model = cap.at("model");
  out->model_path = join_path(base_dir, model.value("path", ""));
  out->model_sha256 = model.value("sha256", "");
  if (model.contains("input") && model["input"].contains("size")) {
    auto size = model["input"]["size"];
    if (size.is_array() && !size.empty()) out->input_size = size[0].get<int>();
  }
  out->protocol_version = cap.value("protocol_version", "");

  // health only; absent for view. Unrecognised values are not rejected here --
  // parse_health_input_protocol() degrades them to full_frame (health_input.h).
  if (cap.contains("input") && cap["input"].is_object()) {
    out->input_protocol = cap["input"].value("protocol", "");
  }

  if (cap.contains("preprocessing")) {
    const json& pre = cap["preprocessing"];
    out->resize_shorter_side = pre.value("resize_shorter_side", out->resize_shorter_side);
    out->scale = pre.value("scale", out->scale);
    if (pre.contains("mean") && pre["mean"].is_array() && pre["mean"].size() == 3) {
      for (int i = 0; i < 3; ++i) out->mean[i] = pre["mean"][i].get<float>();
    }
    if (pre.contains("std") && pre["std"].is_array() && pre["std"].size() == 3) {
      for (int i = 0; i < 3; ++i) out->std_dev[i] = pre["std"][i].get<float>();
    }
  }

  const json& class_map = cap.at("class_map");
  out->classes_path = join_path(base_dir, class_map.value("path", ""));
  out->classes_sha256 = class_map.value("sha256", "");

  if (!verify_hash(out->model_path, out->model_sha256, error)) {
    *error_code_out = INSTAHAM_ML_ERR_HASH_MISMATCH;
    return false;
  }
  if (!verify_hash(out->classes_path, out->classes_sha256, error)) {
    *error_code_out = INSTAHAM_ML_ERR_HASH_MISMATCH;
    return false;
  }
  if (!load_class_names(out->classes_path, &out->class_names, error)) {
    *error_code_out = INSTAHAM_ML_ERR_MANIFEST;
    return false;
  }
  return true;
}

bool load_segmentation(const json& j, const std::string& base_dir, SegmentationCapability* out,
                        std::string* error, int* error_code_out) {
  if (!j.contains("segmentation")) {
    out->available = false;
    return true;
  }
  const json& cap = j.at("segmentation");
  out->available = cap.value("available", false);
  out->protocol_version = cap.value("protocol_version", "");
  if (cap.contains("postprocess")) {
    const json& pp = cap["postprocess"];
    out->conf_threshold = pp.value("conf", out->conf_threshold);
    out->iou_threshold = pp.value("iou", out->iou_threshold);
  }
  if (!out->available) return true;

  if (!cap.contains("model")) {
    *error = "segmentation: missing model block";
    *error_code_out = INSTAHAM_ML_ERR_MANIFEST;
    return false;
  }
  const json& model = cap.at("model");
  out->model_path = join_path(base_dir, model.value("path", ""));
  out->model_sha256 = model.value("sha256", "");
  if (model.contains("input") && model["input"].contains("size")) {
    auto size = model["input"]["size"];
    if (size.is_array() && !size.empty()) out->imgsz = size[0].get<int>();
  }
  if (model.contains("letterbox") && model["letterbox"].contains("color")) {
    auto color = model["letterbox"]["color"];
    if (color.is_array() && !color.empty()) out->letterbox_color = uint8_t(color[0].get<int>());
  }

  // ref_fix.md F18/F19: absent on an older manifest fragment -- keeps input_cm_per_px at
  // 0.0 (disabled) and the ladder at its single-rung default, so a pre-F18 manifest
  // segments exactly as it always has (a plain whole-frame letterbox, one attempt).
  if (cap.contains("input_scale")) {
    const json& input_scale = cap["input_scale"];
    out->input_cm_per_px = input_scale.value("cm_per_px", 0.0);
    if (input_scale.contains("ladder_multipliers") &&
        input_scale["ladder_multipliers"].is_array() &&
        !input_scale["ladder_multipliers"].empty()) {
      out->scale_ladder_multipliers.clear();
      for (const auto& m : input_scale["ladder_multipliers"]) {
        out->scale_ladder_multipliers.push_back(m.get<double>());
      }
    }
    out->retry_conf_threshold = input_scale.value("retry_conf_threshold", 0.0f);

    // docs/fix-phase-4/1-normalize-before-segment.md (F60): absent, or any value other than
    // "normalize_first", keeps the shipped canvas_scale behaviour -- never silently opts a
    // manifest into the new path on a typo.
    const std::string mode = input_scale.value("mode", std::string("canvas_scale"));
    out->input_scale_mode = (mode == "normalize_first") ? SegmentationInputScaleMode::kNormalizeFirst
                                                          : SegmentationInputScaleMode::kCanvasScale;
  }

  if (!verify_hash(out->model_path, out->model_sha256, error)) {
    *error_code_out = INSTAHAM_ML_ERR_HASH_MISMATCH;
    return false;
  }
  return true;
}

// ML_implementation_plan.md revision 7, section 8: the weight capability's regressor +
// feature order, as written by ML/export/export_xgboost.py's manifest_fragment.json.
// `available` gates everything else (instaham_ml_capability_available("weight"),
// instaham_ml.cpp's weight_runner creation): a manifest with weight.available == false
// still parses cleanly, it just leaves `out` at its all-default state.
bool load_weight(const json& j, const std::string& base_dir, WeightCapability* out,
                  std::string* error, int* error_code_out) {
  if (!j.contains("weight")) {
    out->available = false;
    return true;
  }
  const json& cap = j.at("weight");
  out->available = cap.value("available", false);
  if (!out->available) return true;

  if (!cap.contains("regressor")) {
    *error = "weight: missing regressor block";
    *error_code_out = INSTAHAM_ML_ERR_MANIFEST;
    return false;
  }
  const json& regressor = cap.at("regressor");
  out->model_path = join_path(base_dir, regressor.value("path", ""));
  out->model_sha256 = regressor.value("sha256", "");

  // ref_fix.md F16: absent on an older manifest fragment -- keeps the 0.15 default set on
  // the struct (manifest.h), so a pre-F16 manifest gates exactly as it always has apart
  // from gaining the new mask-plausibility check with a sane default threshold.
  out->min_mask_diagonal_fraction =
      cap.value("min_mask_diagonal_fraction", out->min_mask_diagonal_fraction);

  // docs/plan-phase/3-manifest-pipeline.md: absent on an older manifest fragment -- defaults
  // to "baseline5", the only family that ever shipped before this field existed, so a
  // pre-phase-3 manifest fragment validates exactly as it always did.
  out->feature_family = cap.value("feature_family", std::string("baseline5"));
  const std::vector<std::string>* canonical = canonical_order_for_family(out->feature_family);
  if (!canonical) {
    *error = "weight: unknown feature_family '" + out->feature_family + "'";
    *error_code_out = INSTAHAM_ML_ERR_CONTRACT;
    return false;
  }

  if (cap.contains("feature_extractor") && cap["feature_extractor"].contains("names")) {
    for (const auto& name : cap["feature_extractor"]["names"]) {
      out->feature_order.push_back(name.get<std::string>());
    }
  }
  // AGENTS.md rule 2: the order the regressor was trained/exported on is non-negotiable --
  // now validated structurally (family known, order equals that family's canonical list)
  // rather than against a single hardcoded name list, since feature_order is arbitrary width.
  if (out->feature_order != *canonical) {
    *error = "weight: feature_extractor.names must be exactly the " + out->feature_family +
             " order";
    *error_code_out = INSTAHAM_ML_ERR_CONTRACT;
    return false;
  }

  if (cap.contains("capture_contract")) {
    const json& contract = cap["capture_contract"];
    out->training_camera_height_m = contract.value("training_camera_height_m", 0.0);
    out->camera_height_is_xgboost_feature =
        contract.value("camera_height_is_xgboost_feature", false);
    out->cm_per_px_target = contract.value("cm_per_px_target", 0.0);
    // ref_fix.md F9: clamp up to 1.0 -- this field may only ever widen a feature_domain
    // bound at the pipeline.cpp gate, never tighten one (AGENTS.md rule 8), so a manifest
    // that (erroneously) declared a value below 1.0 cannot narrow the gate.
    out->cm_per_px_target_uncertainty =
        std::max(1.0, contract.value("cm_per_px_target_uncertainty", 1.0));
    if (contract.contains("training_frame_px")) {
      const json& frame = contract["training_frame_px"];
      if (frame.is_array() && frame.size() == 2) {
        out->training_frame_w = frame[0].get<int>();
        out->training_frame_h = frame[1].get<int>();
      }
    }
  }

  // TASKS.md W1: a weight-available manifest that cannot report the scale its features
  // were trained at cannot be normalized against a live capture -- refuse to load rather
  // than let the pipeline fall back to an unscaled k = 1.0 (AGENTS.md rule 8).
  if (out->cm_per_px_target <= 0.0 || out->training_frame_w <= 0 || out->training_frame_h <= 0) {
    *error =
        "weight: capture_contract.cm_per_px_target and training_frame_px are required "
        "when weight.available is true";
    *error_code_out = INSTAHAM_ML_ERR_CONTRACT;
    return false;
  }

  // ref_fix.md F3, generalized by docs/plan-phase/3-manifest-pipeline.md: feature_domain is
  // optional (a manifest without it simply skips the gate at pipeline.cpp -- FeatureDomain's
  // all-default max == 0.0 disables it per manifest.h's comment), so no load_manifest
  // failure here even when absent. Keyed by feature name now that feature_order is
  // arbitrary width, rather than five named struct members.
  if (cap.contains("feature_domain")) {
    for (const auto& [name, d] : cap["feature_domain"].items()) {
      WeightCapability::FeatureDomain domain;
      domain.min = d.value("min", 0.0);
      domain.max = d.value("max", 0.0);
      domain.upper_multiplier = d.value("upper_multiplier", 1.0);
      // ref_fix.md F8: absent on an older manifest fragment -- defaults to 1.0, i.e. the
      // min is not widened, exactly matching pre-F8 behaviour.
      domain.lower_multiplier = d.value("lower_multiplier", 1.0);
      // docs/plan-phase/3-manifest-pipeline.md: absent on a pre-phase-3 manifest fragment
      // -- falls back to the per-name default so an old baseline5 fragment gates exactly
      // as it always did (RA area, LC/BL/BW linear, E dimensionless).
      domain.dimension = d.value("dimension", default_dimension_for(out->feature_family, name));
      domain.gate = d.value("gate", true);
      if (domain.dimension == "dimensionless" &&
          (domain.upper_multiplier != 1.0 || domain.lower_multiplier != 1.0)) {
        *error = "weight: feature_domain." + name +
                 " is dimensionless but declares a multiplier other than 1.0 (there is "
                 "nothing for a scale-uncertainty widening to mean on a feature that does "
                 "not scale with k)";
        *error_code_out = INSTAHAM_ML_ERR_CONTRACT;
        return false;
      }
      out->feature_domain[name] = domain;
    }
  }

  if (cap.contains("quality_gates")) {
    const json& qg = cap["quality_gates"];
    out->quality_gate_truncation = qg.value("truncation", false);
    out->quality_gate_posture = qg.value("posture", false);
    out->quality_gate_posture_max_bend_deg =
        qg.value("posture_max_bend_deg", out->quality_gate_posture_max_bend_deg);
  }

  if (!verify_hash(out->model_path, out->model_sha256, error)) {
    *error_code_out = INSTAHAM_ML_ERR_HASH_MISMATCH;
    return false;
  }
  return true;
}

}  // namespace

bool load_manifest(const std::string& path, Manifest* out, std::string* error, int* error_code_out) {
  std::ifstream f(path);
  if (!f) {
    *error = "could not open manifest: " + path;
    *error_code_out = INSTAHAM_ML_ERR_MANIFEST;
    return false;
  }
  json j;
  try {
    f >> j;
  } catch (const std::exception& e) {
    *error = std::string("manifest parse error: ") + e.what();
    *error_code_out = INSTAHAM_ML_ERR_MANIFEST;
    return false;
  }
  if (!j.contains("schema_version") || !j.contains("capabilities")) {
    *error = "manifest missing schema_version or capabilities";
    *error_code_out = INSTAHAM_ML_ERR_MANIFEST;
    return false;
  }

  out->base_dir = dirname_of(path);
  const json& caps = j.at("capabilities");

  if (!load_classifier(caps, "view", out->base_dir, &out->view, error, error_code_out)) return false;
  if (!load_classifier(caps, "health", out->base_dir, &out->health, error, error_code_out)) return false;
  if (!load_segmentation(caps, out->base_dir, &out->segmentation, error, error_code_out)) return false;
  if (!load_weight(caps, out->base_dir, &out->weight, error, error_code_out)) return false;

  out->weight_available = out->weight.available;
  return true;
}

}  // namespace instaham_ml
