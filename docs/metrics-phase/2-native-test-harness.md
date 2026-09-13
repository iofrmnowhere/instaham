# Metrics plan phase 2 — native test harness seam

Status: **done**. `flutter test` now reports 93 passed / 22 skipped / 0 failed — the extra
skip is the harness's own smoke test when `INSTAHAM_NATIVE_TESTS` is unset, which is the one
deliberate remaining skip this plan allows (`docs/metrics-plan.md` phase 2).

## What this phase delivers

`test/support/native_harness.dart`, so Tier B scenario tests (phase 4) and the parity suite
(phase 5) can drive the real native pipeline from `flutter test` without going through
`MlRuntime`. `MlRuntime` stages assets via `rootBundle` and resolves a directory via
`path_provider`, neither of which works in a host `flutter test` process, and the plan
explicitly rejected adding test-only branches to that production loading code. The harness
instead builds the `InstahamMlContext` straight from the repo's own `assets/ml/manifest.json`
on disk, using the existing generated bindings (`InstahamMlBindings`), and exposes the same
`(MlStatus, Map<String, dynamic>)` envelope shape `IPipelineService.run` returns. Nothing in
`lib/` changed.

## Changes

| file | change |
|---|---|
| `test/support/native_harness.dart` | new — `NativeHarness` + `NativeHarnessLoad` (`NativeHarnessReady` / `NativeHarnessSkip`) |
| `test/support/native_harness_test.dart` | new — phase 2's required smoke test |

## Design

- `NativeHarness.load()` never throws. It returns a `NativeHarnessSkip` with a precise
  reason — not `INSTAHAM_NATIVE_TESTS=1`, non-Windows, no built DLL found, manifest missing,
  or the preload/`instaham_ml_create` call itself failing — or a `NativeHarnessReady`
  wrapping a live harness. Callers `switch` on the sealed result and call
  `markTestSkipped(reason)` in the skip case, matching the two-tier pattern phase 4 will use.
- Dependent DLLs (`z.dll`, `onnxruntime.dll`, `opencv_core4.dll`, `opencv_imgproc4.dll`) are
  preloaded by absolute path, in that order, before `instaham_ml.dll` — phase 1 findings 1–2:
  `DynamicLibrary.open` of an absolute path does not extend the search path for the library's
  own imports, and a stray `C:\Windows\System32\onnxruntime.dll` (old ORT API version) wins
  the default search order and crashes `OrtGetApiBase` otherwise. This mirrors
  `packages/instaham_ml_ffi/scripts/check_windows_host.dart` exactly.
- `featureFamily` is read directly from `capabilities.weight.feature_family` in the on-disk
  manifest JSON (not through a native ABI call — none exposes it), per AGENTS.md rule 2: the
  feature family and order must come from the manifest, never be hardcoded. The smoke test
  only asserts a value was surfaced, not a specific family name, so the test itself never
  hardcodes the family either.
- `NativeHarness.run()` mirrors `IPipelineService.run`'s branching: no `cmPerPixel` calls
  `instaham_ml_run_pipeline_json`; a non-null `cmPerPixel` calls the request-shaped
  `instaham_ml_run_pipeline_request_json` instead.

## Verification

```
dart format test/support/native_harness.dart test/support/native_harness_test.dart
flutter analyze test/support/          # No issues found!
INSTAHAM_NATIVE_TESTS=1 flutter test test/support/native_harness_test.dart   # 1 passed
flutter test test/support/native_harness_test.dart                          # 1 skipped, reason printed
flutter test --reporter=compact        # 93 passed, 22 skipped, 0 failed
```

The native-backed run printed:

```
manifestPath ends with assets/ml/manifest.json
featureFamily = chen16_noheight (not asserted by name in the test itself)
```

One bug caught during verification: the manifest's `feature_family` lives under
`capabilities.weight.feature_family`, not a top-level `weight` key — the first cut of
`_readFeatureFamily` looked at the wrong path and the smoke test caught it (`expected: not
null, actual: <null>`) before this was recorded as done.

## Not done here (deferred to later phases / out of scope)

- No scenario or parity test consumes the harness yet — that is phases 4 and 5.
- iOS/macOS/Linux hosts are not wired; `load()` skips with a precise reason on any non-Windows
  platform, consistent with phase 1's Windows-only scope.
