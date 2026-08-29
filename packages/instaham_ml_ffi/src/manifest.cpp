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

  out->weight_available = caps.contains("weight") && caps["weight"].value("available", false);
  return true;
}

}  // namespace instaham_ml
