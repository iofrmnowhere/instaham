#include "pipeline.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <string>
#include <utility>
#include <vector>

#include "health_input.h"
#include "stages/construction.h"
#include "stages/cutter.h"
#include "stages/feature_calculation.h"
#include "stages/quality_gates.h"
#include "stages/segmentation.h"
#include "stages/weight_prediction.h"
#include "third_party/nlohmann_json/single_include/nlohmann/json.hpp"

namespace instaham_ml {
namespace {

using json = nlohmann::json;

json parse_or_empty(const std::string& s) {
  try {
    return json::parse(s);
  } catch (const std::exception&) {
    return json::object();
  }
}

json stopped_envelope(const json& view_json, const std::string& reason) {
  return json{{"status", "stopped"}, {"reason", reason}, {"view", view_json}};
}

json unavailable(const std::string& reason) {
  return json{{"status", "unavailable"}, {"reason", reason}};
}

json skipped(const std::string& reason) { return json{{"status", "skipped"}, {"reason", reason}}; }

// ref_fix.md F2: bounds the CAMERA-HEIGHT-implied ratio (capture height relative to the
// 1.88m training height), not the raw k = cm_per_px_actual / cm_per_px_target. k also
// carries a resolution term (training_frame_px is 720x720; a capture can be 1280, 1920,
// 3000+ px wide) that a bound on k directly conflates with height -- see ref_fix.md
// section 1 for the bug this replaced: a perfectly-framed 3000px photo at exactly 1.88m
// was being rejected as "out of range" purely because of its pixel count.
constexpr double kMinValidHeightRatio = 0.25;
constexpr double kMaxValidHeightRatio = 4.0;

// docs/fix-phase-2/1-cutter-freeze.md F43: when scale_ok is false, mask_for_cutter falls
// back to the raw captured-pixel mask (full capture resolution, e.g. 3000x4000) rather than
// the training-normalized one. The scaled path above is bounded -- a resized mask's
// geometric mean is height_ratio * training_scale, and with training_scale = sqrt(720*720)
// = 720 and kMaxValidHeightRatio = 4.0, it cannot exceed about 2880x2880. This constant
// applies that same bound to the unscaled fallback, so the vendor cutter (shrinking-ball,
// Selle filter, terminal-trunk) never sees more pixels than it already handles on the
// scaled path, without removing the provisional-debugging visibility the fallback exists
// for (pipeline.cpp's cutter/features telemetry stays populated even with no reference
// marked).
constexpr int kUnscaledCutterMaxDimPx = 2880;

// ref_fix.md F1: every scale-branch rejection carries its own reason so
// envelope["weight"]["reason"] can name it exactly -- previously every rejection
// collapsed to the single hardcoded "scale_unavailable", which told a user with a
// correctly-marked but resolution-rejected reference to "mark a reference object".
std::string scale_user_message_key(const std::string& reason) {
  if (reason == "reference_object_not_confirmed") return "weight_needs_reference_object";
  if (reason == "scale_out_of_range") return "weight_scale_out_of_range";
  if (reason == "scale_resample_failed") return "weight_scale_resample_failed";
  if (reason == "weight_capability_unavailable") {
    return "weight_unavailable_cutter_not_implemented";
  }
  return "weight_needs_reference_object";
}

// ref_fix.md F8/F9, generalized by docs/plan-phase/3-manifest-pipeline.md: is `value`
// inside [domain.min * domain.lower_multiplier / uncertainty_pow, domain.max *
// domain.upper_multiplier * uncertainty_pow]? domain.max <= 0.0 means the manifest carried
// no data for this feature (an older export fragment) -- the gate is disabled for that one
// feature rather than rejecting every prediction outright, since a partial manifest is
// still better checked than not at all. `uncertainty_pow` folds in
// manifest.weight.cm_per_px_target_uncertainty raised to the power appropriate for this
// feature's `dimension` (F9) -- 1.0 when the manifest declares no uncertainty, so an older
// manifest behaves exactly as before. On failure, appends a structured entry to
// *violations (feature/value/allowed_min/allowed_max/direction/dimension) and
// "<name>=<value> " to *violations_detail, so both a machine-readable and a human-readable
// trail exist for which feature(s) put the vector outside the trained domain (ref_fix.md
// F6). `dimension` rides along on the violation entry so classify_domain_violation() below
// can tell a shape violation from a size one without hardcoding a feature name.
bool feature_in_domain(double value, const WeightCapability::FeatureDomain& domain,
                        double uncertainty_pow, const std::string& name, json* violations,
                        std::string* violations_detail) {
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
    *violations_detail += name + "=" + std::to_string(value) + " ";
    return false;
  }
  return true;
}

// docs/plan-phase/3-manifest-pipeline.md: the calibration-uncertainty widening exponent for
// a feature's dimension -- area scales with k^2, a linear length with k^1, a dimensionless
// ratio/angle/moment not at all. `dimension` is data from the manifest (ML/export/
// export_xgboost.py's per-family feature-meta tables), not a compiled-in table.
double uncertainty_exponent(const std::string& dimension) {
  if (dimension == "area") return 2.0;
  if (dimension == "linear") return 1.0;
  return 0.0;  // "dimensionless"
}

// ref_fix.md F7/F17, generalized by docs/plan-phase/3-manifest-pipeline.md: names WHY the
// vector fell outside the trained domain, so the message the user sees matches the actual
// failure instead of always pointing at the reference object. A `dimensionless` feature
// (baseline5's `E`/eccentricity; chen16_noheight gates none, since "Do not gate on all
// sixteen" keeps every dimensionless chen16 feature diagnostic-only) is scale-invariant, so
// a violation on it means the mask itself is the wrong shape (curled pig, merged pen-mate,
// bad segmentation), unrelated to the reference object.
//
// ref_fix.md F17 (round 3): ANY dimensionless-feature violation now routes to
// `mask_shape_out_of_domain`, full stop, even when size features also violated -- round 2
// required it to violate ALONE, which routed a real 118kg sample (E passing alongside
// failing RA/LC/BL) to the reference-object message. A broken mask drags the size features
// off as a SIDE EFFECT of being the wrong shape; the shape violation is the cause, not a
// co-symptom to be outvoted. A violation on only the size features (area/linear), all on
// the low side and with every dimensionless feature intact, means the subject is smaller
// than anything the regressor's eval set contained. Anything else (shape features intact, a
// size feature running high) keeps the original reason, since a high size violation is the
// one case a mis-marked or mis-scaled reference object plausibly explains.
std::string classify_domain_violation(const json& violations) {
  bool any_shape = false;
  bool any_size = false;
  bool all_size_low = true;
  for (const auto& v : violations) {
    if (v.value("dimension", "") == "dimensionless") {
      any_shape = true;
    } else {
      any_size = true;
      if (v.value("direction", "") != "low") all_size_low = false;
    }
  }
  if (any_shape) return "mask_shape_out_of_domain";
  if (any_size && all_size_low) return "subject_smaller_than_trained";
  return "features_out_of_training_domain";
}

std::string domain_user_message_key(const std::string& reason) {
  if (reason == "mask_shape_out_of_domain") return "weight_mask_shape_out_of_range";
  if (reason == "subject_smaller_than_trained") return "weight_subject_smaller_than_trained";
  return "weight_features_out_of_range";
}

// ref_fix.md F16/F19/F23: the constructed mask's bounding-box diagonal as a fraction of the
// image's own diagonal -- what both the retry ladder (F19) and the plausibility gate (F16,
// now at F23's raised 0.35 threshold) measure. Shared so the two can never diverge on what
// "plausible" means.
double mask_diagonal_fraction(const stages::PigMask& mask) {
  const double mask_diag =
      std::sqrt(double(mask.bbox_w) * mask.bbox_w + double(mask.bbox_h) * mask.bbox_h);
  const double frame_diag =
      std::sqrt(double(mask.width) * mask.width + double(mask.height) * mask.height);
  return frame_diag > 0.0 ? mask_diag / frame_diag : 0.0;
}

// ref_fix.md F22: is `value` outside the regressor's own [min, max] from the training/eval
// CSV, UNWIDENED by feature_domain's upper_multiplier/lower_multiplier? Those multipliers
// exist to admit an uncut mask (AGENTS.md rule 3's eligibility check still needs to pass),
// but a vector they admit past the model's actual training range is a vector the regressor
// can only answer with its edge leaf -- pinned, not interpolated (ref_fix.md section 1.6).
// domain.max <= 0.0 (no manifest data for this feature) means "not extrapolated" for it,
// matching feature_in_domain's own "gate disabled" convention.
bool feature_extrapolated(double value, const WeightCapability::FeatureDomain& domain) {
  if (domain.max <= 0.0) return false;
  return !std::isfinite(value) || value < domain.min || value > domain.max;
}

// docs/plan-phase/3-manifest-pipeline.md: the five/sixteen-wide feature vector as an
// ordered name->value map, so the eligibility gate and the envelope can both walk
// `manifest.weight.feature_order` generically instead of five hardcoded field accesses.
std::map<std::string, double> baseline5_values(const stages::FiveFeatures& f) {
  return {{"RA", f.ra}, {"LC", f.lc}, {"BL", f.bl}, {"BW", f.bw}, {"E", f.e}};
}

std::map<std::string, double> chen16_values(const std::vector<std::string>& order,
                                             const stages::Chen16Features& f) {
  std::map<std::string, double> out;
  for (size_t i = 0; i < order.size() && i < f.values.size(); ++i) {
    out[order[i]] = f.values[i];
  }
  return out;
}

// `feature_order`-ordered vector<float>, exactly what predict_weight's ONNX graph expects
// (shape {1, N}). Missing entries (should not happen once feature_order and the values map
// agree) become 0.0f rather than throwing, since a malformed manifest is caught earlier at
// load_manifest() -- this is not the place to newly introduce a crash.
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

// docs/plan-phase/3-manifest-pipeline.md, "The domain gate becomes a loop": runs
// feature_in_domain() for every GATED feature in `feature_order` (docs' "Do not gate on all
// sixteen" -- a feature whose manifest entry declares `gate: false` is diagnostic-only and
// never enforced here), widening each by `uncertainty` raised to its own dimension's
// exponent. Every feature is checked and every violation recorded -- ok is computed before
// being folded into the running result, so nothing here short-circuits past a later
// violation the way `&&` on the whole expression would.
bool run_feature_domain_gate(const std::vector<std::string>& feature_order,
                              const std::map<std::string, WeightCapability::FeatureDomain>& domains,
                              const std::map<std::string, double>& values, double uncertainty,
                              json* violations, std::string* violations_detail) {
  bool in_domain = true;
  for (const auto& name : feature_order) {
    auto domain_it = domains.find(name);
    if (domain_it == domains.end() || !domain_it->second.gate) continue;
    const double uncertainty_pow = std::pow(uncertainty, uncertainty_exponent(domain_it->second.dimension));
    const bool ok = feature_in_domain(values.at(name), domain_it->second, uncertainty_pow, name,
                                       violations, violations_detail);
    in_domain = in_domain && ok;
  }
  return in_domain;
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

}  // namespace

bool run_pipeline(const PipelineRunners& runners, const Manifest& manifest,
                   const std::string& image_path, const double* cm_per_px,
                   std::string* out_json) {
  if (image_path.empty() || !out_json) {
    if (out_json) *out_json = unavailable("invalid_argument").dump();
    return false;
  }

  json envelope;
  envelope["pipeline_protocol"] = "instaham_pipeline_v4";

  // ---- view: gates everything downstream (section 1.1(a)) ----
  json view_json = json::object();
  std::string view_label;
  if (manifest.view.available && runners.view) {
    std::string raw;
    int err = 0;
    run_classifier(runners.view, manifest.view, image_path, &raw, &err, nullptr);
    view_json = parse_or_empty(raw);
    view_label = view_json.value("label", "");
  } else {
    view_json = unavailable("view capability not available in this manifest");
  }
  envelope["view"] = view_json;

  if (view_label == "reject") {
    *out_json = stopped_envelope(view_json, "view_rejected").dump();
    return true;
  }

  const bool is_dorsal = view_label == "dorsal_valid";
  const bool is_health_only = view_label == "health_only";
  if (!is_dorsal && !is_health_only) {
    // View unavailable or an unrecognised label -- fail closed rather than guess a route
    // (AGENTS.md rule 8). Health and weight are both reported skipped, not silently absent.
    envelope["status"] = "ok";
    envelope["segmentation"] = skipped("view_unresolved");
    envelope["construction"] = skipped("view_unresolved");
    envelope["cutter"] = skipped("view_unresolved");
    envelope["features"] = skipped("view_unresolved");
    envelope["weight"] = skipped("view_unresolved");
    envelope["health"] = skipped("view_unresolved");
    *out_json = envelope.dump();
    return true;
  }

  // ---- stage 1 + 2: segmentation, construction. Feeds both health input and weight. ----
  // TASKS.md P0 (2026-08-30): gated to is_dorsal only. health_input.cpp's region protocols
  // (segmentation_crop / segmentation_masked) are all stubs that degrade to full_frame
  // (health_input.h), so on the health_only branch this ~640x640 YOLO pass fed nothing --
  // it ran only because "feeds health input" used to be true in principle. Skipping it here
  // is what makes health_only cheaper than dorsal_valid meaningful rather than accidental.
  stages::SegmentationOutput seg_output;
  stages::PigMask pig_mask;
  bool have_mask = false;

  if (is_dorsal && manifest.segmentation.available && runners.segmentation) {
    // ref_fix.md F18/F19: scale-aware composition only when a user-confirmed reference
    // exists AND the manifest declares input_cm_per_px (an older manifest fragment leaves
    // it at 0.0, which disables this and every attempt below falls back to the plain
    // whole-frame letterbox -- unchanged pre-F18 behaviour).
    const bool scale_aware = cm_per_px != nullptr && std::isfinite(*cm_per_px) &&
                              *cm_per_px > 0.0 && manifest.segmentation.input_cm_per_px > 0.0;

    struct Attempt {
      double multiplier;
      float conf_threshold;  // <= 0 means "use the manifest default"
    };
    std::vector<Attempt> attempts;
    if (scale_aware) {
      for (double m : manifest.segmentation.scale_ladder_multipliers) {
        attempts.push_back({m, 0.0f});
      }
      if (manifest.segmentation.retry_conf_threshold > 0.0f) {
        for (double m : manifest.segmentation.scale_ladder_multipliers) {
          attempts.push_back({m, manifest.segmentation.retry_conf_threshold});
        }
      }
    } else {
      attempts.push_back({0.0, 0.0f});  // one attempt, plain letterbox
    }

    // ref_fix.md F19: stop at the FIRST attempt whose constructed mask meets F23's
    // plausibility threshold -- not the best across all attempts, which would be a
    // different (unvalidated) selection criterion. If none do, keep the highest-diagonal
    // one so the existing F16 gate below still has a real mask to reject with a real
    // fraction, rather than reporting on an arbitrary attempt.
    bool any_detection = false;
    std::string last_seg_error;
    double best_diag = -1.0;
    int selected_rung = -1;
    json rungs_tried = json::array();
    for (size_t i = 0; i < attempts.size() && best_diag < manifest.weight.min_mask_diagonal_fraction;
         ++i) {
      stages::SegmentationOutput attempt_seg;
      std::string seg_error;
      const double input_cm_per_px =
          scale_aware ? manifest.segmentation.input_cm_per_px * attempts[i].multiplier : 0.0;
      const double cm_per_px_actual = scale_aware ? *cm_per_px : 0.0;
      const bool seg_ok = stages::run_segmentation(
          runners.segmentation, manifest.segmentation, image_path, cm_per_px_actual,
          input_cm_per_px, attempts[i].conf_threshold, &attempt_seg, &seg_error);
      json rung_json = {
          {"rung", int(i)},
          {"multiplier", attempts[i].multiplier},
          {"conf_threshold_used",
           attempts[i].conf_threshold > 0.0f ? attempts[i].conf_threshold
                                              : manifest.segmentation.conf_threshold},
          {"input_cm_per_px_used", attempt_seg.input_cm_per_px_used},
          {"content_scale", attempt_seg.content_scale},
          {"clamped_to_letterbox", attempt_seg.clamped_to_letterbox},
      };
      if (!seg_ok) {
        last_seg_error = seg_error;
        rung_json["result"] = "error";
        rung_json["reason"] = seg_error;
        rungs_tried.push_back(rung_json);
        continue;
      }
      if (!attempt_seg.has_detection) {
        rung_json["result"] = "no_instance_above_conf";
        rungs_tried.push_back(rung_json);
        continue;
      }
      any_detection = true;
      rung_json["candidates_kept"] = attempt_seg.candidates_kept;
      stages::PigMask attempt_mask = stages::construct_pig_mask(attempt_seg);
      if (attempt_mask.empty()) {
        rung_json["result"] = "empty_mask";
        rungs_tried.push_back(rung_json);
        continue;
      }
      const double diag = mask_diagonal_fraction(attempt_mask);
      rung_json["result"] = "ok";
      rung_json["mask_diagonal_fraction"] = diag;
      rungs_tried.push_back(rung_json);
      if (diag > best_diag) {
        best_diag = diag;
        selected_rung = int(i);
        seg_output = attempt_seg;
        pig_mask = attempt_mask;
      }
    }

    if (best_diag < 0.0) {
      envelope["segmentation"] =
          any_detection ? json{{"status", "error"}, {"reason", "empty_mask"}}
                         : json{{"status", "error"},
                                {"reason", last_seg_error.empty() ? "no_instance_above_conf"
                                                                   : last_seg_error}};
      envelope["segmentation"]["rungs_tried"] = rungs_tried;
      envelope["construction"] = skipped(any_detection ? "empty_mask" : "no_instance");
    } else {
      // ref_fix.md F15: candidates_kept/*_mask_area_proto/selected_box_* are what would
      // have shown F12's bug directly -- candidates_kept > 1 with a near-tied runner-up
      // area, and a selected_box_frame_fraction of ~1-9% against the true pig's ~55-85%.
      // ref_fix.md F18/F19/F20: ladder_rung/rungs_tried/content_scale/input_cm_per_px_used
      // are what would have shown F18's bug directly -- a photo whose only usable rung is
      // not rung 0, or one where every rung stayed below F23's threshold.
      envelope["segmentation"] = json{
          {"status", "ok"},
          {"confidence", seg_output.box.conf},
          {"instances_found", 1},
          {"candidates_kept", seg_output.candidates_kept},
          {"selected_mask_area_proto", seg_output.selected_mask_area_proto},
          {"runner_up_mask_area_proto", seg_output.runner_up_mask_area_proto},
          {"selected_box_orig",
           {seg_output.selected_box_orig_x0, seg_output.selected_box_orig_y0,
            seg_output.selected_box_orig_x1, seg_output.selected_box_orig_y1}},
          {"selected_box_frame_fraction", seg_output.selected_box_frame_fraction},
          {"ladder_rung", selected_rung},
          {"rungs_tried", rungs_tried},
          {"content_scale", seg_output.content_scale},
          {"input_cm_per_px_used", seg_output.input_cm_per_px_used},
          {"clamped_to_letterbox", seg_output.clamped_to_letterbox},
      };
      have_mask = true;
      envelope["construction"] = json{
          {"status", "ok"},
          {"mask_protocol", "original_coordinate_polygon_v1"},
          {"mask_area_px", pig_mask.area_px},
          {"bbox", {pig_mask.bbox_x, pig_mask.bbox_y, pig_mask.bbox_w, pig_mask.bbox_h}},
          {"mask_diagonal_fraction", best_diag},
      };
    }
  } else if (!is_dorsal) {
    // health_only: segmentation is not required for this route (see comment above), not
    // unavailable -- health_input.cpp's region protocols degrade to full_frame regardless.
    envelope["segmentation"] = skipped("not_required_for_route");
    envelope["construction"] = skipped("not_required_for_route");
  } else {
    envelope["segmentation"] = unavailable("segmentation capability not available in this manifest");
    envelope["construction"] = skipped("segmentation_unavailable");
  }

  // ---- health: runs on both branches (section 1.1(b)), degrades its input, never blocks ----
  json health_json = json::object();
  if (manifest.health.available && runners.health) {
    HealthInputOptions health_opts;
    health_opts.protocol = parse_health_input_protocol(manifest.health.input_protocol);
    PigRegion region;
    if (have_mask) {
      region.x0 = pig_mask.bbox_x;
      region.y0 = pig_mask.bbox_y;
      region.x1 = pig_mask.bbox_x + pig_mask.bbox_w;
      region.y1 = pig_mask.bbox_y + pig_mask.bbox_h;
      region.has_mask = true;
      region.mask = pig_mask.pixels.data();
      region.mask_w = pig_mask.width;
      region.mask_h = pig_mask.height;
      health_opts.region = region.valid() ? &region : nullptr;
    }
    std::string raw;
    int err = 0;
    run_classifier(runners.health, manifest.health, image_path, &raw, &err, &health_opts);
    health_json = parse_or_empty(raw);
  } else {
    health_json = unavailable("health capability not available in this manifest");
  }
  envelope["health"] = health_json;

  // ---- scale: normalize the pig mask into the regressor's training pixel space ----
  // (TASKS.md W5 / ref_fix.md F1+F2). k = cm_per_px_actual / cm_per_px_target. This block
  // only ever narrows `scale_ok` from a default of false -- there is no path that defaults
  // it to true, so a request-level failure here can only ever withhold weight, never
  // fabricate one (AGENTS.md rule 8). `scale_failure_reason` stays empty exactly when
  // `scale_ok` is true, and is the single source both envelope["scale"]["reason"] and
  // envelope["weight"]["reason"] read from below -- the two can no longer disagree.
  bool scale_ok = false;
  double k = 0.0;
  std::string scale_failure_reason;
  if (is_dorsal && have_mask) {
    if (!manifest.weight.available) {
      scale_failure_reason = "weight_capability_unavailable";
      envelope["scale"] = skipped(scale_failure_reason);
    } else if (!cm_per_px || !std::isfinite(*cm_per_px) || *cm_per_px <= 0.0) {
      // AGENTS.md rule 7: cm/pixel comes ONLY from the user-confirmed reference object --
      // no reference, no scale, no implicit k = 1.0.
      scale_failure_reason = "reference_object_not_confirmed";
      envelope["scale"] = unavailable(scale_failure_reason);
    } else {
      k = *cm_per_px / manifest.weight.cm_per_px_target;
      // ref_fix.md F2: k alone conflates capture height with capture resolution (the
      // training frame is a fixed 720x720; a live capture is typically 1280px wide, a
      // gallery import up to 3000px). Divide the resolution term back out so the bound
      // below is actually a camera-height check, as it was always meant to be.
      const double capture_scale =
          std::sqrt(double(pig_mask.width) * double(pig_mask.height));
      const double training_scale =
          std::sqrt(double(manifest.weight.training_frame_w) *
                    double(manifest.weight.training_frame_h));
      const double height_ratio =
          training_scale > 0.0 ? k * capture_scale / training_scale : 0.0;
      const double implied_camera_height_m =
          manifest.weight.training_camera_height_m * height_ratio;
      if (!std::isfinite(height_ratio) || height_ratio < kMinValidHeightRatio ||
          height_ratio > kMaxValidHeightRatio) {
        scale_failure_reason = "scale_out_of_range";
        envelope["scale"] = json{
            {"status", "unavailable"},
            {"reason", scale_failure_reason},
            {"cm_per_px_actual", *cm_per_px},
            {"cm_per_px_target", manifest.weight.cm_per_px_target},
            {"k", k},
            {"height_ratio", height_ratio},
            {"implied_camera_height_m", implied_camera_height_m},
        };
      } else {
        scale_ok = true;
        envelope["scale"] = json{
            {"status", "ok"},
            {"cm_per_px_actual", *cm_per_px},
            {"cm_per_px_target", manifest.weight.cm_per_px_target},
            {"k", k},
            {"height_ratio", height_ratio},
            {"implied_camera_height_m", implied_camera_height_m},
            {"training_frame_px",
             {manifest.weight.training_frame_w, manifest.weight.training_frame_h}},
            {"source", "user_confirmed_reference"},
        };
      }
    }
  } else if (is_dorsal && !have_mask) {
    scale_failure_reason = "no_mask";
    envelope["scale"] = skipped(scale_failure_reason);
  } else {
    scale_failure_reason = "view_not_dorsal";
    envelope["scale"] = skipped(scale_failure_reason);
  }

  // ---- stage 3 + 4: cutter (real V176/V144 port, phase 2), feature calculation ----
  // Weight predicts only when BOTH the manifest opts in (test override) AND a valid scale
  // was established above -- AGENTS.md rule 3/8: every eligibility check must pass, and a
  // missing/invalid reference degrades this branch, it never falls back to unscaled pixels.
  if (is_dorsal && have_mask) {
    // Test override (ML/export/export_xgboost.py --enable-for-testing): only reachable
    // when the manifest deliberately sets weight.available true. AGENTS.md rule 8 stays
    // satisfied -- this is a real prediction from the runner, labelled with the same
    // provisional-calibration caveat instaham_ml_predict_weight_json carries, never a
    // fabricated value.
    const bool weight_override = manifest.weight.available && runners.weight;
    const std::string& feature_family = manifest.weight.feature_family;
    // docs/plan-phase/3-manifest-pipeline.md open question 1: weight.available stays
    // gated -- not on the cutter (real since phase 2) but on phase 5's field
    // re-derivation of cm_per_px_target from post-cut masks. "cutter_identity_stub" would
    // now be a false statement; this reason names what is actually still pending.
    json weight_unavailable_json = json{
        {"status", "unavailable"},
        {"reason", "weight_pending_field_validation"},
        {"user_message_key", "weight_unavailable_pending_field_validation"},
        {"capture_contract",
         {{"feature_space", "fixed_camera_pixels"},
          {"training_camera_height_m", manifest.weight.training_camera_height_m},
          {"camera_height_is_xgboost_feature", manifest.weight.camera_height_is_xgboost_feature}}},
    };

    // ref_fix.md F16: refuse a mask whose bounding-box diagonal is an implausibly small
    // fraction of the image's own diagonal BEFORE running the cutter/feature/domain
    // stages on it at all -- a mask this small isn't a pig (F12's bug produced 64x39 and
    // 14x3 px masks against a 2250x3000 frame), and a dimensionless shape feature's domain
    // check alone does not catch it: a thin sliver scores as an extreme shape, not
    // necessarily an out-of-domain one (ref_fix.md section 3, F17). Measured on the RAW
    // captured mask, before scale normalization -- resampling by k changes absolute size,
    // not the mask's proportion of its own frame.
    const double mask_diag_fraction = mask_diagonal_fraction(pig_mask);

    if (mask_diag_fraction < manifest.weight.min_mask_diagonal_fraction) {
      envelope["cutter"] = skipped("mask_implausibly_small");
      envelope["features"] = skipped("mask_implausibly_small");
      json mask_implausible_json = json{
          {"status", "unavailable"},
          {"reason", "mask_implausibly_small"},
          {"user_message_key", "weight_mask_implausibly_small"},
          {"mask_diagonal_fraction", mask_diag_fraction},
          {"min_required_fraction", manifest.weight.min_mask_diagonal_fraction},
      };
      envelope["weight"] = weight_override ? mask_implausible_json : weight_unavailable_json;
      envelope["status"] = "ok";
      *out_json = envelope.dump();
      return true;
    }

    // docs/plan-phase/3-manifest-pipeline.md, "The quality gates get a manifest switch":
    // both ported (phase 2) gates run on the WHOLE mask in original capture coordinates,
    // before Ji/Duan and before any scale-to-training-space resampling
    // (README_AI_INTEGRATION.md's coordinate constraint) -- ship dark (both manifest flags
    // default false in the shipped manifest) until phase 5 measures their real on-device
    // rejection rate. Truncation is checked first and names the rejection reason when both
    // gates reject, simply because it runs first here -- no other precedence is implied.
    {
      const stages::MaskView whole_mask_view{pig_mask.pixels.data(), pig_mask.width,
                                              pig_mask.height};
      json quality_gates_json = json::object();
      bool quality_gate_rejected = false;
      std::string quality_gate_reason;

      if (manifest.weight.quality_gate_truncation) {
        stages::TruncationGateResult trunc = stages::run_truncation_gate(whole_mask_view);
        quality_gates_json["truncation"] = json{
            {"status", trunc.valid ? "ok" : "analysis_failed"},
            {"reject", trunc.reject},
            {"candidate_strength", trunc.candidate_strength},
        };
        if (trunc.reject) {
          quality_gate_rejected = true;
          quality_gate_reason = "truncation_gate_rejected";
        }
      }
      if (manifest.weight.quality_gate_posture) {
        stages::PostureGateResult posture = stages::run_posture_gate(
            whole_mask_view, manifest.weight.quality_gate_posture_max_bend_deg);
        quality_gates_json["posture"] = json{
            {"status", posture.valid ? "ok" : "analysis_failed"},
            {"reject", posture.reject},
            {"body_curve_deg", posture.body_curve_deg},
            {"bend_deg", posture.bend_deg},
            {"max_bend_deg", manifest.weight.quality_gate_posture_max_bend_deg},
        };
        if (posture.reject && !quality_gate_rejected) {
          quality_gate_rejected = true;
          quality_gate_reason = "posture_gate_rejected";
        }
      }
      if (!quality_gates_json.empty()) envelope["quality_gates"] = quality_gates_json;

      if (quality_gate_rejected) {
        envelope["cutter"] = skipped(quality_gate_reason);
        envelope["features"] = skipped(quality_gate_reason);
        json quality_gate_rejected_json = json{
            {"status", "unavailable"},
            {"reason", quality_gate_reason},
            {"user_message_key", quality_gate_reason == "truncation_gate_rejected"
                                      ? "weight_truncation_gate_rejected"
                                      : "weight_posture_gate_rejected"},
        };
        envelope["weight"] =
            weight_override ? quality_gate_rejected_json : weight_unavailable_json;
        envelope["status"] = "ok";
        *out_json = envelope.dump();
        return true;
      }
    }

    // Cut and measure on the training-normalized mask when a scale is available, so the
    // cutter's pixel-space thresholds and the RA denominator both operate on the space the
    // regressor was trained in (TASKS.md section 3.3, Option B). Falls back to the raw
    // captured-pixel mask, unscaled, only to keep provisional debugging features visible
    // when no reference was marked.
    stages::PigMask scaled_mask;
    const stages::PigMask* mask_for_cutter = &pig_mask;
    if (scale_ok) {
      // docs/fix-3.md (round 7) F55: one composed transform straight from the 640x640 binary
      // mask into training pixel space, instead of construct_pig_mask's unletterbox-to-
      // capture-resolution followed by scale_mask_to_training_space -- two nearest-neighbour
      // rasterizations whose grid alignment depended on `k`, so one pixel of reference
      // marking moved the estimate by up to ~13% (docs/fix-phase-2/2.1). `seg_output` is the
      // ladder-selected attempt; transform_mask_to_training_space re-decodes its 640 mask
      // through the shared decode_binary_640 helper (pipeline.cpp stays OpenCV-free -- see
      // docs/fix-phase-3/2 Outcome). construct_pig_mask's output (pig_mask) is unchanged and
      // still feeds the quality gates above, in original capture coordinates.
      scaled_mask = stages::transform_mask_to_training_space(seg_output, k);
      if (!scaled_mask.empty()) {
        mask_for_cutter = &scaled_mask;
        if (envelope["construction"].is_object()) {
          envelope["construction"]["composed_transform"] = json{
              {"letterbox_scale", seg_output.letterbox_scale},
              {"k", k},
              {"out_w", scaled_mask.width},
              {"out_h", scaled_mask.height},
              {"out_area_px", scaled_mask.area_px},
          };
        }
      } else {
        scale_ok = false;
        scale_failure_reason = "scale_resample_failed";
        envelope["scale"] = json{{"status", "unavailable"}, {"reason", scale_failure_reason}};
      }
    }
    if (!scale_ok) {
      // F43: bound the unscaled fallback to the same pixel budget the scaled path already
      // guarantees, so a full-capture-resolution mask never reaches the cutter.
      const int longest_dim = std::max(mask_for_cutter->width, mask_for_cutter->height);
      if (longest_dim > kUnscaledCutterMaxDimPx) {
        const double cap_k = double(kUnscaledCutterMaxDimPx) / double(longest_dim);
        stages::PigMask capped = stages::scale_mask_to_training_space(pig_mask, cap_k);
        if (!capped.empty()) {
          scaled_mask = std::move(capped);
          mask_for_cutter = &scaled_mask;
        }
        // If capping itself fails, mask_for_cutter stays on the uncapped pig_mask -- the
        // cutter's own try/catch guards (and F44's, now) still bound the failure to a
        // decline rather than a crash, so this is a size-reduction best-effort, not a
        // second eligibility gate.
      }
    }

    stages::MaskView mask_view{mask_for_cutter->pixels.data(), mask_for_cutter->width,
                                mask_for_cutter->height};
    stages::CutterResult cutter_result = stages::cut_body_mask(mask_view);

    // docs/plan-phase/3-manifest-pipeline.md, "kept_fraction is ours, not the vendor's":
    // pre_cut_area/post_cut_area computed here in the app's own adapter, telemetry only,
    // never a gate -- VALIDATION.md states the V144 cutter itself does not compute or
    // return a kept-area fraction, and that omission is deliberate and kept. `mask_for_
    // cutter->area_px` is the pixel count of the SAME mask handed to the cutter (whichever
    // of pig_mask/scaled_mask that was), so this is comparable across a scaled or unscaled
    // run.
    const long long post_cut_area = std::count(cutter_result.mask.begin(),
                                                cutter_result.mask.end(), uint8_t(1));
    const double kept_fraction = mask_for_cutter->area_px > 0
                                      ? double(post_cut_area) / double(mask_for_cutter->area_px)
                                      : 0.0;
    envelope["cutter"] = json{
        {"status", cutter_result.status},
        {"head_removal_applied", cutter_result.head_removal_applied},
        {"protocol_version",
         "v176_strict_nonprimary_break1_region_meet_v144_fixed_center_bilateral_circle_v1"},
        {"protocol_implemented", true},
        {"kept_fraction", kept_fraction},
        {"removed_fraction", 1.0 - kept_fraction},
    };

    // ref_fix.md F1: the reason here is the SAME one already recorded on envelope["scale"]
    // above -- never a generic "scale_unavailable" regardless of what actually failed.
    json weight_scale_unavailable_json = json{
        {"status", "unavailable"},
        {"reason", scale_failure_reason.empty() ? "scale_unavailable" : scale_failure_reason},
        {"user_message_key", scale_user_message_key(scale_failure_reason)},
        {"capture_contract",
         {{"feature_space", "fixed_camera_pixels"},
          {"training_camera_height_m", manifest.weight.training_camera_height_m},
          {"camera_height_is_xgboost_feature", manifest.weight.camera_height_is_xgboost_feature}}},
    };

    if (cutter_result.ok()) {
      // docs/plan-phase/3-manifest-pipeline.md, "Select extract_five_features vs
      // extract_chen16_features on feature_family" -- chen16_noheight measures raw pixel
      // counts on the final cut mask (no ra_frame_w/h-style normalization: see
      // feature_calculation.h), while baseline5 keeps the training-frame normalization
      // scale_ok enables. scale_ok -> the mask cut above is already in training pixels, so
      // linear_scale stays 1.0 and RA's denominator is the manifest's training frame.
      // Without a scale, baseline5 reproduces the pre-W5 provisional-debug values exactly
      // (mask's own w/h, no frame override) -- never mistakeable for weight input given the
      // label below.
      std::map<std::string, double> feature_values;
      bool features_ok = false;
      std::string features_error;
      if (feature_family == "chen16_noheight") {
        auto feats = stages::extract_chen16_features(cutter_result.mask, cutter_result.width,
                                                       cutter_result.height);
        if (feats && feats->valid) {
          feature_values = chen16_values(manifest.weight.feature_order, *feats);
          features_ok = true;
        } else {
          features_error = "contour_too_small";
        }
      } else {
        auto feats = stages::extract_five_features(
            cutter_result.mask, cutter_result.width, cutter_result.height, 1.0,
            /*preserve_processed_mask=*/true,
            scale_ok ? manifest.weight.training_frame_w : 0,
            scale_ok ? manifest.weight.training_frame_h : 0);
        if (feats) {
          feature_values = baseline5_values(*feats);
          features_ok = true;
        } else {
          features_error = "contour_too_small";
        }
      }

      if (features_ok) {
        json values_json = json::object();
        for (const auto& name : manifest.weight.feature_order) {
          values_json[name] = feature_values.at(name);
        }
        // docs/plan-phase/4-dart-persistence-ui.md: the Dart rejection renderer shows the
        // GATED features only ("Do not gate on all sixteen") and must be driven by the
        // envelope, not a second hardcoded feature list. A feature is gated exactly when
        // pipeline.cpp's own domain gate would check it: FeatureDomain.gate && max > 0.
        json gated_json = json::array();
        for (const auto& name : manifest.weight.feature_order) {
          auto it = manifest.weight.feature_domain.find(name);
          if (it != manifest.weight.feature_domain.end() && it->second.gate &&
              it->second.max > 0.0) {
            gated_json.push_back(name);
          }
        }
        envelope["features"] = json{
            {"status", "provisional"},
            {"family", feature_family},
            {"order", manifest.weight.feature_order},
            {"gated", gated_json},
            {"values", values_json},
            {"measured_on", scale_ok ? "training_normalized_mask" : "uncut_mask_unnormalized"},
        };
        if (weight_override && scale_ok) {
          // ref_fix.md F3/F9, generalized: gate on whether the trained regressor has ever
          // seen anything like this normalized feature vector -- the principled check the
          // resolution-blind k-range bound (fixed in F2) was only ever a proxy for. Runs
          // AFTER normalization, so it is checking the same space the manifest's
          // feature_domain values were measured in. `uncertainty` widens each GATED
          // feature's bounds by the manifest's own declared cm_per_px_target calibration
          // uncertainty (clamped >= 1.0 at load time), raised to that feature's own
          // dimension exponent, so the gate is never stricter than the calibration it rests
          // on. Only gated features (area/linear -- "Do not gate on all sixteen") are
          // checked; every dimensionless feature is diagnostic-only.
          const double uncertainty = manifest.weight.cm_per_px_target_uncertainty;
          json domain_violations = json::array();
          std::string domain_violations_detail;
          const bool in_domain = run_feature_domain_gate(
              manifest.weight.feature_order, manifest.weight.feature_domain, feature_values,
              uncertainty, &domain_violations, &domain_violations_detail);
          if (!in_domain) {
            // ref_fix.md F7: name WHY, not just THAT, the vector fell outside the domain.
            const std::string reason = classify_domain_violation(domain_violations);
            envelope["weight"] = json{
                {"status", "unavailable"},
                {"reason", reason},
                {"user_message_key", domain_user_message_key(reason)},
                {"detail", domain_violations_detail},
                {"violations", domain_violations},
            };
          } else {
            const std::vector<float> feature_vector =
                ordered_feature_vector(manifest.weight.feature_order, feature_values);
            auto weight = stages::predict_weight(runners.weight, feature_vector);
            if (weight.ok) {
              // ref_fix.md F22, generalized: check the UNWIDENED trained [min, max] on
              // every GATED feature -- the domain gate above already passed the widened
              // bounds, but a gradient-boosted regressor cannot extrapolate past what it
              // was actually trained on: a vector past the raw max is answered from the
              // edge leaf, a real, silent ceiling measured at ref_fix.md section 1.6.
              // Surface it rather than presenting a saturated value with the same
              // confidence as an interpolated one.
              json extrapolated_features = extrapolated_feature_names(
                  manifest.weight.feature_order, manifest.weight.feature_domain,
                  feature_values);
              envelope["weight"] = json{
                  {"status", "ok"},
                  {"estimated_kg", weight.weight_kg},
                  {"protocol_implemented", true},
                  {"extrapolated", !extrapolated_features.empty()},
                  {"extrapolated_features", extrapolated_features},
                  {"note",
                   "TEST OVERRIDE: weight.available is a manual flag for on-device "
                   "verification -- cm_per_px_target and its calibration uncertainty are "
                   "not yet field-validated (phase 5); treat estimated_kg as provisional."},
                  {"capture_contract",
                   {{"feature_space", "fixed_camera_pixels"},
                    {"training_camera_height_m", manifest.weight.training_camera_height_m},
                    {"camera_height_is_xgboost_feature",
                     manifest.weight.camera_height_is_xgboost_feature}}},
              };
            } else {
              envelope["weight"] = json{{"status", "error"}, {"reason", weight.error}};
            }
          }
        } else if (weight_override) {
          envelope["weight"] = weight_scale_unavailable_json;
        } else {
          envelope["weight"] = weight_unavailable_json;
        }
      } else {
        envelope["features"] = json{{"status", "error"}, {"reason", features_error}};
        envelope["weight"] = weight_override
                                  ? json{{"status", "error"}, {"reason", features_error}}
                                  : weight_unavailable_json;
      }
    } else {
      envelope["features"] = skipped("cutter_failed");
      envelope["weight"] =
          weight_override ? json{{"status", "error"}, {"reason", "cutter_failed"}}
                           : weight_unavailable_json;
    }
  } else if (is_dorsal && !have_mask) {
    envelope["cutter"] = skipped("no_mask");
    envelope["features"] = skipped("no_mask");
    envelope["weight"] = unavailable("segmentation_failed");
  } else {
    // health_only: no cutter, no features, no weight -- exactly refactor_plan.md's
    // "no -> use base segmentation mask for health cnn" (health already ran above).
    envelope["cutter"] = skipped("view_not_dorsal");
    envelope["features"] = skipped("view_not_dorsal");
    envelope["weight"] = skipped("view_not_dorsal");
  }

  envelope["status"] = "ok";
  *out_json = envelope.dump();
  return true;
}

}  // namespace instaham_ml
