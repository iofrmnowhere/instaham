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
  // capability, which has no input switch (section 1.1(a)). abnormality_crop still
  // degrades to full_frame -- see health_input.h -- the other two protocols are
  // implemented as of docs/plan-phase-3/1-coordinate-recovery-and-masked-crop.md.
  std::string input_protocol;
  // health only: capabilities.health.input.bbox_padding_ratio / background_fill --
  // docs/plan-phase-3/1-coordinate-recovery-and-masked-crop.md. Defaults match
  // ML/parity/reference_health_input.py's HEALTH_INPUT_PARAMS so an absent manifest
  // block reproduces the reference exactly rather than silently zeroing the pad.
  float health_bbox_padding_ratio = 0.06f;
  std::string health_background_fill = "imagenet_mean";
  // health only: capabilities.health.cascade -- docs/plan-4.md / docs/plan-phase-4/1-native-
  // cascade.md. When enabled, classifier.cpp's run_health_cascade() runs a second pass with
  // `health_second_stage_protocol` whenever the first pass's label is not
  // `health_healthy_label`, and that second pass's result becomes the final one. Disabled
  // (the default) reproduces today's single-pass behaviour exactly.
  bool health_cascade_enabled = false;
  // Checked against class_names (below) once it is loaded; a name absent from the class map
  // disables the cascade rather than failing manifest load (AGENTS.md rule 4) -- see
  // manifest.cpp's load_classifier(). health_cascade_disabled_reason then records why.
  std::string health_healthy_label = "Healthy";
  std::string health_second_stage_protocol = "segmentation_masked";
  std::string health_cascade_disabled_reason;
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

  // docs/fix-phase-4/4-app-wiring.md phase 4: the round-4 `input_scale` block
  // (`legacy_ladder_base_cm_per_px`, `ladder_multipliers`, `retry_conf_threshold`) is
  // removed here along with pipeline.cpp's retry ladder it fed. README section 13 is a
  // single pass at `WeightCapability::cm_per_px_target`; there is no other scale for this
  // capability to declare. A manifest still carrying the old block is read as if it did
  // not (manifest.cpp no longer parses `input_scale`), not rejected -- an older asset
  // degrades to the README path's one composition rather than failing to load.
};

// ML_implementation_plan.md revision 7, section 8 / docs/plan-phase/3-manifest-pipeline.md:
// XGBoost weight regressor, exported to ONNX by ML/export/export_xgboost.py.
// `feature_family` names which of ML/export/common.py's FEATURE_FAMILIES this manifest was
// exported for ("baseline5" | "chen16_noheight"); `feature_order` MUST equal that family's
// canonical order exactly (AGENTS.md rule 2) -- load_manifest() rejects a manifest where it
// does not. Kept as a compiled-in pair of constants (manifest.cpp) rather than trusting the
// manifest's order alone: the manifest is an asset and can be swapped without a rebuild, so
// the native side must still refuse a vector whose width/order does not match the graph
// it is about to run.
struct WeightCapability {
  bool available = false;
  std::string model_path;    // absolute; the xgboost.onnx graph
  std::string model_sha256;
  std::string feature_family = "baseline5";  // "baseline5" | "chen16_noheight"
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

  // ref_fix.md F3/F8, generalized by docs/plan-phase/3-manifest-pipeline.md: the [min, max]
  // each named feature actually took across the regressor's own training/eval set. `min`/
  // `max` is the real question a scale sanity check should ask ("would this feature vector
  // even make sense to this model?") rather than the proxy question k's range asks.
  // `upper_multiplier`/`lower_multiplier` widen the max/min -- on baseline5 these existed to
  // tolerate the identity-stub cutter leaving the head/neck in the mask (see
  // ML/export/export_xgboost.py); with the real V176/V144 cutter running for chen16_noheight
  // both are 1.0 (phase 2, "no widening to admit an uncut mask" is no longer justified).
  // `dimension` ("area" | "linear" | "dimensionless") is data, not a compiled-in table --
  // it drives the calibration-uncertainty widening exponent in pipeline.cpp (area ->
  // uncertainty^2, linear -> uncertainty^1, dimensionless -> uncertainty^0). A dimensionless
  // feature declaring a multiplier other than 1.0 is a manifest contract error (there is
  // nothing for a scale-uncertainty widening to mean on a feature that does not scale with
  // k) -- load_weight() below rejects it rather than silently ignoring it.
  // `gate` says whether this feature's domain is an eligibility check (pipeline.cpp refuses
  // a prediction when it fails) or a diagnostic-only bound recorded for visibility; only the
  // features `k` actually scales are gated (docs/plan-phase/3-manifest-pipeline.md, "Do not
  // gate on all sixteen"). Empty (all-default) FeatureDomain entries mean "no manifest data
  // yet"; the gate at pipeline.cpp only applies to a feature whose domain has max > 0.
  struct FeatureDomain {
    double min = 0.0;
    double max = 0.0;
    double upper_multiplier = 1.0;
    double lower_multiplier = 1.0;
    std::string dimension = "linear";  // "area" | "linear" | "dimensionless"
    bool gate = true;
  };
  // Keyed by feature name (e.g. "RA" or "mask_area", matching feature_order). Replaces the
  // five named domain_ra/lc/bl/bw/e members now that feature_order is arbitrary width.
  std::map<std::string, FeatureDomain> feature_domain;

  // docs/plan-phase/3-manifest-pipeline.md, "The quality gates get a manifest switch": both
  // gates are ported (phase 2) but ship dark until their activation is a deliberate manifest
  // edit, not a rebuild. posture_max_bend_deg is a validated research value carried here to
  // be recorded, not casually tuned (vendor README_AI_INTEGRATION.md section 8).
  bool quality_gate_truncation = false;
  bool quality_gate_posture = false;
  double quality_gate_posture_max_bend_deg = 40.0;
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
