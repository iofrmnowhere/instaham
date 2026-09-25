# ADR-018: Native inference calls run on a worker isolate, serialized from Dart

Status: Accepted

## Context

Every native entrypoint was called synchronously from the Dart main isolate. `PipelineServiceImpl.run`
was `async` in signature only — `MlRuntime.runPipeline` was a plain synchronous function that
blocked until ONNX Runtime returned. `Isolate`, `Isolate.run` and `compute(` appeared nowhere in
`lib/` or `packages/instaham_ml_ffi/lib/`.

The cost of that was measured, not estimated. Median time for one whole-graph run, from
[../device-metrics-results.md](../device-metrics-results.md):

| tier | device | median | max |
|---|---|---|---|
| high | `tokay` | 11 705 ms | 11 824 ms |
| mid | `oriole` | 16 992 ms | 18 408 ms |
| low | `lion` | 70 898 ms | 71 963 ms |

So the UI isolate was blocked for 12–71 seconds per scan. No frame was pumped in that window,
which meant the `CircularProgressIndicator` on `/analysis` painted once and then froze, and on a
low-tier phone the wait sat well inside Android ANR territory. [ADR-008](008-unscaled-cutter-input-is-capped-not-gated.md)
bounds one stage's contribution to that budget; it does not remove the structural problem, and
the earlier architecture note naming "moving the call off the main isolate" as the standing
remedy is what this ADR finally spends.

A second, smaller wait has the same shape: the capture review screen's "Verify reference" button
runs `resolveViewGate`, which is also a real native call on the UI isolate.

Improving the loading UI without moving the work would have produced a nicer *frozen* loading
screen, so the offload had to come first. `docs/plan-2.md` is the plan; the implementation and its
alternatives are in [../plan-phase-2/1-isolate-offload.md](../plan-phase-2/1-isolate-offload.md).

## Decision

**`MlRuntime` wraps each blocking `*_json` entrypoint in `Isolate.run`, and serializes every call
through a Dart-side single-slot queue.** Three entrypoints are offloaded — `classifyView`,
`runPipeline`, `runPipelineRequest` — because those are the three a user waits on. The remaining
wrappers are unchanged.

The shape of the offload, and why each part is what it is:

- **The context pointer is sent to the worker as-is.** `Pointer<InstahamMlContext>` crosses the
  isolate boundary because both isolates are in the same isolate group and the pointer is only an
  address into memory they already share. No Dart-heap object crosses.
- **The worker opens its own bindings** rather than closing over the caller's. A `DynamicLibrary`
  handle is not guaranteed sendable, and `dlopen` of an already-loaded library is a refcount bump,
  not a second load of the ~80 MB of models.
- **The worker reads `instaham_ml_last_error()` itself** and returns the string inside its result
  record. That storage is `thread_local` (`instaham_ml.cpp`), so an error raised on the worker's
  thread is invisible from the UI isolate. This is a correctness requirement of the offload, not a
  convenience.
- **Calls are serialized by `CallQueue`** (`lib/core/utils/call_queue.dart`), a single-slot queue
  that runs tasks strictly in enqueue order regardless of how long each takes, and whose failed
  task never wedges the tasks behind it. It is a top-level class rather than private to
  `MlRuntime` precisely so it can be unit-tested, since `ml_runtime.dart` itself cannot run
  host-side.

**No ABI change.** No exported symbol gains, loses, or changes a parameter;
`INSTAHAM_ML_ABI_VERSION` stays 1. The alternatives that would have changed it — a native worker
thread, or an async/callback-shaped C API — were not taken, because the blocking call is
acceptable once it is off the UI isolate and neither alternative buys anything this product needs.

## Consequences

**The native context is now reached from more than one thread over a process's life**, which it
was not before. The safety argument is: the `Context` struct holds a `Manifest` and four
`OnnxRunner`s, is not mutated after `instaham_ml_create`, and `Ort::Session::Run` is documented
thread-safe. That argument is read from the code, not proven by a concurrency test — which is
exactly why `CallQueue` exists. The serialization keeps the claim the app depends on as small as
possible: never two calls in flight at once, the same invariant that held before the offload.

**`thread_local` error storage became load-bearing.** Before, "thread-local" was an
implementation detail nobody could trip over, because every call ran on one thread. Now reading
`instaham_ml_last_error()` from the wrong isolate silently returns an empty string. Any future
entrypoint that gets offloaded must read its error inside the worker. See
[../ffi-bridge.md](../ffi-bridge.md).

**Callers must not bypass `MlRuntime`'s queue.** Two concurrent calls into one
`InstahamMlContext` are outside anything this app has exercised. Nothing enforces this at the ABI
level; it is a Dart-side convention with a test behind it.

**Per-call overhead is added and is not free**, though it is small against a 12–71 second call:
spawning the worker, a second `dlopen` refcount bump, and passing the image path and result JSON
across the boundary. Post-inference RSS was 1.5 GB on `tokay` before this change and the one
native context is still shared rather than duplicated, but no measurement has been taken *after*
the change — a re-measure would cost Firebase Test Lab quota and has not been authorized.

**What the user sees changes too, and that is deliberate.** Because frames now pump for the whole
run, `/analysis` renders a live progress state with honest phase labels, and leaving mid-run is
safe — the run continues on the worker isolate and persists regardless of whether the screen is
alive. The UI contract this establishes is recorded in [../design-system.md](../design-system.md);
the flow is in [../app-flow.md](../app-flow.md).

**Verification.** Host: `test/core/utils/call_queue_test.dart` pins enqueue-order completion when
an earlier task is slower than a later one, and that a failed task neither wedges the queue nor
loses its own error. The offload itself cannot be verified host-side at all — `flutter test`
cannot `dlopen` the native library — so its proof is a sideloaded APK. Device-verified on
`/analysis` (user confirmation, 2026-09-23 session); the capture review screen's offloaded
`classifyView` path has been exercised host-side only, and one full end-to-end device check
covering indicator liveness, result equivalence, and a back-press mid-analysis is still owed.
