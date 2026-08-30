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

/*
 * Marks the C ABI as publicly visible.
 *
 * The build compiles with -fvisibility=hidden (CMakeLists' C/CXX_VISIBILITY_PRESET) so that
 * ONNX Runtime's and stb's symbols stay internal to this .so. Hidden visibility is applied
 * by the COMPILER and cannot be undone by the linker version script -- a symbol compiled
 * hidden is internalized and never reaches .dynsym, so instaham_ml.map's `global:` clause
 * has nothing left to promote. Without this attribute every entry point below vanished,
 * -Wl,--gc-sections then dropped the now-unreferenced implementation, and the .so linked to
 * ~9 KB of nothing -- dlsym failing at runtime with "undefined symbol: instaham_ml_create".
 *
 * Hidden-by-default plus an explicit default on exactly these functions is what actually
 * implements TASKS.md's "clear entry point": the ABI is the only thing callable from
 * outside, and models/helpers cannot be reached around it. The version script stays as a
 * second, independent guard.
 */
#if defined(_WIN32)
#define INSTAHAM_ML_API __declspec(dllexport)
#else
#define INSTAHAM_ML_API __attribute__((visibility("default")))
#endif

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
INSTAHAM_ML_API InstahamMlStatus instaham_ml_create(const char* manifest_path, InstahamMlContext** out_ctx);
INSTAHAM_ML_API void             instaham_ml_destroy(InstahamMlContext* ctx);

/* ---- diagnostics ---------------------------------------------------------- */

INSTAHAM_ML_API int32_t     instaham_ml_abi_version(void);
INSTAHAM_ML_API const char* instaham_ml_build_info(void);  /* static; e.g. "ort=1.17.1 opencv=4.9 commit=abcdef" */

/* Thread-local. Valid until the next instaham_ml_* call on the same thread. */
INSTAHAM_ML_API const char* instaham_ml_last_error(void);

/* ---- result strings ----------------------------------------------------- */

/*
 * Every *_json entrypoint writes a heap UTF-8 JSON string to *out_json, even on error
 * ({"status":"error"|"unavailable","error_code":<int>,"message":<str>}). The caller MUST
 * free it with instaham_ml_string_free.
 */
INSTAHAM_ML_API void instaham_ml_string_free(char* s);

/* ---- capabilities ------------------------------------------------------ */

/* Returns 1 iff `capability` ("view"|"health"|"segmentation"|"weight") exists in the
 * manifest AND its "available" flag is true; 0 otherwise. */
INSTAHAM_ML_API int32_t instaham_ml_capability_available(InstahamMlContext* ctx, const char* capability);

/* ---- inference -------------------------------------------------------- */

/*
 * image_path: absolute path to an ALREADY-EXIF-NORMALISED RGB image. The native layer does
 * NO rotation (AGENTS.md rule 5 is enforced once, Dart-side, at capture time in
 * lib/core/utils/image_service.dart's ImageService.processRawBytes via img.bakeOrientation
 * -- not in MlRuntime, which has no exif-handling method of its own).
 */

/* {"status":"ok","label":<str>,"confidence":<num>,"probabilities":{<cls>:<num>,...},
 *  "class_map_sha256":<str>,"protocol_version":<str>} */
INSTAHAM_ML_API InstahamMlStatus instaham_ml_classify_view_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);
INSTAHAM_ML_API InstahamMlStatus instaham_ml_classify_health_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);

/* Added slice 3/4 (additive; ABI_VERSION unchanged per the contract above -- only a
 * breaking signature change bumps it). Detection only: is there a pig, how confident, how
 * many survived NMS. Does not decode the mask/coefficients into pixels or map them back to
 * source-image coordinates -- that is the geometry-port work the weight branch still needs.
 *   {"status":"ok","pig_count":<int>,"confidence":<num>,"mask_available":<bool>,
 *    "protocol_version":<str>}
 * When the manifest's segmentation.available flag is false: INSTAHAM_ML_ERR_UNAVAILABLE +
 * {"status":"unavailable","reason":<str>,"capability":"segmentation"}. */
INSTAHAM_ML_API InstahamMlStatus instaham_ml_segment_json(
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
INSTAHAM_ML_API InstahamMlStatus instaham_ml_predict_weight_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);

/*
 * Provisional feature path: the five features (RA,LC,BL,BW,E) from the raw YOLO mask, with
 * no ji_duan / body_mask head removal. For parity bring-up and the "provisional" UI state
 * while weight estimation is unavailable.
 *   {"status":"provisional","features":{...},"qc":{...},"segmentation_confidence":<num>}
 */
INSTAHAM_ML_API InstahamMlStatus instaham_ml_extract_features_provisional_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);

/*
 * Added ML_implementation_plan.md revision 7 (additive; ABI_VERSION stays 1 per this
 * header's own contract -- only a breaking signature change bumps it). Runs the whole
 * section-1 graph in one call: view -> segmentation -> construction -> (health |
 * cutter -> feature_calculation). Returns the COMPLETE section-9 envelope, always -- there
 * is no suspended state and no second call, because the cutter is a permanent C++ identity
 * dummy (section 3.4): nothing crosses a runtime boundary mid-pipeline on any platform.
 *   {"status":"ok"|"stopped","pipeline_protocol":<str>,
 *    "view":{...},"segmentation":{...},"construction":{...},
 *    "cutter":{...},"features":{...},"weight":{...},"health":{...}}
 * Returns INSTAHAM_ML_ERR_INVALID_ARG only for a request-level failure (null args); every
 * stage-level failure is reported inside the envelope with its own status instead
 * (AGENTS.md rule 4/8), so this call otherwise always returns INSTAHAM_ML_OK.
 */
INSTAHAM_ML_API InstahamMlStatus instaham_ml_run_pipeline_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* INSTAHAM_ML_H */
