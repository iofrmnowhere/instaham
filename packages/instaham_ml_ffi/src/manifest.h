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

  // ref_fix.md F18: centimetres one 640x640-canvas pixel should span, measured against the
  // three ground-truth photos in .pig_pictures/ (section 2, F18) -- the segmenter does not
  // reliably detect a pig at the apparent size a plain whole-frame letterbox produces for a
  // typical 2250x3000 phone capture (roughly 220x400px, well below what the model responds
  // to; section 1.3/1.4). 0.0 (the default, and what an older manifest fragment carries)
  // disables scale-aware composition and falls back to the plain fit-to-canvas letterbox
  // this always used -- the only behaviour available when no cm_per_px_actual exists yet
  // (health_only route, or no reference marked: AGENTS.md rule 7 forbids inventing one).
  double input_cm_per_px = 0.0;

  // ref_fix.md F19: multipliers of input_cm_per_px tried in order (by pipeline.cpp, not
  // this file) until a mask meeting manifest.weight.min_mask_diagonal_fraction is found --
  // the segmenter is measurably brittle at any single scale (section 1.4's 118kg row), so
  // one constant is not enough. {1.0} (the default) means "no ladder, one attempt".
  std::vector<double> scale_ladder_multipliers = {1.0};

  // ref_fix.md F19: once every ladder rung has been tried at conf_threshold with no
  // plausible mask, retry the same ladder at this lower confidence. 0.0 (default) disables
  // the retry pass entirely rather than silently lowering the bar.
  float retry_conf_threshold = 0.0f;
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

  // ref_fix.md F16: the minimum fraction (of the image's own diagonal) the constructed
  // mask's bounding-box diagonal must reach before the cutter/feature/domain stages even
  // run on it. A mask this small isn't a pig -- it's what F12's mask-selection bug
  // produced (observed as low as ~1.5% and ~8% of frame against a real 55%-of-frame
  // photo) -- and E (eccentricity) alone cannot catch it, since a thin sliver scores HIGH
  // on eccentricity rather than low. Tunable from the manifest rather than a compiled-in
  // constant per ref_fix.md section 3; defaults to 0.15 when the manifest doesn't declare
  // it (an older fragment), which is permissive enough not to newly reject a manifest that
  // predates this field.
  double min_mask_diagonal_fraction = 0.15;

  // ref_fix.md F9: how far cm_per_px_target itself might be off (>= 1.0; 1.0 means "exact,
  // no widening"). Set by ML/export/export_xgboost.py from an allometric sanity check
  // while cm_per_px_target_source stays "UNCALIBRATED_..." -- see ref_fix.md section 1.5.
  // Widens (never tightens) the SIZE feature_domain bounds at the pipeline.cpp gate so a
  // correctly-marked reference isn't rejected purely because the manifest's own scale seed
  // carries unquantified error. Clamped to >= 1.0 by load_weight() below so a malformed or
  // missing value can only ever widen, never tighten, a bound (AGENTS.md rule 8).
  double cm_per_px_target_uncertainty = 1.0;

  // ref_fix.md F3/F8: the [min, max] each of RA/LC/BL/BW/E actually took across the
  // regressor's own training/eval set (ML/weight_prediction/fixed_test_predictions_POSTHOC.csv,
  // 2014 rows) -- the real question a scale sanity check should ask ("would this feature
  // vector even make sense to this model?") rather than the proxy question k's range asks.
  // `upper_multiplier` widens the max and `lower_multiplier` widens the min, both to allow
  // for the identity-stub cutter leaving the head/neck in the mask -- see
  // ML/export/export_xgboost.py for how each per-feature multiplier is derived from the
  // CSV's own whole_mask_area_px/body_mask_area_px ratio rather than guessed. Empty
  // (all-default) FeatureDomain entries mean "no manifest data yet"; the gate at
  // pipeline.cpp only applies to a feature whose domain has max > 0.
  struct FeatureDomain {
    double min = 0.0;
    double max = 0.0;
    double upper_multiplier = 1.0;
    double lower_multiplier = 1.0;
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
