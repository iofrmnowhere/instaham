# Phase 1 — run native inference off the UI isolate

Status: done; device-verified on the `/analysis` path only — see Verification

## Goal

Make every native inference call return to its caller without blocking the UI isolate, so that
any progress indicator in the app actually animates during analysis. No visual change is part
of this phase: the success criterion is that the *existing* `CircularProgressIndicator` on
`/analysis` spins for the whole run.

## Design/Approach

### What is being moved

Two entry points, both currently synchronous FFI on the UI isolate:

- `MlRuntime.runPipeline` — the whole-graph call used by `PipelineServiceImpl.run`, which is
  the 11.7 s / 17.0 s / 70.9 s measurement. It has two native targets: `instaham_ml_run_pipeline_json`
  (no extras) and `instaham_ml_run_pipeline_request_json` (when `cmPerPixel` or
  `viewGateOverride` is set).
- `MlRuntime.classifyView` — used by `resolveViewGate` from the capture review screen. Smaller
  model, but on `lion` it is not free, and it is the wait that today shows nothing at all.

`classifyHealth`, `segment` and `predictWeight` are the isolated-debugging path
(`pipeline_service.dart`'s own comment) and are not on a user-facing wait. Move them only if it
costs nothing; they are not a requirement of this phase.

### Chosen mechanism

`Isolate.run` per call, plus a single-slot serialization lock in `MlRuntime`.

The worker closure receives plain sendable values only — the context pointer as an `int`
address, the image path, and the request JSON — opens the library on its own side with
`openInstahamMl()`, calls the same generated binding, and returns a sendable record of
`(statusCode, responseJson, lastError)`.

Rejected alternative: a long-lived worker isolate with a `SendPort` queue. It avoids a
per-call `dlopen`, but `dlopen` of an already-loaded library is refcounted and costs
microseconds against a 12–71 second run, and the long-lived variant adds isolate lifecycle,
teardown and hot-restart leakage to own. Revisit only if profiling shows spawn cost matters.

### Constraints that must be honoured

1. **The context must already exist before the worker runs.** `MlRuntime.instance()` stages
   ~80 MB of assets using `rootBundle` and `path_provider`, neither of which is available in a
   plain `Isolate.run` closure. Staging and `instaham_ml_create` stay on the main isolate,
   exactly as now; only the per-image call moves.
2. **`instaham_ml_last_error` is `thread_local`** (`instaham_ml.cpp:29`). The worker must read
   it *inside* the isolate and return it; reading it on the UI isolate after the call returns
   yields a different thread's (empty) string. Any current caller that reads `lastError` after
   a failed call has to be rewired to the returned value.
3. **One native call at a time.** Serialize with a `Future` chain (or a `Completer`-based
   mutex) inside `MlRuntime`, so a second caller awaits the first. Nothing has ever exercised
   concurrent calls into one `Context`; the sessions are `SetIntraOpNumThreads(1)` and the
   struct is not mutated after `create`, but the lock keeps that argument from mattering.
4. **The returned string is heap-allocated by native code** and freed through the existing
   binding path. Keep allocate and free on the same side of the call — inside the worker — so
   no raw pointer crosses the isolate boundary.
5. **Public API shape does not change.** `IPipelineService.run` and `IViewModelService.classify`
   keep their current signatures, so `RunAndPersistPipelineUseCase`, every test double
   (`view_gate_override_test.dart`, `reference_scale_forwarding_test.dart`,
   `weight_domain_failure_test.dart`, `functional_scenarios_test.dart`) and the results screen
   compile unchanged.

## Steps

- [x] Add worker entry functions in `lib/services/ml/ml_runtime.dart`
      (`_isolateClassifyView`, `_isolateRunPipeline`, `_isolateRunPipelineRequest`) that each
      take `(Pointer<InstahamMlContext> ctx, String payload)`, run inside `Isolate.run`, open
      their own `InstahamMlBindings` via `openInstahamMl()`, and return
      `(int status, String json, String lastError)`. A `Pointer` is sendable as-is between
      isolates in the same isolate group, so no address-to-int conversion was needed —
      simpler than the address-passing this step originally proposed.
- [x] Extracted the serialization lock to its own public, host-testable class,
      `CallQueue` (`lib/core/utils/call_queue.dart`), rather than a private class inside
      `ml_runtime.dart` — that file itself cannot be exercised in `flutter test` (it stages
      assets via `rootBundle`/`path_provider`), so the queue needed to live somewhere a host
      test could reach it directly. `MlRuntime` holds one `CallQueue` instance and routes
      `runPipeline` through it and `Isolate.run`. `runPipeline` is now
      `Future<(MlStatus, Map<String, dynamic>)>`; `PipelineServiceImpl.run` already declared
      that return type and returned the call directly, so it needed no change at all.
- [x] Routed `classifyView` the same way. No caller read `MlRuntime`'s `_bindings.lastError`
      after `classifyView`/`runPipeline` (grepped `lib/`) — nothing needed rewiring there
      beyond `view_model_service.dart` adding the `await` its call was already missing.
- [x] Confirmed no caller of the moved methods relied on synchronous completion:
      `resolveViewGate` and `execute()` already `await` the service methods that wrap these
      calls. `view_model_service.dart`'s `classify()` destructured `classifyView`'s result
      directly and correctly without `await` while it was synchronous; now that it returns a
      `Future`, the missing `await` needed to be added there.
- [x] Left `classifyHealth`/`segment`/`predictWeight` unchanged — sharing the offload helper
      would have meant redesigning `_invoke`'s function-pointer parameter (a bound method
      can't safely close over the worker isolate the way a payload string can), which is out
      of scope since none of the three sit behind a user-facing wait.

## Verification

Commands run, in order:

```
dart format lib/services/ml/ml_runtime.dart lib/services/ml/view_model_service.dart \
  lib/services/ml/pipeline_service.dart lib/core/utils/call_queue.dart \
  test/core/utils/call_queue_test.dart
flutter analyze
flutter test test/features/inference_pipeline/
flutter test test/core/utils/call_queue_test.dart
flutter test
```

Results:

- `dart format`: 0 changes needed on the pre-existing files; the new test file was
  reformatted once by the formatter itself.
- `flutter analyze`: 1 pre-existing info (`use_null_aware_elements` on the `cm_per_px` map
  literal, present before this change too — confirmed via `git diff`) plus the project's
  existing vendored-package and generated-file notices. No new issues.
- `flutter test test/features/inference_pipeline/`: 21/21 passed (no change in count or
  content from before this phase).
- `flutter test test/core/utils/call_queue_test.dart` (new): 3/3 passed — proves strict
  ordering under a slow-then-fast task sequence, that a failed task doesn't wedge later
  tasks, and that each task gets its own result back.
- `flutter test` (full suite): **122 passed, 39 skipped** (was 119/39 per the last handoff;
  +3 is exactly the new `CallQueue` tests, nothing else moved).

**Device verification is partial.** A sideloaded build was run by the user on 2026-09-22/23:

- **Wait B (`runPipeline`, `/analysis`) — observed working.** The user reported "the spinner
  works when clicking 'confirm and analyze'", i.e. the existing
  `CircularProgressIndicator` now animates through the real run instead of freezing. That is
  the proof this phase was written for, on the 12–71 s path that matters most.
- **Wait A (`classifyView`, the review screen's "Verify reference" step) — not observed
  either way.** That screen renders no indicator at all today (`_buildReview()` never reads
  `_saving`), so there is nothing on it to watch animate until phase 2 adds one. Its
  offload is host-verified only.
- **Result equivalence — not checked.** Nobody has confirmed that the persisted result for a
  given photo is identical to the pre-offload behaviour; the user's scans completed and
  looked normal, which is weaker evidence than a same-photo before/after comparison.

Note the freeze the user *did* hit during this check was a different defect entirely, in the
pure-Dart capture path — see [1.1-image-processing-freeze.md](1.1-image-processing-freeze.md).

## Open questions

- Whether `MlRuntime._instance`'s context pointer should be revalidated inside the worker (it
  cannot be, cheaply). Accept: the context outlives the process's analysis window because
  `instaham_ml_destroy` is never called during normal operation.
