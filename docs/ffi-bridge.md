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
| `instaham_ml_classify_health_json(ctx, path, char**)` | `.classifyHealth` | Health only, one pass: no region, so never the two-stage cascade |
| `instaham_ml_segment_json(ctx, path, char**)` | `.segment` | Detection counts only, no mask pixels |
| `instaham_ml_predict_weight_json(ctx, path, char**)` | `.predictWeight` | Standalone weight branch |
| `instaham_ml_extract_features_provisional_json(ctx, path, char**)` | `.extractFeaturesProvisional` | Five features off the raw mask, parity bring-up |
| `instaham_ml_run_pipeline_json(ctx, path, char**)` | `.runPipeline` | Whole graph, no scale |
| `instaham_ml_run_pipeline_request_json(ctx, request_json, char**)` | `.runPipelineRequest` | Whole graph, request-shaped |

The request-shaped entrypoint takes
`{"image_path":<str>, "cm_per_px":<num|omitted>, "view_route_override":<str|omitted>}`
(plus the legacy `"view_gate_override":<bool>` alias below).
Unknown keys are ignored, so future inputs are additive fields rather than new symbols.
`instaham_ml_run_pipeline_json` is implemented as a call into it with both optional fields
omitted. The request JSON is built in `ml_runtime.dart`, not in the bindings class, which
stays a thin typed wrapper that does not know the schema.

`view_route_override` (round 10, [adr/020](adr/020-view-route-override-either-route.md),
widening [adr/017](adr/017-user-consent-view-gate-override.md)): `"dorsal_valid"` or
`"health_only"`, the route the user chose for a `reject` or `health_only` verdict. Any other
string, null, a non-string, or an absent key means no override, which is the pre-existing
behaviour exactly. The route is decided by the pure `stages::resolve_view_route()`
(`src/stages/view_route.h`): a `dorsal_valid` verdict is never changed, `health_only` can be
raised to `dorsal_valid`, and `reject` can go to either route instead of returning the
`stopped` envelope. It changes routing only — the `view` block's `label` keeps the verdict —
and it weakens no other gate.

The round 9 boolean `view_gate_override` is still accepted as an alias: `true` means
`"dorsal_valid"`. It is read only when `view_route_override` is absent or not a string, so a
string key — even an invalid one — wins over the boolean.

When, and only when, the override changes the route that would otherwise run
(`resolve_view_route(label, override) != resolve_view_route(label, "")`), the envelope's `view`
block gains `"override": true` and `"override_route": "<route>"`. A no-op override (anything on
a `dorsal_valid` verdict, or `health_only` → `health_only`) leaves the block exactly as it was.
No exported symbol changed. `MlRuntime.runPipeline` sends `view_route_override` and selects the
request-shaped entrypoint when **either** optional field is present, not only `cm_per_px`.

`image_path` must point to an **already-EXIF-normalised** RGB image. The native layer never
rotates.

## Threading

Three rules, all introduced by [adr/018](adr/018-native-calls-run-on-a-worker-isolate.md) when
native inference moved off the UI isolate:

1. **Blocking entrypoints are called from a worker isolate's thread, not the platform thread.**
   `MlRuntime` wraps `classify_view_json`, `run_pipeline_json` and `run_pipeline_request_json`
   in `Isolate.run`. The other wrappers still run on the calling isolate. Native code must not
   assume any particular thread, and must not touch thread-affine platform state.
2. **Callers must be serialized.** Every offloaded call goes through `CallQueue`
   (`lib/core/utils/call_queue.dart`), so at most one call is ever in flight against the one
   `InstahamMlContext`. Two concurrent calls into one context are outside what this app has
   ever exercised; the `Context` struct is unmutated after `create` and `Ort::Session::Run` is
   documented thread-safe, but that argument is read from the code rather than tested, and the
   queue is what keeps the claim small. Nothing enforces this at the ABI level.
3. **`instaham_ml_last_error()` must be read on the thread that made the call.** Its storage is
   `thread_local`, so an error raised inside the worker reads back **empty** from the UI
   isolate. Each worker reads it before returning and passes the string back inside its result
   record. Any entrypoint offloaded in future must do the same.

Two details that look wrong at a glance and are not:

- **The `Pointer<InstahamMlContext>` is sent across the isolate boundary as-is.** That is safe
  because both isolates belong to the same isolate group and the pointer is only an address
  into memory they already share — no Dart-heap object crosses.
- **The worker opens its own `InstahamMlBindings`** instead of reusing the caller's. A
  `DynamicLibrary` handle is not guaranteed sendable, and `dlopen` of an already-loaded library
  is a refcount bump, not a second load of the models.

No symbol changed signature for any of this; `INSTAHAM_ML_ABI_VERSION` is still 1.

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

The context is created once per process by `MlRuntime` and is shared by every isolate that
calls into it; concurrent callers of `MlRuntime.instance()` share the same in-flight future. A failed load clears the cached
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
   never parsed. For an offloaded call it is read inside the worker and returned with the
   result — see **Threading** above; reading it from the UI isolate instead yields an empty
   string, not the error.

`InstahamMlBindings.create` is the only wrapper that throws. Every inference wrapper returns
a `(MlStatus, String)` record and lets the caller decide.
