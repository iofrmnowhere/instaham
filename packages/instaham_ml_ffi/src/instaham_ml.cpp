// instaham_ml — C ABI implementation.
//
// ML_implementation_plan.md revision 7: view/health classification, segmentation, mask
// construction, and provisional (uncut) feature extraction are real. The weight branch
// stays INSTAHAM_ML_ERR_UNAVAILABLE by manifest contract (weight.available is false in
// every manifest this build ships) because the cutter is a permanent C++ identity dummy
// (section 3.4) -- that is the documented behaviour, not a stub awaiting a decision.

#include "include/instaham_ml.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include "classifier.h"
#include "manifest.h"
#include "onnx_runner.h"
#include "pipeline.h"
#include "stages/construction.h"
#include "stages/cutter.h"
#include "stages/feature_calculation.h"
#include "stages/segmentation.h"
#include "stages/weight_prediction.h"
#include "third_party/nlohmann_json/single_include/nlohmann/json.hpp"

namespace {

thread_local std::string g_last_error;

void set_error(const std::string& msg) { g_last_error = msg; }

char* dup_cstr(const std::string& s) {
  char* out = static_cast<char*>(std::malloc(s.size() + 1));
  if (out) std::memcpy(out, s.c_str(), s.size() + 1);
  return out;
}

std::string unavailable_envelope(const char* capability, const char* reason) {
  std::string cap = capability ? capability : "unknown";
  std::string why = reason ? reason : "capability unavailable";
  return "{\"status\":\"unavailable\",\"reason\":\"" + why + "\",\"capability\":\"" + cap + "\"}";
}

struct Context {
  instaham_ml::Manifest manifest;
  std::unique_ptr<instaham_ml::OnnxRunner> view_runner;
  std::unique_ptr<instaham_ml::OnnxRunner> health_runner;
  std::unique_ptr<instaham_ml::OnnxRunner> segmentation_runner;
  std::unique_ptr<instaham_ml::OnnxRunner> weight_runner;
};

InstahamMlStatus run_classifier_entrypoint(Context* ctx, instaham_ml::OnnxRunner* runner,
                                            const instaham_ml::ClassifierCapability& cap,
                                            const char* capability_name, const char* image_path,
                                            char** out_json,
                                            const instaham_ml::HealthInputOptions* health_input) {
  if (!ctx || !image_path || !out_json) {
    set_error("null argument");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  if (!cap.available || !runner) {
    *out_json = dup_cstr(unavailable_envelope(capability_name, "not available in this manifest"));
    set_error("capability unavailable");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }
  std::string json_out;
  int error_code = INSTAHAM_ML_OK;
  bool ok =
      instaham_ml::run_classifier(runner, cap, image_path, &json_out, &error_code, health_input);
  *out_json = dup_cstr(json_out);
  if (!ok) {
    set_error(json_out);
    return static_cast<InstahamMlStatus>(error_code);
  }
  set_error("");
  return INSTAHAM_ML_OK;
}

}  // namespace

extern "C" {

InstahamMlStatus instaham_ml_create(const char* manifest_path, InstahamMlContext** out_ctx) {
  if (!manifest_path || !out_ctx) {
    set_error("manifest_path or out_ctx is null");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }

  auto ctx = std::make_unique<Context>();
  std::string error;
  int error_code = INSTAHAM_ML_OK;
  if (!instaham_ml::load_manifest(manifest_path, &ctx->manifest, &error, &error_code)) {
    set_error(error);
    return static_cast<InstahamMlStatus>(error_code);
  }

  // Every referenced file's sha256 was already verified inside load_manifest() before we
  // get here -- ORT sessions are only ever created over hash-checked models.
  if (ctx->manifest.view.available) {
    ctx->view_runner = std::make_unique<instaham_ml::OnnxRunner>();
    if (!ctx->view_runner->load(ctx->manifest.view.model_path, &error)) {
      set_error(error);
      return INSTAHAM_ML_ERR_MODEL_LOAD;
    }
  }
  if (ctx->manifest.health.available) {
    ctx->health_runner = std::make_unique<instaham_ml::OnnxRunner>();
    if (!ctx->health_runner->load(ctx->manifest.health.model_path, &error)) {
      set_error(error);
      return INSTAHAM_ML_ERR_MODEL_LOAD;
    }
  }
  if (ctx->manifest.segmentation.available) {
    ctx->segmentation_runner = std::make_unique<instaham_ml::OnnxRunner>();
    if (!ctx->segmentation_runner->load(ctx->manifest.segmentation.model_path, &error)) {
      set_error(error);
      return INSTAHAM_ML_ERR_MODEL_LOAD;
    }
  }
  if (ctx->manifest.weight.available) {
    ctx->weight_runner = std::make_unique<instaham_ml::OnnxRunner>();
    if (!ctx->weight_runner->load(ctx->manifest.weight.model_path, &error)) {
      set_error(error);
      return INSTAHAM_ML_ERR_MODEL_LOAD;
    }
  }

  *out_ctx = reinterpret_cast<InstahamMlContext*>(ctx.release());
  set_error("");
  return INSTAHAM_ML_OK;
}

void instaham_ml_destroy(InstahamMlContext* ctx) { delete reinterpret_cast<Context*>(ctx); }

int32_t instaham_ml_abi_version(void) { return INSTAHAM_ML_ABI_VERSION; }

const char* instaham_ml_build_info(void) {
  return "instaham_ml revision7 android ort=1.17.1 opencv-mobile=4.13.0";
}

const char* instaham_ml_last_error(void) { return g_last_error.c_str(); }

void instaham_ml_string_free(char* s) { std::free(s); }

int32_t instaham_ml_capability_available(InstahamMlContext* raw_ctx, const char* capability) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  if (!ctx || !capability) return 0;
  std::string cap = capability;
  if (cap == "view") return ctx->manifest.view.available ? 1 : 0;
  if (cap == "health") return ctx->manifest.health.available ? 1 : 0;
  if (cap == "segmentation") return ctx->manifest.segmentation.available ? 1 : 0;
  if (cap == "weight") return ctx->manifest.weight_available ? 1 : 0;
  return 0;
}

InstahamMlStatus instaham_ml_classify_view_json(InstahamMlContext* raw_ctx, const char* image_path,
                                                 char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  return run_classifier_entrypoint(ctx, ctx ? ctx->view_runner.get() : nullptr,
                                    ctx ? ctx->manifest.view : instaham_ml::ClassifierCapability{},
                                    "view", image_path, out_json, nullptr);
}

InstahamMlStatus instaham_ml_classify_health_json(InstahamMlContext* raw_ctx,
                                                   const char* image_path, char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  // The manifest's health.input.protocol is honoured here, but health_input.cpp's region
  // protocols are stubs that fall through to full_frame, so today this changes nothing
  // about the pixels -- only what the envelope reports. No region is passed: this
  // per-capability entrypoint runs health in isolation, with no segmentation output to draw
  // one from -- instaham_ml_run_pipeline_json is the call that has a real mask to pass
  // (pipeline.cpp), and the stub would ignore this one's region regardless.
  instaham_ml::HealthInputOptions health_input;
  health_input.protocol = instaham_ml::parse_health_input_protocol(
      ctx ? ctx->manifest.health.input_protocol : std::string());
  health_input.region = nullptr;
  return run_classifier_entrypoint(
      ctx, ctx ? ctx->health_runner.get() : nullptr,
      ctx ? ctx->manifest.health : instaham_ml::ClassifierCapability{}, "health", image_path,
      out_json, &health_input);
}

// ML_implementation_plan.md revision 7: now runs the real segmentation + construction
// stages and reports the constructed mask's bbox/area/protocol, not detection-only fields.
InstahamMlStatus instaham_ml_segment_json(InstahamMlContext* raw_ctx, const char* image_path,
                                           char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  if (!ctx || !image_path || !out_json) {
    set_error("null argument");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  if (!ctx->manifest.segmentation.available || !ctx->segmentation_runner) {
    *out_json = dup_cstr(unavailable_envelope("segmentation", "not available in this manifest"));
    set_error("capability unavailable");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  instaham_ml::stages::SegmentationOutput seg;
  std::string error;
  // ref_fix.md F18: this standalone entrypoint has no cm_per_px context of its own (it
  // predates the reference-object scale plumbing run_pipeline() has), so it always uses
  // the plain whole-frame letterbox -- 0.0/0.0 disables scale-aware canvas composition,
  // exactly the pre-F18 behaviour.
  if (!instaham_ml::stages::run_segmentation(ctx->segmentation_runner.get(),
                                              ctx->manifest.segmentation, image_path, 0.0, 0.0,
                                              0.0f, &seg, &error)) {
    *out_json = dup_cstr(nlohmann::json{{"status", "error"}, {"message", error}}.dump());
    set_error(error);
    return INSTAHAM_ML_ERR_INFERENCE;
  }
  if (!seg.has_detection) {
    nlohmann::json result = {{"status", "ok"},         {"pig_count", 0}, {"confidence", 0.0},
                              {"mask_available", false}, {"protocol_version",
                                                           ctx->manifest.segmentation.protocol_version}};
    *out_json = dup_cstr(result.dump());
    set_error("");
    return INSTAHAM_ML_OK;
  }

  instaham_ml::stages::PigMask mask = instaham_ml::stages::construct_pig_mask(seg);
  nlohmann::json result = {
      {"status", "ok"},
      {"pig_count", 1},
      {"confidence", seg.box.conf},
      {"mask_available", !mask.empty()},
      {"protocol_version", ctx->manifest.segmentation.protocol_version},
  };
  if (!mask.empty()) {
    result["mask_protocol"] = "original_coordinate_polygon_v1";
    result["mask_area_px"] = mask.area_px;
    result["bbox"] = {mask.bbox_x, mask.bbox_y, mask.bbox_w, mask.bbox_h};
  }
  *out_json = dup_cstr(result.dump());
  set_error("");
  return INSTAHAM_ML_OK;
}

InstahamMlStatus instaham_ml_predict_weight_json(InstahamMlContext* raw_ctx,
                                                  const char* image_path, char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  if (!ctx || !image_path || !out_json) {
    set_error("null argument");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }

  // weight.available is false in every manifest ML_implementation_plan.md revision 7
  // ships by default: the cutter is a permanent C++ identity dummy (section 3.4), not a
  // stub awaiting a decision. A build that deliberately flips weight.available true (a
  // documented, opt-in test override -- see ML/export/export_xgboost.py's
  // --enable-for-testing flag) reaches the branch below instead; every envelope it
  // produces still carries protocol_implemented:false and the uncut-mask caveat, per
  // AGENTS.md rule 8 -- nothing here fabricates a number, it labels a real, biased one.
  if (!ctx->manifest.weight.available || !ctx->weight_runner) {
    *out_json = dup_cstr(unavailable_envelope("weight", "cutter_identity_stub"));
    set_error("weight unavailable: cutter_identity_stub");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }
  if (!ctx->manifest.segmentation.available || !ctx->segmentation_runner) {
    *out_json = dup_cstr(unavailable_envelope("weight", "segmentation_unavailable"));
    set_error("capability unavailable");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  instaham_ml::stages::SegmentationOutput seg;
  std::string error;
  // ref_fix.md F18: same as above -- this standalone entrypoint has no cm_per_px context,
  // so it always uses the plain whole-frame letterbox (pre-F18 behaviour unchanged).
  if (!instaham_ml::stages::run_segmentation(ctx->segmentation_runner.get(),
                                              ctx->manifest.segmentation, image_path, 0.0, 0.0,
                                              0.0f, &seg, &error) ||
      !seg.has_detection) {
    *out_json = dup_cstr(unavailable_envelope("weight", "no_instance_above_conf"));
    set_error(error.empty() ? "no instance above conf" : error);
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  instaham_ml::stages::PigMask mask = instaham_ml::stages::construct_pig_mask(seg);
  if (mask.empty()) {
    *out_json = dup_cstr(unavailable_envelope("weight", "empty_mask"));
    set_error("empty mask");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  instaham_ml::stages::MaskView mask_view{mask.pixels.data(), mask.width, mask.height};
  instaham_ml::stages::CutterResult cutter_result = instaham_ml::stages::cut_body_mask(mask_view);
  if (!cutter_result.ok()) {
    *out_json = dup_cstr(unavailable_envelope("weight", "cutter_failed"));
    set_error("cutter failed");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  auto feats = instaham_ml::stages::extract_five_features(
      cutter_result.mask, cutter_result.width, cutter_result.height, 1.0,
      /*preserve_processed_mask=*/true);
  if (!feats) {
    *out_json = dup_cstr(unavailable_envelope("weight", "contour_too_small"));
    set_error("contour too small");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  auto weight = instaham_ml::stages::predict_weight(ctx->weight_runner.get(), *feats);
  if (!weight.ok) {
    *out_json = dup_cstr(nlohmann::json{{"status", "error"}, {"message", weight.error}}.dump());
    set_error(weight.error);
    return INSTAHAM_ML_ERR_INFERENCE;
  }

  nlohmann::json result = {
      {"status", "ok"},
      {"estimated_kg", weight.weight_kg},
      {"segmentation_confidence", seg.box.conf},
      {"feature_family", "baseline5"},
      {"feature_order", {"RA", "LC", "BL", "BW", "E"}},
      {"features",
       {{"RA", feats->ra}, {"LC", feats->lc}, {"BL", feats->bl}, {"BW", feats->bw},
        {"E", feats->e}}},
      {"qc",
       {{"head_removal_applied", cutter_result.head_removal_applied},
        {"pair_valid", false},
        {"cutter", "identity_stub"}}},
      {"protocols",
       {{"cutter_protocol_version", "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26"},
        {"cutter_protocol_implemented", false}}},
      {"capture_contract",
       {{"feature_space", "fixed_camera_pixels"},
        {"training_camera_height_m", ctx->manifest.weight.training_camera_height_m},
        {"camera_height_is_xgboost_feature",
         ctx->manifest.weight.camera_height_is_xgboost_feature}}},
      // Section 3.4's rule stated plainly in the payload, not just in a comment: this
      // build's cutter never removed the head/neck, so `estimated_kg` is measured on the
      // full (uncut) mask and reads heavier than the research protocol's number would.
      {"note",
       "TEST OVERRIDE: cutter is the identity stub (head/neck not removed). "
       "estimated_kg is measured on the uncut mask and is expected to overestimate."},
  };
  *out_json = dup_cstr(result.dump());
  set_error("");
  return INSTAHAM_ML_OK;
}

// ML_implementation_plan.md revision 7, section 3.4 rule 3: the one thing the identity
// cutter DOES deliver. Real features from a real (uncut) mask, permanently labelled
// "provisional" so no caller can mistake them for a weight input.
InstahamMlStatus instaham_ml_extract_features_provisional_json(InstahamMlContext* raw_ctx,
                                                                 const char* image_path,
                                                                 char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  if (!ctx || !image_path || !out_json) {
    set_error("null argument");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  if (!ctx->manifest.segmentation.available || !ctx->segmentation_runner) {
    *out_json = dup_cstr(unavailable_envelope("weight_provisional", "segmentation_unavailable"));
    set_error("capability unavailable");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  instaham_ml::stages::SegmentationOutput seg;
  std::string error;
  // ref_fix.md F18: same as above -- this standalone entrypoint has no cm_per_px context,
  // so it always uses the plain whole-frame letterbox (pre-F18 behaviour unchanged).
  if (!instaham_ml::stages::run_segmentation(ctx->segmentation_runner.get(),
                                              ctx->manifest.segmentation, image_path, 0.0, 0.0,
                                              0.0f, &seg, &error) ||
      !seg.has_detection) {
    *out_json = dup_cstr(unavailable_envelope("weight_provisional", "no_instance_above_conf"));
    set_error(error.empty() ? "no instance above conf" : error);
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  instaham_ml::stages::PigMask mask = instaham_ml::stages::construct_pig_mask(seg);
  if (mask.empty()) {
    *out_json = dup_cstr(unavailable_envelope("weight_provisional", "empty_mask"));
    set_error("empty mask");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  auto feats = instaham_ml::stages::extract_five_features(mask.pixels, mask.width, mask.height,
                                                            1.0,
                                                            /*preserve_processed_mask=*/false);
  if (!feats) {
    *out_json = dup_cstr(unavailable_envelope("weight_provisional", "contour_too_small"));
    set_error("contour too small");
    return INSTAHAM_ML_ERR_UNAVAILABLE;
  }

  nlohmann::json result = {
      {"status", "provisional"},
      {"features",
       {{"RA", feats->ra}, {"LC", feats->lc}, {"BL", feats->bl}, {"BW", feats->bw},
        {"E", feats->e}}},
      {"qc",
       {{"head_removal_applied", false}, {"pair_valid", false}, {"cutter", "identity_stub"}}},
      {"segmentation_confidence", seg.box.conf},
  };
  *out_json = dup_cstr(result.dump());
  set_error("");
  return INSTAHAM_ML_OK;
}

InstahamMlStatus instaham_ml_run_pipeline_json(InstahamMlContext* raw_ctx, const char* image_path,
                                                char** out_json) {
  // Thin call into the request-shaped entrypoint with cm_per_px absent -- TASKS.md W4, so
  // this signature (and every existing caller/test of it) is untouched by the scale work.
  if (!image_path) {
    set_error("null argument");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  nlohmann::json request = {{"image_path", image_path}};
  return instaham_ml_run_pipeline_request_json(raw_ctx, request.dump().c_str(), out_json);
}

InstahamMlStatus instaham_ml_run_pipeline_request_json(InstahamMlContext* raw_ctx,
                                                         const char* request_json,
                                                         char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  if (!ctx || !request_json || !out_json) {
    set_error("null argument");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  nlohmann::json request;
  try {
    request = nlohmann::json::parse(request_json);
  } catch (const std::exception&) {
    set_error("request_json did not parse");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  if (!request.contains("image_path") || !request["image_path"].is_string()) {
    set_error("request_json missing string image_path");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  std::string image_path = request["image_path"].get<std::string>();

  // TASKS.md W3/W4: the user-confirmed reference object's cm/pixel for this capture
  // (AGENTS.md rule 7). Absent, null, or non-numeric all mean "no confirmed reference" --
  // run_pipeline() degrades the weight branch rather than assuming a scale.
  double cm_per_px_value = 0.0;
  const double* cm_per_px = nullptr;
  if (request.contains("cm_per_px") && request["cm_per_px"].is_number()) {
    cm_per_px_value = request["cm_per_px"].get<double>();
    cm_per_px = &cm_per_px_value;
  }

  instaham_ml::PipelineRunners runners{ctx->view_runner.get(), ctx->health_runner.get(),
                                        ctx->segmentation_runner.get(),
                                        ctx->weight_runner.get()};
  std::string json_out;
  bool ok =
      instaham_ml::run_pipeline(runners, ctx->manifest, image_path, cm_per_px, &json_out);
  *out_json = dup_cstr(json_out);
  if (!ok) {
    set_error(json_out);
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  set_error("");
  return INSTAHAM_ML_OK;
}

}  // extern "C"
