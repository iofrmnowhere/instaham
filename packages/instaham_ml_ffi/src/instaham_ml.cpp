// instaham_ml — C ABI implementation.
//
// Slice 3/4 (Android-first pass): view + health classification and segmentation detection
// are real ONNX Runtime inference. The weight branch and the mask/geometry port (five
// features, dorsal-core cut) remain deferred to the section-3.5 decision point -- both
// entrypoints below still return INSTAHAM_ML_ERR_UNAVAILABLE by manifest contract
// (weight.available is false in every manifest this build ships), which is the documented
// behaviour, not a stub.

#include "include/instaham_ml.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include "classifier.h"
#include "manifest.h"
#include "onnx_runner.h"
#include "segmenter.h"

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
};

InstahamMlStatus run_classifier_entrypoint(Context* ctx, instaham_ml::OnnxRunner* runner,
                                            const instaham_ml::ClassifierCapability& cap,
                                            const char* capability_name, const char* image_path,
                                            char** out_json) {
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
  bool ok = instaham_ml::run_classifier(runner, cap, image_path, &json_out, &error_code);
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

  *out_ctx = reinterpret_cast<InstahamMlContext*>(ctx.release());
  set_error("");
  return INSTAHAM_ML_OK;
}

void instaham_ml_destroy(InstahamMlContext* ctx) { delete reinterpret_cast<Context*>(ctx); }

int32_t instaham_ml_abi_version(void) { return INSTAHAM_ML_ABI_VERSION; }

const char* instaham_ml_build_info(void) {
  return "instaham_ml slice3-4 android ort=1.17.1 opencv=none(stb_image)";
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
                                    "view", image_path, out_json);
}

InstahamMlStatus instaham_ml_classify_health_json(InstahamMlContext* raw_ctx,
                                                   const char* image_path, char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  return run_classifier_entrypoint(
      ctx, ctx ? ctx->health_runner.get() : nullptr,
      ctx ? ctx->manifest.health : instaham_ml::ClassifierCapability{}, "health", image_path,
      out_json);
}

// New in slice 3/4 (additive -- ABI_VERSION stays 1 per instaham_ml.h's own contract: only
// a breaking signature change bumps it). Exposed for a future segmentation UI card; not yet
// consumed by the weight branch, which still needs the full mask decode.
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
  std::string json_out;
  int error_code = INSTAHAM_ML_OK;
  bool ok = instaham_ml::run_segmenter(ctx->segmentation_runner.get(), ctx->manifest.segmentation,
                                        image_path, &json_out, &error_code);
  *out_json = dup_cstr(json_out);
  if (!ok) {
    set_error(json_out);
    return static_cast<InstahamMlStatus>(error_code);
  }
  set_error("");
  return INSTAHAM_ML_OK;
}

InstahamMlStatus instaham_ml_predict_weight_json(InstahamMlContext* raw_ctx,
                                                  const char* image_path, char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  (void)image_path;
  if (!out_json) {
    set_error("out_json is null");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  // weight.available is false in every manifest this build ships (section 3.5 decision
  // point not yet taken) -- this is the documented "unavailable" contract, not a stub.
  (void)ctx;
  *out_json = dup_cstr(unavailable_envelope("weight", "body_mask_port_incomplete"));
  set_error("weight unavailable: body_mask_port_incomplete");
  return INSTAHAM_ML_ERR_UNAVAILABLE;
}

InstahamMlStatus instaham_ml_extract_features_provisional_json(InstahamMlContext* raw_ctx,
                                                                 const char* image_path,
                                                                 char** out_json) {
  auto* ctx = reinterpret_cast<Context*>(raw_ctx);
  (void)image_path;
  if (!out_json) {
    set_error("out_json is null");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  (void)ctx;
  *out_json = dup_cstr(unavailable_envelope("weight_provisional", "body_mask_port_incomplete"));
  set_error("weight_provisional unavailable: body_mask_port_incomplete");
  return INSTAHAM_ML_ERR_UNAVAILABLE;
}

}  // extern "C"
