#include "manifest.h"

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

  if (cap.contains("feature_extractor") && cap["feature_extractor"].contains("names")) {
    for (const auto& name : cap["feature_extractor"]["names"]) {
      out->feature_order.push_back(name.get<std::string>());
    }
  }
  // AGENTS.md rule 2: the order the regressor was trained/exported on is non-negotiable.
  static const std::vector<std::string> kExpectedOrder = {"RA", "LC", "BL", "BW", "E"};
  if (out->feature_order != kExpectedOrder) {
    *error = "weight: feature_extractor.names must be exactly [RA,LC,BL,BW,E]";
    *error_code_out = INSTAHAM_ML_ERR_CONTRACT;
    return false;
  }

  if (cap.contains("capture_contract")) {
    const json& contract = cap["capture_contract"];
    out->training_camera_height_m = contract.value("training_camera_height_m", 0.0);
    out->camera_height_is_xgboost_feature =
        contract.value("camera_height_is_xgboost_feature", false);
    out->cm_per_px_target = contract.value("cm_per_px_target", 0.0);
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

  // ref_fix.md F3: feature_domain is optional (a manifest without it simply skips the
  // gate at pipeline.cpp -- FeatureDomain's all-default max == 0.0 disables it per
  // manifest.h's comment), so no load_manifest failure here even when absent.
  if (cap.contains("feature_domain")) {
    const json& domains = cap["feature_domain"];
    auto load_domain = [&domains](const char* key, WeightCapability::FeatureDomain* out_domain) {
      if (!domains.contains(key)) return;
      const json& d = domains[key];
      out_domain->min = d.value("min", 0.0);
      out_domain->max = d.value("max", 0.0);
      out_domain->upper_multiplier = d.value("upper_multiplier", 1.0);
    };
    load_domain("RA", &out->domain_ra);
    load_domain("LC", &out->domain_lc);
    load_domain("BL", &out->domain_bl);
    load_domain("BW", &out->domain_bw);
    load_domain("E", &out->domain_e);
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
