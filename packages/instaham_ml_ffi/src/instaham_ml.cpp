// instaham_ml — C ABI implementation.
//
// SLICE 0: skeleton. Every inference entrypoint returns INSTAHAM_ML_ERR_UNAVAILABLE with a
// well-formed JSON envelope so the Dart side can be wired and tested before any model runs.
// Slices 2-5 replace the stub bodies with real ONNX Runtime / OpenCV work behind
// context.cpp / classifier.cpp / weight_pipeline.cpp.

#include "include/instaham_ml.h"

#include <cstdlib>
#include <cstring>
#include <string>

namespace {

// Thread-local last-error buffer (see instaham_ml_last_error).
thread_local std::string g_last_error;

void set_error(const char* msg) { g_last_error = msg ? msg : ""; }

// Duplicate a std::string onto the C heap; caller frees with instaham_ml_string_free.
char* dup_cstr(const std::string& s) {
  char* out = static_cast<char*>(std::malloc(s.size() + 1));
  if (out) std::memcpy(out, s.c_str(), s.size() + 1);
  return out;
}

std::string unavailable_envelope(const char* capability) {
  std::string cap = capability ? capability : "unknown";
  return "{\"status\":\"unavailable\",\"error_code\":6,"
         "\"message\":\"native ML runtime not built yet (slice 0 skeleton)\","
         "\"capability\":\"" + cap + "\"}";
}

// Minimal opaque context. Real fields (manifest, ORT env, sessions) land in context.cpp.
struct Context {
  std::string manifest_path;
};

InstahamMlStatus stub_json(const char* capability, char** out_json) {
  if (!out_json) {
    set_error("out_json is null");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  *out_json = dup_cstr(unavailable_envelope(capability));
  set_error("capability unavailable in slice 0 skeleton");
  return INSTAHAM_ML_ERR_UNAVAILABLE;
}

}  // namespace

extern "C" {

InstahamMlStatus instaham_ml_create(const char* manifest_path, InstahamMlContext** out_ctx) {
  if (!manifest_path || !out_ctx) {
    set_error("manifest_path or out_ctx is null");
    return INSTAHAM_ML_ERR_INVALID_ARG;
  }
  auto* ctx = new (std::nothrow) Context{};
  if (!ctx) {
    set_error("out of memory");
    return INSTAHAM_ML_ERR_MODEL_LOAD;
  }
  ctx->manifest_path = manifest_path;
  // TODO(slice-2): parse manifest, verify sha256 of every referenced file, open ORT sessions.
  *out_ctx = reinterpret_cast<InstahamMlContext*>(ctx);
  set_error("");
  return INSTAHAM_ML_OK;
}

void instaham_ml_destroy(InstahamMlContext* ctx) {
  delete reinterpret_cast<Context*>(ctx);
}

int32_t instaham_ml_abi_version(void) { return INSTAHAM_ML_ABI_VERSION; }

const char* instaham_ml_build_info(void) {
  return "instaham_ml slice0-skeleton ort=pending opencv=pending";
}

const char* instaham_ml_last_error(void) { return g_last_error.c_str(); }

void instaham_ml_string_free(char* s) { std::free(s); }

int32_t instaham_ml_capability_available(InstahamMlContext* ctx, const char* capability) {
  (void)ctx;
  (void)capability;
  return 0;  // nothing available in the skeleton
}

InstahamMlStatus instaham_ml_classify_view_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json) {
  (void)ctx;
  (void)image_path;
  return stub_json("view", out_json);
}

InstahamMlStatus instaham_ml_classify_health_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json) {
  (void)ctx;
  (void)image_path;
  return stub_json("health", out_json);
}

InstahamMlStatus instaham_ml_predict_weight_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json) {
  (void)ctx;
  (void)image_path;
  return stub_json("weight", out_json);
}

InstahamMlStatus instaham_ml_extract_features_provisional_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json) {
  (void)ctx;
  (void)image_path;
  return stub_json("weight_provisional", out_json);
}

}  // extern "C"
