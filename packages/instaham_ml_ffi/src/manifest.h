#ifndef INSTAHAM_ML_MANIFEST_H
#define INSTAHAM_ML_MANIFEST_H

#include <map>
#include <string>
#include <vector>

namespace instaham_ml {

// One classifier capability (view | health) as recorded by ML/export/export_classifier.py.
struct ClassifierCapability {
  bool available = false;
  std::string model_path;    // absolute, resolved against the manifest's directory
  std::string model_sha256;
  std::string classes_path;  // absolute
  std::string classes_sha256;
  int input_size = 224;      // square crop, per model_input_block() in ML/export/common.py
  int resize_shorter_side = 255;
  float scale = 1.0f / 255.0f;
  float mean[3] = {0.485f, 0.456f, 0.406f};
  float std_dev[3] = {0.229f, 0.224f, 0.225f};
  std::string protocol_version;
  // health only: capabilities.health.input.protocol, one of full_frame /
  // segmentation_crop / segmentation_masked / abnormality_crop. Empty for the view
  // capability, which has no input switch (section 1.1(a)). Only full_frame is
  // implemented -- see health_input.h -- so any other value currently degrades to it.
  std::string input_protocol;
  // class name -> index, loaded from classes.json (never hardcode indices: AGENTS.md rule 1)
  std::vector<std::string> class_names;  // index -> name, built from classes.json
};

struct SegmentationCapability {
  bool available = false;
  std::string model_path;
  std::string model_sha256;
  int imgsz = 640;
  uint8_t letterbox_color = 114;
  float conf_threshold = 0.25f;
  float iou_threshold = 0.7f;
  std::string protocol_version;
};

struct Manifest {
  std::string base_dir;  // directory containing manifest.json; all *_path fields above are absolute
  ClassifierCapability view;
  ClassifierCapability health;
  SegmentationCapability segmentation;
  bool weight_available = false;
};

// Loads and validates manifest.json at `path`:
//   - JSON must parse and schema_version must be present (section 8 of the plan).
//   - Every referenced model/classes file's sha256 must match the manifest's recorded hash.
// On any failure returns false and fills `error` with a short diagnostic; `error_code_out`
// receives INSTAHAM_ML_ERR_MANIFEST or INSTAHAM_ML_ERR_HASH_MISMATCH (values match
// instaham_ml.h's InstahamMlStatus so callers do not need to duplicate the mapping).
bool load_manifest(const std::string& path, Manifest* out, std::string* error, int* error_code_out);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_MANIFEST_H
