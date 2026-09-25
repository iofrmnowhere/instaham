# Plan (round 2): a real loading state while the app is analyzing

## Goal

After the user takes a photo and again after they confirm the reference object, the app
appears frozen until the next screen appears. Give both waits a visible, animating,
app-styled progress state, and make that state truthful about what is actually running.

Two distinct waits exist, and the second is the severe one:

| # | Trigger | What runs | What the user sees today |
|---|---|---|---|
| A | "Verify reference" on the capture review screen (`_usePhoto`, `capture_screen.dart:383`) | `resolveViewGate` → the view classifier over FFI | Nothing. `_saving` is set but `_buildReview()` renders no indicator and does not disable the button. |
| B | Confirm on the reference-marking screen → `/analysis` first build | the whole-graph native pipeline (`RunAndPersistPipelineUseCase.execute`) | `Center(CircularProgressIndicator())` (`results_screen.dart:188`) — painted once, then frozen. |

## Why a spinner alone does not fix this

The native calls are **synchronous FFI executed on the UI isolate**. `PipelineServiceImpl.run`
is `async` in signature only: `MlRuntime.runPipeline` is a plain synchronous function that
blocks until ONNX Runtime returns. Nothing in `lib/` or `packages/instaham_ml_ffi/lib/` uses
`Isolate` or `compute` — verified by grep.

Measured medians for one full pipeline run, from `docs/device-metrics-results.md`:

| tier | device | median | max |
|---|---|---|---|
| high | `tokay` | 11 705 ms | 11 824 ms |
| mid | `oriole` | 16 992 ms | 18 408 ms |
| low | `lion` | 70 898 ms | 71 963 ms |

So the UI thread is blocked for 12–71 seconds. The existing `CircularProgressIndicator` on
`/analysis` cannot animate during that window, because no frame is pumped; on a low-tier
phone this is also well inside Android ANR territory. Building a nicer loading screen without
moving the work off the UI isolate would produce a nicer *frozen* loading screen.

Therefore phase 1 is the isolate offload and phase 2 is the UI. That order also means phase 1
is independently valuable and independently verifiable (the existing spinner starts spinning),
and a phase-2 regression can never be confused with a phase-1 one.

## Design/Approach

- **Offload, do not re-architect.** `MlRuntime` keeps ownership of the one native context. The
  worker call receives the context pointer as an integer address and re-opens the shared
  library on its side; the `Context` struct (`instaham_ml.cpp`) holds only a `Manifest` and
  four `OnnxRunner`s and is not mutated after `create`, and `Ort::Session::Run` is thread-safe.
- **Serialize every native call in Dart.** Nothing in this repo has ever exercised two
  concurrent calls into one context, so the plan does not start now: a single-slot queue in
  `MlRuntime` makes calls strictly one at a time, which is also what the product needs (one
  scan analyzed at a time).
- **`instaham_ml_last_error` is `thread_local`** (`instaham_ml.cpp:29`). An error raised on the
  worker isolate's thread is invisible from the UI isolate, so the worker must read it and
  return it inside its result — this is a real correctness constraint of the offload, not a
  nicety.
- **The progress UI must not invent stage completion.** The native pipeline is one opaque call
  with no progress callback, so the only stage boundaries Dart genuinely knows are: view gate
  done, pipeline call running, persisting/reloading. The loading state shows those and nothing
  more (AGENTS.md: never display invented model scores, predictions, or completed states).
  Fabricated per-stage ticks are explicitly out of scope; see open question 2.
- **No new route.** `/analysis` stays the analysis destination and `ResultsScreen` gains a
  progress state, extracted into its own widget. A separate `/analyzing` route would add a
  navigation replace step and a second chance to double-run the pipeline for no user benefit.
- **No behaviour change in the pipeline itself.** No stage, model, manifest, feature vector, or
  database write changes in this plan. The only pipeline-adjacent change is which thread the
  existing call runs on.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Run native inference off the UI isolate | done; `/analysis` device-verified, review-screen path host-only | docs/plan-phase-2/1-isolate-offload.md |
| 1.1 | Fix the capture/gallery-pick freeze (pure-Dart image decode/encode, not FFI) | done, device-verified | docs/plan-phase-2/1.1-image-processing-freeze.md |
| 2 | Loading and progress UI for both waits | implemented; indicators device-checked, rest of the device step owed to phase 3 | docs/plan-phase-2/2-progress-ui.md |
| 2.1 | Guard the capture camera screen while a capture is in flight | done, device-verified; widget tests deferred (no camera/image_picker test harness exists) | docs/plan-phase-2/2.1-capture-screen-guards.md |
| 3 | Validation and documentation | tests + docs done (119 -> 126 passed, 39 skipped); device check owed, capture-review widget test deferred, `pipeline-docs`/ADR-018 flagged not run | docs/plan-phase-2/3-validation-docs.md |

**Where subphase 1.1 came from:** it surfaced during phase 1's device check — a third freeze
point, unrelated to FFI, in the pure-Dart image decode/orientation-bake/re-encode chain that
runs right after the shutter or gallery pick. It blocked phase 2 for the same reason phase 2
was ordered after phase 1 (a progress UI over a frozen isolate is still frozen), and is now
done and device-verified, so phase 2 is unblocked.

## Relationship to the open documents

- `docs/plan.md` (Chen16 regressor swap, phase 5 outstanding) and `docs/fix-4.md` / `docs/fix-5.md`
  are untouched by this round. This plan changes threading and presentation only, so it does
  not interact with their numeric work — but note that round 9 already owes a capture-screen
  widget test, and phase 3 here adds a different one. Keep them separate; do not fold either
  into the other.
- Phase 3 flags a `pipeline-docs` run: the FFI bridge's threading contract changes, which is
  ADR-worthy. This plan does not write that ADR.

  **Flag raised, 2026-09-23 — not yet actioned.** The owed work, for whoever runs
  `pipeline-docs`:

  - **New ADR (next free number is 018): native calls run on a worker isolate.** The decision
    and its alternatives are in [plan-phase-2/1-isolate-offload.md](plan-phase-2/1-isolate-offload.md);
    the ADR records that `MlRuntime` wraps each `*_json` entrypoint in `Isolate.run` rather
    than adding a native thread or an ABI-level async API, and why the Dart-side `CallQueue`
    exists instead of relying on ORT's documented `Run` thread-safety alone.
  - **`ffi-bridge.md` contract changes**, three of them: (1) native entrypoints are now
    called from a worker isolate's thread, not the platform thread; (2) callers must be
    serialized — two concurrent calls into one `InstahamMlContext` are outside what this app
    has ever exercised, and `CallQueue` is what keeps it that way; (3)
    `instaham_ml_last_error`'s `thread_local` storage is now load-bearing rather than
    incidental — it must be read on the worker thread that made the call, or it reads back
    empty.
  - The `Pointer<InstahamMlContext>` crossing the isolate boundary is safe because both
    isolates are in the same isolate group and only an address is sent; the worker `dlopen`s
    its own bindings because a `DynamicLibrary` handle is not guaranteed sendable. Worth
    stating explicitly in the bridge doc, since it looks wrong at a glance.

## Open questions

1. **Cancellation.** The native ABI has no cancel token, so a "Cancel" button cannot stop an
   in-flight run — it could only stop *waiting* for it. Proposal: no cancel button; allow the
   user to navigate back, let the run finish in the worker isolate, and let the use case's
   normal database writes stand so the scan is complete when reopened. Needs the user's call
   on whether a back-press during analysis should be blocked, warned, or silent.
2. **Real per-stage progress.** Truthful stage ticks require a progress callback across the FFI
   boundary (`NativeCallable.listener` plus a native callback invoked between stages). That is
   an ABI change and its own round. Recommendation: defer; ship indeterminate progress with
   honest phase labels now.
3. **A 71-second wait is a product problem, not only a presentation problem.** Phase 2 makes it
   bearable and honest; it does not make it short. Whether low-tier devices need a different
   treatment (background notification, or a device-tier warning before the user commits) is out
   of this plan's scope and needs a product decision.
4. **Memory.** Post-inference RSS is 1.5 GB on `tokay`. The worker isolate shares the one native
   context, so no model is loaded twice, but the Dart isolate itself and the image path
   round-trip add some overhead. Phase 3's device check should confirm no meaningful regression
   rather than assume it.

## Plan rating: 8/10

**Pros.** The root cause is identified and measured rather than guessed — synchronous FFI on
the UI isolate, with 11.7 s / 17.0 s / 70.9 s device medians already on file — so the plan fixes
the freeze instead of decorating it. The phase order makes phase 1 verifiable on its own using
the spinner that already exists, so the two changes never mask each other. Scope is tight: no
model, manifest, schema, or pipeline-stage change, and no new dependency. The two freeze points
are both covered, including the capture-review one that currently shows no feedback at all.

**Cons.** The offload cannot be verified host-side — `flutter test` cannot dlopen the native
library — so phase 1's real proof is a sideloaded APK on a physical phone, which makes the
feedback loop slow and manual. Thread-safety of the native context is argued from reading the
code (immutable after `create`, ORT `Run` documented thread-safe) rather than from a
concurrency test, and the Dart-side serialization exists precisely to keep that argument small.
And the honest progress state still leaves a low-tier user watching an indeterminate indicator
for over a minute, which open questions 2 and 3 park rather than solve.
