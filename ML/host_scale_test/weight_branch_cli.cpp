// docs/test-plan-phase/2-host-cli.md: host-side replication of INSTAHAM's weight branch,
// built from the SAME stage sources pipeline.cpp calls (segmentation, construction, the
// k-resample, the vendor V176/V144 cutter, Chen16 feature extraction, XGBoost-via-ONNX
// prediction) -- not a Python reimplementation. This file reproduces pipeline.cpp's weight
// branch ordering by hand (see the plan's "What the CLI must reproduce exactly"); it does
// NOT include pipeline.cpp itself, which also owns the view/health branches and the FFI
// envelope and would require the classifier models this test does not need.
//
// Unlike the app, this CLI assumes the image is already a valid dorsal-view photo (no view
// classifier is loaded) and ALWAYS computes and prints a prediction even where a gate would
// have made the app withhold one -- see "Deliberate deviations from the app" in the phase 2
// plan. Every place a gate would have withheld sets a field in
// "gates_would_have_withheld_reasons" rather than aborting, so a caller can tell "the
// constant changed the number" apart from "the constant changed whether the app would have
// shown a number at all".
//
// Usage: weight_branch_cli <manifest_path> <image_path> <cm_per_px_actual>
// Prints one JSON object to stdout. Diagnostics go to stderr. Exit 0 once an envelope was
// produced (including a declined one); exit 2 on argument/load failure.

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

#include "manifest.h"
#include "onnx_runner.h"
#include "stages/construction.h"
#include "stages/cutter.h"
#include "stages/feature_calculation.h"
#include "stages/segmentation.h"
#include "stages/weight_prediction.h"
#include "third_party/nlohmann_json/single_include/nlohmann/json.hpp"

using json = nlohmann::json;
using namespace instaham_ml;

namespace {

// ---- reproduced from pipeline.cpp's anonymous namespace (not exported by that TU) -------
// Each function below is copied, not re-derived, from packages/instaham_ml_ffi/src/
// pipeline.cpp so this harness checks the same arithmetic the app runs. Where this CLI's
// behaviour differs from the app's (always predict, never withhold), the difference is in
// the CALLER below, not in these helpers -- the helpers themselves are faithful copies.

double mask_diagonal_fraction(const stages::PigMask& mask) {
  const double mask_diag =
      std::sqrt(double(mask.bbox_w) * mask.bbox_w + double(mask.bbox_h) * mask.bbox_h);
  const double frame_diag =
      std::sqrt(double(mask.width) * mask.width + double(mask.height) * mask.height);
  return frame_diag > 0.0 ? mask_diag / frame_diag : 0.0;
}

double uncertainty_exponent(const std::string& dimension) {
  if (dimension == "area") return 2.0;
  if (dimension == "linear") return 1.0;
  return 0.0;  // "dimensionless"
}

bool feature_in_domain(double value, const WeightCapability::FeatureDomain& domain,
                        double uncertainty_pow, const std::string& name, json* violations) {
  if (domain.max <= 0.0) return true;
  const double lower = domain.min * domain.lower_multiplier / uncertainty_pow;
  const double upper = domain.max * domain.upper_multiplier * uncertainty_pow;
  if (!std::isfinite(value) || value < lower || value > upper) {
    const std::string direction = (!std::isfinite(value) || value < lower) ? "low" : "high";
    violations->push_back(json{
        {"feature", name},
        {"value", value},
        {"allowed_min", lower},
        {"allowed_max", upper},
        {"direction", direction},
        {"dimension", domain.dimension},
    });
    return false;
  }
  return true;
}

bool run_feature_domain_gate(const std::vector<std::string>& feature_order,
                              const std::map<std::string, WeightCapability::FeatureDomain>& domains,
                              const std::map<std::string, double>& values, double uncertainty,
                              json* violations) {
  bool in_domain = true;
  for (const auto& name : feature_order) {
    auto domain_it = domains.find(name);
    if (domain_it == domains.end() || !domain_it->second.gate) continue;
    const double uncertainty_pow =
        std::pow(uncertainty, uncertainty_exponent(domain_it->second.dimension));
    const bool ok =
        feature_in_domain(values.at(name), domain_it->second, uncertainty_pow, name, violations);
    in_domain = in_domain && ok;
  }
  return in_domain;
}

std::map<std::string, double> chen16_values(const std::vector<std::string>& order,
                                             const stages::Chen16Features& f) {
  std::map<std::string, double> out;
  for (size_t i = 0; i < order.size() && i < f.values.size(); ++i) {
    out[order[i]] = f.values[i];
  }
  return out;
}

// docs/sweep-phase/1-harness-rebuild.md: reproduced verbatim from pipeline.cpp's anonymous
// namespace (ref_fix.md F22) -- is `value` outside the regressor's own [min, max] from the
// training/eval CSV, UNWIDENED by feature_domain's upper_multiplier/lower_multiplier? Those
// multipliers exist to admit an uncut mask past the (inert, in this CLI) domain gate, but a
// vector past the raw max is answered from the edge leaf, not interpolated. domain.max <=
// 0.0 (no manifest data for this feature) means "not extrapolated" for it, matching
// feature_in_domain's own "gate disabled" convention.
bool feature_extrapolated(double value, const WeightCapability::FeatureDomain& domain) {
  if (domain.max <= 0.0) return false;
  return !std::isfinite(value) || value < domain.min || value > domain.max;
}

// ref_fix.md F22, generalized: which GATED features (the ones a regressor could plausibly
// have "pinned" at an edge leaf, matching run_feature_domain_gate's own eligibility set)
// fell outside the regressor's raw trained [min, max], unwidened by any multiplier.
json extrapolated_feature_names(const std::vector<std::string>& feature_order,
                                 const std::map<std::string, WeightCapability::FeatureDomain>& domains,
                                 const std::map<std::string, double>& values) {
  json out = json::array();
  for (const auto& name : feature_order) {
    auto domain_it = domains.find(name);
    if (domain_it == domains.end() || !domain_it->second.gate) continue;
    if (feature_extrapolated(values.at(name), domain_it->second)) out.push_back(name);
  }
  return out;
}

std::vector<float> ordered_feature_vector(const std::vector<std::string>& order,
                                           const std::map<std::string, double>& values) {
  std::vector<float> out;
  out.reserve(order.size());
  for (const auto& name : order) {
    auto it = values.find(name);
    out.push_back(static_cast<float>(it != values.end() ? it->second : 0.0));
  }
  return out;
}

// ---- one segmentation attempt, mirroring pipeline.cpp's ladder loop body -----------------
struct Attempt {
  double multiplier;
  float conf_threshold;  // <= 0 means "use the manifest default"
};

struct LadderResult {
  bool any_detection = false;
  double best_diag = -1.0;
  int selected_rung = -1;
  stages::SegmentationOutput seg_output;
  stages::PigMask pig_mask;
  std::string last_error;
};

LadderResult run_ladder(OnnxRunner* seg_runner, const SegmentationCapability& seg_cap,
                         const WeightCapability& weight_cap, const std::string& image_path,
                         double cm_per_px_actual_for_canvas, bool scale_aware,
                         const std::vector<Attempt>& attempts) {
  LadderResult result;
  for (size_t i = 0; i < attempts.size() && result.best_diag < weight_cap.min_mask_diagonal_fraction;
       ++i) {
    stages::SegmentationOutput attempt_seg;
    std::string seg_error;
    const double input_cm_per_px =
        scale_aware ? seg_cap.input_cm_per_px * attempts[i].multiplier : 0.0;
    const double cm_per_px_actual = scale_aware ? cm_per_px_actual_for_canvas : 0.0;
    const bool seg_ok = stages::run_segmentation(seg_runner, seg_cap, image_path, cm_per_px_actual,
                                                  input_cm_per_px, attempts[i].conf_threshold,
                                                  &attempt_seg, &seg_error);
    if (!seg_ok) {
      result.last_error = seg_error;
      continue;
    }
    if (!attempt_seg.has_detection) continue;
    result.any_detection = true;
    stages::PigMask attempt_mask = stages::construct_pig_mask(attempt_seg);
    if (attempt_mask.empty()) continue;
    const double diag = mask_diagonal_fraction(attempt_mask);
    if (diag > result.best_diag) {
      result.best_diag = diag;
      result.selected_rung = int(i);
      result.seg_output = attempt_seg;
      result.pig_mask = attempt_mask;
    }
  }
  return result;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 4) {
    std::fprintf(stderr, "usage: %s <manifest_path> <image_path> <cm_per_px_actual>\n", argv[0]);
    return 2;
  }
  const std::string manifest_path = argv[1];
  const std::string image_path = argv[2];
  const double cm_per_px_actual = std::atof(argv[3]);

  json envelope;
  envelope["image"] = image_path;
  envelope["cm_per_px_actual"] = cm_per_px_actual;

  // ---- step 1: load manifest ----------------------------------------------------------
  Manifest manifest;
  std::string error;
  int error_code = 0;
  if (!load_manifest(manifest_path, &manifest, &error, &error_code)) {
    std::fprintf(stderr, "load_manifest failed: %s (code %d)\n", error.c_str(), error_code);
    return 2;
  }
  envelope["cm_per_px_target"] = manifest.weight.cm_per_px_target;

  // AGENTS.md rule 2 / phase 2 step 10: refuse to proceed on an assumed feature order.
  static const std::vector<std::string> kCanonicalChen16Order = {
      "mask_area", "convex_hull_area", "difference", "dif_mask", "body_curve", "perimeter",
      "outline_curve", "longest", "shortest", "Hu_1", "Hu_2", "Hu_3", "Hu_4", "Hu_5", "Hu_6", "Hu_7"};
  if (manifest.weight.feature_family != "chen16_noheight") {
    std::fprintf(stderr, "expected feature_family chen16_noheight, manifest declares %s\n",
                 manifest.weight.feature_family.c_str());
    return 2;
  }
  if (manifest.weight.feature_order != kCanonicalChen16Order) {
    std::fprintf(stderr, "manifest.weight.feature_order does not match the canonical chen16 order\n");
    return 2;
  }

  // ---- step 2: load the two ONNX sessions ----------------------------------------------
  OnnxRunner seg_runner;
  std::string seg_load_error;
  if (!seg_runner.load(manifest.segmentation.model_path, &seg_load_error)) {
    std::fprintf(stderr, "segmentation model load failed: %s\n", seg_load_error.c_str());
    return 2;
  }
  OnnxRunner weight_runner;
  std::string weight_load_error;
  if (!weight_runner.load(manifest.weight.model_path, &weight_load_error)) {
    std::fprintf(stderr, "weight model load failed: %s\n", weight_load_error.c_str());
    return 2;
  }

  bool gates_would_have_withheld = false;
  json gates_would_have_withheld_reasons = json::array();

  // ---- step 3: segmentation with the retry ladder, plus the letterbox fallback --------
  const bool scale_aware_requested =
      std::isfinite(cm_per_px_actual) && cm_per_px_actual > 0.0 &&
      manifest.segmentation.input_cm_per_px > 0.0;

  std::vector<Attempt> attempts;
  if (scale_aware_requested) {
    for (double m : manifest.segmentation.scale_ladder_multipliers) attempts.push_back({m, 0.0f});
    if (manifest.segmentation.retry_conf_threshold > 0.0f) {
      for (double m : manifest.segmentation.scale_ladder_multipliers) {
        attempts.push_back({m, manifest.segmentation.retry_conf_threshold});
      }
    }
  } else {
    attempts.push_back({0.0, 0.0f});
  }

  LadderResult ladder = run_ladder(&seg_runner, manifest.segmentation, manifest.weight, image_path,
                                    cm_per_px_actual, scale_aware_requested, attempts);
  std::string canvas_mode = scale_aware_requested ? "scale_aware" : "letterbox_fallback";

  // Phase 2 plan step 3: if scale-aware composition never got a detection at all, retry
  // once with the plain whole-frame letterbox before giving up -- this is a deliberate
  // deviation from pipeline.cpp (which has no such fallback), added because these 960x540
  // PIGRGB images are smaller than the phone captures input_cm_per_px was tuned for.
  if (scale_aware_requested && !ladder.any_detection) {
    std::vector<Attempt> fallback_attempts = {{0.0, 0.0f}};
    ladder = run_ladder(&seg_runner, manifest.segmentation, manifest.weight, image_path,
                         cm_per_px_actual, /*scale_aware=*/false, fallback_attempts);
    canvas_mode = "letterbox_fallback";
  }
  envelope["canvas_mode"] = canvas_mode;

  if (ladder.best_diag < 0.0) {
    envelope["segmentation_status"] = ladder.any_detection ? "empty_mask" : "no_detection";
    envelope["predicted_kg"] = nullptr;
    envelope["gates_would_have_withheld"] = true;
    envelope["gates_would_have_withheld_reasons"] = json::array({"no_usable_segmentation"});
    std::printf("%s\n", envelope.dump().c_str());
    return 0;
  }

  const stages::SegmentationOutput& seg_output = ladder.seg_output;
  const stages::PigMask& pig_mask = ladder.pig_mask;

  envelope["segmentation_status"] = "ok";
  envelope["ladder_rung"] = ladder.selected_rung;
  envelope["input_cm_per_px_used"] = seg_output.input_cm_per_px_used;
  envelope["content_scale"] = seg_output.content_scale;
  envelope["clamped_to_letterbox"] = seg_output.clamped_to_letterbox;
  envelope["seg_conf"] = seg_output.box.conf;
  envelope["candidates_kept"] = seg_output.candidates_kept;
  envelope["mask_w"] = pig_mask.width;
  envelope["mask_h"] = pig_mask.height;
  envelope["mask_area_px"] = pig_mask.area_px;

  // ---- step 4: mask diagonal gate (recorded, not enforced -- see file header) ---------
  const double mask_diag_fraction = mask_diagonal_fraction(pig_mask);
  envelope["mask_diagonal_fraction"] = mask_diag_fraction;
  const bool mask_diag_gate_pass = mask_diag_fraction >= manifest.weight.min_mask_diagonal_fraction;
  if (!mask_diag_gate_pass) {
    gates_would_have_withheld = true;
    gates_would_have_withheld_reasons.push_back("mask_implausibly_small");
  }

  // ---- step 5: the scale step -- the one line this whole test exists to measure -------
  bool scale_ok = false;
  double k = 0.0;
  std::string scale_failure_reason;
  double height_ratio = 0.0;
  double implied_camera_height_m = 0.0;
  if (!manifest.weight.available) {
    scale_failure_reason = "weight_capability_unavailable";
  } else if (!std::isfinite(cm_per_px_actual) || cm_per_px_actual <= 0.0) {
    scale_failure_reason = "reference_object_not_confirmed";
  } else {
    k = cm_per_px_actual / manifest.weight.cm_per_px_target;
    const double capture_scale = std::sqrt(double(pig_mask.width) * double(pig_mask.height));
    const double training_scale = std::sqrt(double(manifest.weight.training_frame_w) *
                                             double(manifest.weight.training_frame_h));
    height_ratio = training_scale > 0.0 ? k * capture_scale / training_scale : 0.0;
    implied_camera_height_m = manifest.weight.training_camera_height_m * height_ratio;
    constexpr double kMinValidHeightRatio = 0.25;
    constexpr double kMaxValidHeightRatio = 4.0;
    if (!std::isfinite(height_ratio) || height_ratio < kMinValidHeightRatio ||
        height_ratio > kMaxValidHeightRatio) {
      scale_failure_reason = "scale_out_of_range";
    } else {
      scale_ok = true;
    }
  }
  envelope["k"] = k;
  envelope["height_ratio"] = height_ratio;
  envelope["implied_camera_height_m"] = implied_camera_height_m;
  envelope["scale_ok"] = scale_ok;
  if (!scale_ok) {
    envelope["scale_failure_reason"] = scale_failure_reason;
    gates_would_have_withheld = true;
    gates_would_have_withheld_reasons.push_back(scale_failure_reason);
  }

  // ---- step 6: resample into the regressor's training pixel space ---------------------
  // docs/fix-3.md (round 7) F55: pipeline.cpp now composes one transform straight from the
  // 640 binary mask -- transform_mask_to_training_space(seg_output, k) -- instead of
  // scale_mask_to_training_space(pig_mask, k) on top of construct_pig_mask's unletterbox.
  // Mirrored here so this harness still measures the same arithmetic the app runs
  // (docs/fix-phase-3/4 validates the jitter change against jitter_sweep.py's baselines).
  // The no-reference cap path stays on scale_mask_to_training_space (F58: no `k`, no
  // calibrated target space to compose into -- it is a size cap, not a calibration).
  constexpr int kUnscaledCutterMaxDimPx = 2880;
  stages::PigMask scaled_mask;
  const stages::PigMask* mask_for_cutter = &pig_mask;
  if (scale_ok) {
    scaled_mask = stages::transform_mask_to_training_space(seg_output, k);
    if (!scaled_mask.empty()) {
      mask_for_cutter = &scaled_mask;
    } else {
      scale_ok = false;
      gates_would_have_withheld = true;
      gates_would_have_withheld_reasons.push_back("scale_resample_failed");
    }
  }
  if (!scale_ok) {
    const int longest_dim = std::max(mask_for_cutter->width, mask_for_cutter->height);
    if (longest_dim > kUnscaledCutterMaxDimPx) {
      const double cap_k = double(kUnscaledCutterMaxDimPx) / double(longest_dim);
      stages::PigMask capped = stages::scale_mask_to_training_space(pig_mask, cap_k);
      if (!capped.empty()) {
        scaled_mask = std::move(capped);
        mask_for_cutter = &scaled_mask;
      }
    }
  }
  envelope["scaled_w"] = mask_for_cutter->width;
  envelope["scaled_h"] = mask_for_cutter->height;
  envelope["scaled_area_px"] = mask_for_cutter->area_px;
  envelope["composed_transform_used"] = scale_ok;

  // ---- step 7: quality gates -- manifest currently ships both false; reproduced but ---
  // inert. Not enforced even when true (see file header): recorded only.
  if (manifest.weight.quality_gate_truncation || manifest.weight.quality_gate_posture) {
    // Left unimplemented deliberately: the committed manifest ships both flags false
    // (docs/test-plan-phase/2-host-cli.md step 7), so exercising the real gate stages here
    // would require pulling in stages/quality_gates.h/.cpp for a codepath this specific
    // sweep never reaches. If a future manifest turns either flag on, this harness must be
    // extended before its results can be trusted, and it says so instead of a silent no-op.
    std::fprintf(stderr,
                 "manifest enables a quality gate (truncation=%d, posture=%d) this CLI does "
                 "not implement -- extend weight_branch_cli.cpp before trusting this run\n",
                 manifest.weight.quality_gate_truncation, manifest.weight.quality_gate_posture);
    return 2;
  }

  // ---- step 8: the cutter ---------------------------------------------------------------
  stages::MaskView mask_view{mask_for_cutter->pixels.data(), mask_for_cutter->width,
                              mask_for_cutter->height};
  stages::CutterResult cutter_result = stages::cut_body_mask(mask_view);
  const long long pre_cut_area = mask_for_cutter->area_px;
  const long long post_cut_area =
      std::count(cutter_result.mask.begin(), cutter_result.mask.end(), uint8_t(1));
  const double kept_fraction =
      pre_cut_area > 0 ? double(post_cut_area) / double(pre_cut_area) : 0.0;
  envelope["cutter_status"] = cutter_result.status;
  envelope["head_removal_applied"] = cutter_result.head_removal_applied;
  envelope["pre_cut_area"] = pre_cut_area;
  envelope["post_cut_area"] = post_cut_area;
  envelope["kept_fraction"] = kept_fraction;

  if (!cutter_result.ok()) {
    gates_would_have_withheld = true;
    gates_would_have_withheld_reasons.push_back("cutter_failed_" + cutter_result.status);
    envelope["predicted_kg"] = nullptr;
    envelope["gates_would_have_withheld"] = gates_would_have_withheld;
    envelope["gates_would_have_withheld_reasons"] = gates_would_have_withheld_reasons;
    std::printf("%s\n", envelope.dump().c_str());
    return 0;
  }

  // ---- step 9 + 10: Chen16 features, named positionally per feature_order -------------
  auto feats = stages::extract_chen16_features(cutter_result.mask, cutter_result.width,
                                                 cutter_result.height);
  if (!feats || !feats->valid) {
    gates_would_have_withheld = true;
    gates_would_have_withheld_reasons.push_back("contour_too_small");
    envelope["predicted_kg"] = nullptr;
    envelope["gates_would_have_withheld"] = gates_would_have_withheld;
    envelope["gates_would_have_withheld_reasons"] = gates_would_have_withheld_reasons;
    std::printf("%s\n", envelope.dump().c_str());
    return 0;
  }
  std::map<std::string, double> feature_values =
      chen16_values(manifest.weight.feature_order, *feats);
  for (const auto& name : manifest.weight.feature_order) {
    envelope[name] = feature_values.at(name);
  }

  // ---- step 11: domain gate (recorded, not enforced) -----------------------------------
  json domain_violations = json::array();
  const double uncertainty = manifest.weight.cm_per_px_target_uncertainty;
  const bool in_domain = run_feature_domain_gate(manifest.weight.feature_order,
                                                  manifest.weight.feature_domain, feature_values,
                                                  uncertainty, &domain_violations);
  envelope["domain_violations"] = domain_violations;
  if (!in_domain) {
    gates_would_have_withheld = true;
    gates_would_have_withheld_reasons.push_back("feature_domain_violation");
  }

  // ---- step 11.5: extrapolation telemetry (docs/sweep-phase/1-harness-rebuild.md) -----
  // Computed unconditionally, like every other gate this CLI records rather than enforces
  // (see file header): the app only surfaces this when the domain gate above passed AND
  // predict_weight succeeded, but this harness always predicts, so it always reports it.
  json extrapolated_features = extrapolated_feature_names(
      manifest.weight.feature_order, manifest.weight.feature_domain, feature_values);
  envelope["extrapolated"] = !extrapolated_features.empty();
  envelope["extrapolated_features"] = extrapolated_features;

  // ---- step 12: predict -- always, regardless of any gate above (see file header) -----
  const std::vector<float> feature_vector =
      ordered_feature_vector(manifest.weight.feature_order, feature_values);
  stages::WeightPredictionResult weight = stages::predict_weight(&weight_runner, feature_vector);
  if (!weight.ok) {
    std::fprintf(stderr, "predict_weight failed: %s\n", weight.error.c_str());
    envelope["predicted_kg"] = nullptr;
    envelope["predict_error"] = weight.error;
  } else {
    envelope["predicted_kg"] = weight.weight_kg;
  }

  envelope["gates_would_have_withheld"] = gates_would_have_withheld;
  envelope["gates_would_have_withheld_reasons"] = gates_would_have_withheld_reasons;

  std::printf("%s\n", envelope.dump().c_str());
  return 0;
}
