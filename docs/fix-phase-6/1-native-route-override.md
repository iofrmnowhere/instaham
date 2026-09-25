# Phase 1 — native route override

Status: done (2026-09-25)

Parent: [`../fix-6.md`](../fix-6.md) (round 10), finding F68.

## Symptom

`run_pipeline` can only turn an overridden `reject` into the `dorsal_valid` route
(`packages/instaham_ml_ffi/src/pipeline.cpp:291-312`). It cannot run a `reject` photo as
health-only, and it cannot run a `health_only` photo as dorsal. The request carries only a
boolean (`instaham_ml.cpp:447-449`).

## Root cause

Round 9 needed one override outcome, so the flag was a boolean and the routing was written
inline as `is_dorsal = view_label == "dorsal_valid" || overridden`.

## Change made (planned)

1. **Request field.** `instaham_ml_run_pipeline_request_json` accepts an optional string
   `"view_route_override"`: `"dorsal_valid"` or `"health_only"`. Anything else (absent, null,
   another string, a non-string) means no override. The existing boolean
   `"view_gate_override": true` stays accepted and means `"dorsal_valid"`, so round 9 callers
   and tests keep working. If both are present, `view_route_override` wins. No exported symbol
   changes, and `INSTAHAM_ML_ABI_VERSION` stays 1.
2. **Pure routing helper.** Move the route decision out of `run_pipeline` into a small
   model-free function (in `pipeline.h`/`pipeline.cpp`, or a new header if that keeps the
   ctest free of ORT), roughly `resolve_view_route(view_label, override_route)`, returning
   `dorsal`, `health_only`, `stopped` or `unresolved`:

   | `view_label` | override | route |
   |---|---|---|
   | `dorsal_valid` | any | `dorsal` (an override never downgrades a clean verdict) |
   | `health_only` | none or `health_only` | `health_only` |
   | `health_only` | `dorsal_valid` | `dorsal` |
   | `reject` | none | `stopped` (`view_rejected`, unchanged) |
   | `reject` | `dorsal_valid` | `dorsal` |
   | `reject` | `health_only` | `health_only` |
   | anything else / view unavailable | any | `unresolved` (fail closed, unchanged) |

   `run_pipeline` then sets `is_dorsal` / `is_health_only` from the helper. Nothing below that
   point changes: segmentation, construction and the health cascade already follow `is_dorsal`.
3. **Envelope.** When an override changed the route, the `view` block keeps its real `label`
   and gains `"override": true` (as today) plus `"override_route": "<route>"`. When the
   override is a no-op (a `dorsal_valid` verdict, or `health_only` → `health_only`), the block
   is left exactly as it is today, with no `override` key.
4. **`run_pipeline` signature.** The `bool view_gate_override` parameter becomes the override
   route (an enum or string, default none). `instaham_ml_run_pipeline_json` still passes none.

## Verification

- New ctest target (or a new group in an existing model-free test) covering every row of the
  table above, plus the request parsing rules in step 1: the bool alias, `view_route_override`
  winning, and invalid values meaning none.
- Build through the BuildTools `vcvars64.bat` / ninja route in `docs/handoff.md`, then
  `ctest -E test_abi --timeout 400`. Expected: the new test passes and the only failure is the
  already-failing `test_scale_normalization`. Check that binaries are newer than sources before
  reporting counts.
- No model run is needed. The routes themselves are unchanged code; only the choice of route
  moved.

### Result (2026-09-25)

- The route decision lives in a pure helper, `stages::resolve_view_route()` in
  `packages/instaham_ml_ffi/src/stages/view_route.h`, covered by the new ctest
  `test_view_route` (`src/test/test_view_route.cpp`).
- The envelope `override` flag is set only when the route actually changed, meaning
  `resolve_view_route(label, override) != resolve_view_route(label, "")`. A no-op override
  leaves the `view` block unchanged, as step 3 requires.
- Binaries rebuilt after the source edits. `ctest -E test_abi --timeout 400`: 11/12 passed;
  `test_view_route` passes and the only failure is the already-failing
  `test_scale_normalization`. No ABI change.

## Open questions

- None beyond the parent's. `docs/ffi-bridge.md` and `docs/spec.md` pick up the new request
  and envelope fields in phase 4, through their owning skills.
