#include "pipeline.h"

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

}  // namespace

bool run_pipeline(const PipelineRunners& runners, const Manifest& manifest,
                   const std::string& image_path, std::string* out_json) {
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
  stages::SegmentationOutput seg_output;
  stages::PigMask pig_mask;
  bool have_mask = false;

  if (manifest.segmentation.available && runners.segmentation) {
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

  // ---- stage 3 + 4: cutter (identity dummy, section 3.4), feature calculation ----
  // Weight ALWAYS stays unavailable while the cutter is the dummy -- AGENTS.md rule 8, and
  // manifest.weight_available is already false in every manifest this build ships, so this
  // branch cannot disagree with the manifest by construction.
  if (is_dorsal && have_mask) {
    stages::MaskView mask_view{pig_mask.pixels.data(), pig_mask.width, pig_mask.height};
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

    if (cutter_result.ok()) {
      auto feats = stages::extract_five_features(cutter_result.mask, cutter_result.width,
                                                  cutter_result.height, 1.0,
                                                  /*preserve_processed_mask=*/true);
      if (feats) {
        envelope["features"] = json{
            {"status", "provisional"},
            {"family", "baseline5"},
            {"order", {"RA", "LC", "BL", "BW", "E"}},
            {"values",
             {{"RA", feats->ra}, {"LC", feats->lc}, {"BL", feats->bl}, {"BW", feats->bw},
              {"E", feats->e}}},
            {"measured_on", "uncut_mask"},
        };
        if (weight_override) {
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
