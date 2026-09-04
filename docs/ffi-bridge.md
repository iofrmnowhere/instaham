# FFI Bridge Conventions

The contract between `lib/services/ml/ml_runtime.dart` +
`packages/instaham_ml_ffi/lib/instaham_ml_bindings_generated.dart` and the C ABI declared in
`packages/instaham_ml_ffi/src/include/instaham_ml.h`. If code and this document disagree,
one of them is a bug — fix it immediately.

## Payload shape

Nothing but strings and one opaque pointer crosses the boundary. Every inference entrypoint
takes a UTF-8 path (or a UTF-8 request JSON) and writes a heap UTF-8 JSON string out. No C
structs are shared, so a new envelope field is an additive change that cannot break the ABI.
`INSTAHAM_ML_ABI_VERSION` is 1 and is bumped only for a breaking signature change; adding a
new exported symbol is not one.

## Function signatures

| C symbol | Dart wrapper | Purpose |
|---|---|---|
| `instaham_ml_create(const char*, InstahamMlContext**)` | `InstahamMlBindings.create` | Load + hash-verify manifest, open ORT sessions |
| `instaham_ml_destroy(InstahamMlContext*)` | `.destroy` | Free the context |
| `instaham_ml_abi_version()` | `.abiVersion` | Diagnostics |
| `instaham_ml_build_info()` | `.buildInfo` | Static string, never freed by the caller |
| `instaham_ml_last_error()` | `.lastError` | Thread-local, valid until the next call on that thread |
| `instaham_ml_capability_available(ctx, const char*)` | `.capabilityAvailable` | 1 iff the capability exists **and** its manifest `available` flag is true |
| `instaham_ml_string_free(char*)` | called inside `_invoke` | Frees an out-param string |
| `instaham_ml_classify_view_json(ctx, path, char**)` | `.classifyView` | View gate only |
| `instaham_ml_classify_health_json(ctx, path, char**)` | `.classifyHealth` | Health only |
| `instaham_ml_segment_json(ctx, path, char**)` | `.segment` | Detection counts only, no mask pixels |
| `instaham_ml_predict_weight_json(ctx, path, char**)` | `.predictWeight` | Standalone weight branch |
| `instaham_ml_extract_features_provisional_json(ctx, path, char**)` | `.extractFeaturesProvisional` | Five features off the raw mask, parity bring-up |
| `instaham_ml_run_pipeline_json(ctx, path, char**)` | `.runPipeline` | Whole graph, no scale |
| `instaham_ml_run_pipeline_request_json(ctx, request_json, char**)` | `.runPipelineRequest` | Whole graph, request-shaped |

The request-shaped entrypoint takes `{"image_path":<str>, "cm_per_px":<num|omitted>}`.
Unknown keys are ignored, so future inputs are additive fields rather than new symbols.
`instaham_ml_run_pipeline_json` is implemented as a call into it with `cm_per_px` omitted.
The request JSON is built in `ml_runtime.dart`, not in the bindings class, which stays a
thin typed wrapper that does not know the schema.

`image_path` must point to an **already-EXIF-normalised** RGB image. The native layer never
rotates.

## Memory ownership

| Buffer | Allocated by | Freed by |
|---|---|---|
| Path / request `Pointer<Utf8>` | Dart (`toNativeUtf8`) | Dart, in a `finally` (`calloc.free`) |
| `Pointer<Pointer<Utf8>>` out-slot | Dart (`calloc`) | Dart, in a `finally` |
| Out JSON string | C++ (`std::malloc` in `instaham_ml.cpp`) | Dart, via `instaham_ml_string_free` before the `finally` releases the slot |
| `InstahamMlContext*` | C++ (`new`, in `instaham_ml_create`) | Dart, via `instaham_ml_destroy` |
| `instaham_ml_build_info()` / `instaham_ml_last_error()` | C++ static / thread-local | Nobody — never pass these to `string_free` |

An out JSON string is written **even on error**, so `_invoke` frees it unconditionally when
the out-slot is non-null. A null out-slot decodes as `{}` rather than throwing.

The context is created once per process by `MlRuntime`; concurrent callers of
`MlRuntime.instance()` share the same in-flight future. A failed load clears the cached
future so a later call retries — asset staging copies roughly 80 MB and can fail for
transient reasons such as low disk space.

## Error propagation

Three layers, in order of precedence:

1. **`InstahamMlStatus` return code** — `ok`, `errManifest`, `errHashMismatch`,
   `errModelLoad`, `errIo`, `errInference`, `errUnavailable`, `errContract`,
   `errInvalidArg`. Dart maps it through `MlStatus.fromValue`; an unknown integer falls
   back to `errInference` rather than throwing. **Callers branch on this status, never on
   JSON shape.**
2. **The JSON envelope** — always well-formed. On a request-level failure it is
   `{"status":"error"|"unavailable","error_code":<int>,"message":<str>}`. For the
   whole-graph entrypoints the return code is `INSTAHAM_ML_OK` for anything short of a null
   argument: a stage that fails reports its own `status` inside the envelope
   (`ok` / `stopped` / `skipped` / `unavailable` / `error`) with a machine-readable `reason`
   and, where the user must be told something, a `user_message_key`. This is what keeps a
   failed weight branch from blocking health.
3. **`instaham_ml_last_error()`** — a thread-local diagnostic string for the last call on
   that thread. Used in the `StateError` message thrown when `instaham_ml_create` fails;
   never parsed.

`InstahamMlBindings.create` is the only wrapper that throws. Every inference wrapper returns
a `(MlStatus, String)` record and lets the caller decide.
