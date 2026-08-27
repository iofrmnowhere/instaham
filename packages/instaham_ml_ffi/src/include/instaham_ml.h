#ifndef INSTAHAM_ML_H
#define INSTAHAM_ML_H

/*
 * instaham_ml — stable C ABI for the INSTAHAM native ML runtime.
 *
 * Called from Flutter via dart:ffi (ffigen bindings). The Python files in ML/ are the
 * reference implementation; this library runs the exported ONNX models plus a C++ port of
 * the classical-CV feature path.
 *
 * ABI stability contract:
 *   - Only symbols matching instaham_ml_* are exported (see instaham_ml.map).
 *   - Payloads are UTF-8 JSON strings, never C structs, so fields can be added without
 *     breaking the ABI. Bump INSTAHAM_ML_ABI_VERSION only for a breaking signature change.
 */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define INSTAHAM_ML_ABI_VERSION 1

typedef struct InstahamMlContext InstahamMlContext;

typedef enum {
  INSTAHAM_ML_OK                = 0,
  INSTAHAM_ML_ERR_MANIFEST      = 1, /* missing / invalid / schema_version mismatch */
  INSTAHAM_ML_ERR_HASH_MISMATCH = 2, /* a model or class-map file failed sha256 */
  INSTAHAM_ML_ERR_MODEL_LOAD    = 3, /* ORT could not create a session */
  INSTAHAM_ML_ERR_IO            = 4, /* image path unreadable / undecodable */
  INSTAHAM_ML_ERR_INFERENCE     = 5, /* failure during Run() / postprocess */
  INSTAHAM_ML_ERR_UNAVAILABLE   = 6, /* capability manifest flag "available": false */
  INSTAHAM_ML_ERR_CONTRACT      = 7, /* feature_order / class-map / protocol mismatch */
  INSTAHAM_ML_ERR_INVALID_ARG   = 8
} InstahamMlStatus;

/* ---- lifecycle -------------------------------------------------------------- */

/*
 * Reads manifest.json at the absolute path `manifest_path`. All model paths inside the
 * manifest resolve relative to the manifest's directory. Every referenced file's sha256 is
 * verified before any ORT session is created. On success *out_ctx is a heap context the
 * caller owns and must release with instaham_ml_destroy.
 */
InstahamMlStatus instaham_ml_create(const char* manifest_path, InstahamMlContext** out_ctx);
void             instaham_ml_destroy(InstahamMlContext* ctx);

/* ---- diagnostics ---------------------------------------------------------- */

int32_t     instaham_ml_abi_version(void);
const char* instaham_ml_build_info(void);  /* static; e.g. "ort=1.17.1 opencv=4.9 commit=abcdef" */

/* Thread-local. Valid until the next instaham_ml_* call on the same thread. */
const char* instaham_ml_last_error(void);

/* ---- result strings ----------------------------------------------------- */

/*
 * Every *_json entrypoint writes a heap UTF-8 JSON string to *out_json, even on error
 * ({"status":"error"|"unavailable","error_code":<int>,"message":<str>}). The caller MUST
 * free it with instaham_ml_string_free.
 */
void instaham_ml_string_free(char* s);

/* ---- capabilities ------------------------------------------------------ */

/* Returns 1 iff `capability` ("view"|"health"|"segmentation"|"weight") exists in the
 * manifest AND its "available" flag is true; 0 otherwise. */
int32_t instaham_ml_capability_available(InstahamMlContext* ctx, const char* capability);

/* ---- inference -------------------------------------------------------- */

/*
 * image_path: absolute path to an ALREADY-EXIF-NORMALISED RGB image. The native layer does
 * NO rotation (AGENTS.md rule 5 is enforced once, Dart-side, in MlRuntime.exifNormalize).
 */

/* {"status":"ok","label":<str>,"confidence":<num>,"probabilities":{<cls>:<num>,...},
 *  "class_map_sha256":<str>,"protocol_version":<str>} */
InstahamMlStatus instaham_ml_classify_view_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);
InstahamMlStatus instaham_ml_classify_health_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);

/*
 * Full weight pipeline, mirrors ML/weight_runtime.py predict() (section 13 of the plan):
 *   {"status":"ok","estimated_kg":<num>,"segmentation_confidence":<num>,
 *    "feature_family":<str>,"feature_order":[...],"features":{RA,LC,BL,BW,E},
 *    "qc":{...},"protocols":{...},
 *    "capture_contract":{"feature_space":<str>,"training_camera_height_m":<num>,
 *                        "camera_height_is_xgboost_feature":<bool>},
 *    "artifacts":{...}}
 * When the manifest's weight.available flag is false: returns INSTAHAM_ML_ERR_UNAVAILABLE
 * and {"status":"unavailable","reason":"body_mask_port_incomplete",...}.
 */
InstahamMlStatus instaham_ml_predict_weight_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);

/*
 * Provisional feature path: the five features (RA,LC,BL,BW,E) from the raw YOLO mask, with
 * no ji_duan / body_mask head removal. For parity bring-up and the "provisional" UI state
 * while weight estimation is unavailable.
 *   {"status":"provisional","features":{...},"qc":{...},"segmentation_confidence":<num>}
 */
InstahamMlStatus instaham_ml_extract_features_provisional_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* INSTAHAM_ML_H */
