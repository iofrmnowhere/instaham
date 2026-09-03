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

// ML_implementation_plan.md revision 7, section 8: XGBoost weight regressor, exported to
// ONNX by ML/export/export_xgboost.py. `feature_order` MUST equal {"RA","LC","BL","BW","E"}
// (AGENTS.md rule 2) -- load_manifest() rejects a manifest where it does not.
struct WeightCapability {
  bool available = false;
  std::string model_path;    // absolute; the xgboost.onnx graph
  std::string model_sha256;
  std::vector<std::string> feature_order;
  double training_camera_height_m = 0.0;
  bool camera_height_is_xgboost_feature = false;

  // TASKS.md W1: cm/px the regressor's feature space was trained at, and the frame (in
  // pixels) `RA`'s denominator was measured against -- recovered from
  // ML/weight_prediction/fixed_test_predictions_POSTHOC.csv, where
  // body_mask_area_px / RA == 720*720 on every one of 2014 rows. A weight-available
  // manifest missing either field fails to load (load_manifest, INSTAHAM_ML_ERR_CONTRACT)
  // rather than silently defaulting to an unscaled k = 1.0 (AGENTS.md rule 8).
  double cm_per_px_target = 0.0;
  int training_frame_w = 0;
  int training_frame_h = 0;

  // ref_fix.md F3: the [min, max] each of RA/LC/BL/BW/E actually took across the
  // regressor's own training/eval set (ML/weight_prediction/fixed_test_predictions_POSTHOC.csv,
  // 2014 rows) -- the real question a scale sanity check should ask ("would this feature
  // vector even make sense to this model?") rather than the proxy question k's range asks.
  // `upper_multiplier` widens only the max, to allow for the identity-stub cutter leaving
  // the head/neck in the mask (so BL/LC/RA legitimately run above their trained range until
  // the real cutter lands) -- the min is never widened, since a smaller-than-trained value
  // has no such excuse. Empty (all-default) FeatureDomain entries mean "no manifest data
  // yet"; the gate at pipeline.cpp only applies to a feature whose domain has max > 0.
  struct FeatureDomain {
    double min = 0.0;
    double max = 0.0;
    double upper_multiplier = 1.0;
  };
  FeatureDomain domain_ra;
  FeatureDomain domain_lc;
  FeatureDomain domain_bl;
  FeatureDomain domain_bw;
  FeatureDomain domain_e;
};

struct Manifest {
  std::string base_dir;  // directory containing manifest.json; all *_path fields above are absolute
  ClassifierCapability view;
  ClassifierCapability health;
  SegmentationCapability segmentation;
  WeightCapability weight;
  bool weight_available = false;  // == weight.available; kept for existing callers
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
