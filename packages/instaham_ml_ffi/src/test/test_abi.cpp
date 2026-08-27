// Slice 0 smoke test: the ABI links, the version matches, and stub entrypoints return a
// well-formed unavailable envelope that the caller frees.

#include "../include/instaham_ml.h"

#include <cassert>
#include <cstdlib>
#include <cstring>
#include <cstdio>

int main() {
  assert(instaham_ml_abi_version() == INSTAHAM_ML_ABI_VERSION);
  assert(instaham_ml_abi_version() == 1);
  assert(std::strlen(instaham_ml_build_info()) > 0);

  InstahamMlContext* ctx = nullptr;
  // No real manifest yet; create still succeeds in the skeleton (parsing lands in slice 2).
  assert(instaham_ml_create("/nonexistent/manifest.json", &ctx) == INSTAHAM_ML_OK);
  assert(ctx != nullptr);

  assert(instaham_ml_capability_available(ctx, "view") == 0);
  assert(instaham_ml_capability_available(ctx, "weight") == 0);

  char* json = nullptr;
  InstahamMlStatus st = instaham_ml_classify_view_json(ctx, "/tmp/x.jpg", &json);
  assert(st == INSTAHAM_ML_ERR_UNAVAILABLE);
  assert(json != nullptr);
  assert(std::strstr(json, "\"status\":\"unavailable\"") != nullptr);
  instaham_ml_string_free(json);

  json = nullptr;
  st = instaham_ml_predict_weight_json(ctx, "/tmp/x.jpg", &json);
  assert(st == INSTAHAM_ML_ERR_UNAVAILABLE);
  assert(json != nullptr);
  instaham_ml_string_free(json);

  // null out-param is rejected
  assert(instaham_ml_classify_health_json(ctx, "/tmp/x.jpg", nullptr) == INSTAHAM_ML_ERR_INVALID_ARG);

  instaham_ml_destroy(ctx);
  std::printf("test_abi OK\n");
  return 0;
}
