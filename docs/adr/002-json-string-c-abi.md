# ADR-002: The C ABI passes JSON strings, not structs

Status: Accepted

Context: The native pipeline returns a result with many optional, per-stage fields whose shape
changes as stages are added, gated, or instrumented. Expressing that as C structs across
`dart:ffi` means every new diagnostic field is an ABI break: the Dart struct layout, the ffigen
bindings, and the `.so` must all ship together or the app reads garbage. The envelope also has
to carry per-stage failure detail, since the weight and health branches must fail
independently rather than collapsing to one error code.

Decision: Every inference entrypoint takes a UTF-8 path or request JSON and writes a heap UTF-8
JSON string out, freed by the caller through `instaham_ml_string_free`. The only shared binary
type is the opaque `InstahamMlContext*`. `INSTAHAM_ML_ABI_VERSION` stays 1 and is bumped only
for a breaking signature change; adding a new exported symbol or a new envelope field is not
one. Inputs are widened the same way: `instaham_ml_run_pipeline_request_json` takes
`{"image_path":…, "cm_per_px":…}` and ignores unknown keys, so a future input is an additive
field rather than another entrypoint.

Consequences: Envelope fields can be added freely — `rungs_tried`, `violations`,
`extrapolated_features` all arrived this way with no ABI change. The cost is JSON
serialization on every call and no compile-time checking of envelope shape, so Dart branches on
the `InstahamMlStatus` return code, never on JSON shape, and decoding failures fall back to an
empty map instead of throwing. Callers must free the out string on the error path too, since
one is written even when the status is not `OK`.
