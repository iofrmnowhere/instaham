#include "pipeline.h"

#include <cmath>

#include "health_input.h"
#include "stages/construction.h"
#include "stages/cutter.h"
#include "stages/feature_calculation.h"
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

// ref_fix.md F3: is `value` inside [domain.min, domain.max * domain.upper_multiplier]?
// domain.max <= 0.0 means the manifest carried no data for this feature (an older export
// fragment) -- the gate is disabled for that one feature rather than rejecting every
// prediction outright, since a partial manifest is still better checked than not at all.
// On failure, appends "<name>=<value> " to *violations so the envelope can name exactly
// which feature(s) put the vector outside the trained domain.
bool feature_in_domain(double value, const WeightCapability::FeatureDomain& domain,
                        const char* name, std::string* violations) {
  if (domain.max <= 0.0) return true;
  const double upper = domain.max * domain.upper_multiplier;
  if (!std::isfinite(value) || value < domain.min || value > upper) {
    *violations += std::string(name) + "=" + std::to_string(value) + " ";
    return false;
  }
  return true;
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
    std::string seg_error;
    bool seg_ok =
        stages::run_segmentation(runners.segmentation, manifest.segmentation, image_path,
                                  &seg_output, &seg_error);
    if (!seg_ok) {
      envelope["segmentation"] = json{{"status", "error"}, {"reason", seg_error}};
      envelope["construction"] = skipped("segmentation_failed");
    } else if (!seg_output.has_detection) {
      envelope["segmentation"] = json{{"status", "error"}, {"reason", "no_instance_above_conf"}};
      envelope["construction"] = skipped("no_instance");
    } else {
      envelope["segmentation"] =
          json{{"status", "ok"}, {"confidence", seg_output.box.conf}, {"instances_found", 1}};
      pig_mask = stages::construct_pig_mask(seg_output);
      if (pig_mask.empty()) {
        envelope["construction"] = json{{"status", "error"}, {"reason", "empty_mask"}};
      } else {
        have_mask = true;
        envelope["construction"] = json{
            {"status", "ok"},
            {"mask_protocol", "original_coordinate_polygon_v1"},
            {"mask_area_px", pig_mask.area_px},
            {"bbox", {pig_mask.bbox_x, pig_mask.bbox_y, pig_mask.bbox_w, pig_mask.bbox_h}},
        };
      }
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

  // ---- stage 3 + 4: cutter (identity dummy, section 3.4), feature calculation ----
  // Weight predicts only when BOTH the manifest opts in (test override) AND a valid scale
  // was established above -- AGENTS.md rule 3/8: every eligibility check must pass, and a
  // missing/invalid reference degrades this branch, it never falls back to unscaled pixels.
  if (is_dorsal && have_mask) {
    // Cut and measure on the training-normalized mask when a scale is available, so the
    // cutter's (currently dummy, eventually real) pixel-space thresholds and the RA
    // denominator both operate on the space the regressor was trained in (TASKS.md
    // section 3.3, Option B). Falls back to the raw captured-pixel mask, unscaled, only to
    // keep provisional debugging features visible when no reference was marked.
    stages::PigMask scaled_mask;
    const stages::PigMask* mask_for_cutter = &pig_mask;
    if (scale_ok) {
      scaled_mask = stages::scale_mask_to_training_space(pig_mask, k);
      if (!scaled_mask.empty()) {
        mask_for_cutter = &scaled_mask;
      } else {
        scale_ok = false;
        scale_failure_reason = "scale_resample_failed";
        envelope["scale"] = json{{"status", "unavailable"}, {"reason", scale_failure_reason}};
      }
    }

    stages::MaskView mask_view{mask_for_cutter->pixels.data(), mask_for_cutter->width,
                                mask_for_cutter->height};
    stages::CutterResult cutter_result = stages::cut_body_mask(mask_view);

    envelope["cutter"] = json{
        {"status", cutter_result.status},
        {"head_removal_applied", cutter_result.head_removal_applied},
        {"pair_valid", false},
        {"protocol_version", "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26"},
        {"protocol_implemented", false},
    };

    // Test override (ML/export/export_xgboost.py --enable-for-testing): only reachable
    // when the manifest deliberately sets weight.available true. AGENTS.md rule 8 stays
    // satisfied -- this is a real prediction from the runner, labelled with the same
    // uncut-mask caveat instaham_ml_predict_weight_json carries, never a fabricated value.
    const bool weight_override = manifest.weight.available && runners.weight;
    json weight_unavailable_json = json{
        {"status", "unavailable"},
        {"reason", "cutter_identity_stub"},
        {"user_message_key", "weight_unavailable_cutter_not_implemented"},
        {"capture_contract",
         {{"feature_space", "fixed_camera_pixels"},
          {"training_camera_height_m", 1.88},
          {"camera_height_is_xgboost_feature", false}}},
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
      // scale_ok -> the mask cut above is already in training pixels, so linear_scale
      // stays 1.0 and RA's denominator is the manifest's training frame. Without a scale,
      // this reproduces the pre-W5 provisional-debug values exactly (mask's own w/h, no
      // frame override) -- never mistakeable for weight input given the label below.
      auto feats = stages::extract_five_features(
          cutter_result.mask, cutter_result.width, cutter_result.height, 1.0,
          /*preserve_processed_mask=*/true,
          scale_ok ? manifest.weight.training_frame_w : 0,
          scale_ok ? manifest.weight.training_frame_h : 0);
      if (feats) {
        envelope["features"] = json{
            {"status", "provisional"},
            {"family", "baseline5"},
            {"order", {"RA", "LC", "BL", "BW", "E"}},
            {"values",
             {{"RA", feats->ra}, {"LC", feats->lc}, {"BL", feats->bl}, {"BW", feats->bw},
              {"E", feats->e}}},
            {"measured_on", scale_ok ? "training_normalized_mask" : "uncut_mask_unnormalized"},
        };
        if (weight_override && scale_ok) {
          // ref_fix.md F3: gate on whether the trained regressor has ever seen anything
          // like this normalized feature vector -- the principled check the resolution-
          // blind k-range bound (fixed in F2) was only ever a proxy for. Runs AFTER
          // normalization, so it is checking the same space the manifest's
          // feature_domain values were measured in.
          std::string domain_violations;
          // Bitwise `&`, deliberately, not `&&` -- every feature is checked and every
          // violation appended to domain_violations, rather than short-circuiting after
          // the first one and hiding whether other features were also out of range.
          const bool in_domain =
              feature_in_domain(feats->ra, manifest.weight.domain_ra, "RA", &domain_violations) &
              feature_in_domain(feats->lc, manifest.weight.domain_lc, "LC", &domain_violations) &
              feature_in_domain(feats->bl, manifest.weight.domain_bl, "BL", &domain_violations) &
              feature_in_domain(feats->bw, manifest.weight.domain_bw, "BW", &domain_violations) &
              feature_in_domain(feats->e, manifest.weight.domain_e, "E", &domain_violations);
          if (!in_domain) {
            envelope["weight"] = json{
                {"status", "unavailable"},
                {"reason", "features_out_of_training_domain"},
                {"user_message_key", "weight_features_out_of_range"},
                {"detail", domain_violations},
            };
          } else {
            auto weight = stages::predict_weight(runners.weight, *feats);
            if (weight.ok) {
              envelope["weight"] = json{
                  {"status", "ok"},
                  {"estimated_kg", weight.weight_kg},
                  {"protocol_implemented", false},
                  {"note",
                   "TEST OVERRIDE: cutter is the identity stub (head/neck not removed); "
                   "estimated_kg overestimates the research protocol's number."},
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
        envelope["features"] = json{{"status", "error"}, {"reason", "contour_too_small"}};
        envelope["weight"] = weight_override
                                  ? json{{"status", "error"}, {"reason", "contour_too_small"}}
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
