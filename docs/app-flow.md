# App Flow — capture to results

The Dart side of a scan: camera shutter → routing → one native call → persisted results.
The C++ model graph this call runs is documented in [pipeline/README.md](pipeline/README.md);
this file covers only what Flutter does around it.

Source of truth: `lib/features/capture/presentation/screens/capture_screen.dart`,
`lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`,
`lib/services/ml/pipeline_service.dart`.

The one thing that is easy to get wrong: **the view gate runs at capture time, not at
analysis time.** It decides which screen the user sees next, so it cannot wait for the
results screen.

## The view model has three labels

Read by name from `view/classes.json`, never by index (`AGENTS.md` rule 1). The label is
always the model's argmax — there is no confidence threshold anywhere in the routing path,
because the model's recorded metrics were measured under argmax. Confidence is displayed and
drives a display-only `uncertain` flag on the health card below `kHealthUncertainBelow`
(0.60), but it never changes a route or a label.

| Label | Weight branch | Health branch | Reference marking |
|---|---|---|---|
| `dorsal_valid` | runs | runs | shown (Reference mode) |
| `health_only` | skipped | runs | skipped (after the route dialog) |
| `reject` | stopped | stopped | n/a — route dialog |
| `reject` or `health_only`, overridden to `dorsal_valid` | runs | runs | shown (Reference mode) |
| `reject`, overridden to `health_only` | skipped | runs | skipped |

## Stage A — capture-time routing

`CaptureScreen._usePhoto()` bakes EXIF orientation once via
`ImageService.processRawBytes` (`AGENTS.md` rule 5 — no later stage rotates), then calls
`RunAndPersistPipelineUseCase.resolveViewGate`, which runs the view classifier and persists
the label as a `view` `PipelineEvent`. That event is reused at analysis time, so the model
never runs twice.

### When the scan row is actually created

A scan row is **not** created by opening the camera. `didChangeDependencies` only adopts an
incoming `initialArgs.sessionId`; the first writer is `_capture()` or `_pickFromGallery()`,
whichever produces a photo first, and each of those calls `_ensureSession()` only *after* the
image has been processed and the widget is confirmed still mounted. By the time `_usePhoto()`
runs, `_ensureSession()` normally finds that row already there.

The practical consequences, all deliberate
([plan-phase-2/2.1](plan-phase-2/2.1-capture-screen-guards.md) finding 3):

- Opening the camera and leaving writes nothing.
- Quitting *during* capture or gallery-pick processing — before the mounted check — writes
  nothing either.
- Reaching the review screen and then leaving **does** leave a row in status `captured` with
  no results. That is the one path that still produces a row the user did not finish, and it
  is not cleaned up; `ScanStatuses.cancelled` exists but is deliberately unused, because the
  chosen design writes no row at all rather than writing one and hiding it.

### The capture-time wait

`resolveViewGate` is a real native call and the review screen's "Verify reference" button is
a user-facing wait, so the review screen has its own busy state: while `_saving` is true the
button shows an inline indicator, and "Retake", "Verify reference", the shutter, the gallery
button, the guidance button, and the reference picker are all disabled. `_usePhoto()` also
re-checks `_saving` on entry, because a fast double-tap can enter the method twice before the
first `setState` lands a frame later.

There is **no** `PopScope` on this screen, deliberately — unlike `/analysis`. Under the
ordering above there is no in-flight work whose result the user would lose by leaving, so
there is nothing to warn about.

Routing on the label:

- `reject` or `health_only` → one dialog, `showViewChoiceDialog()`, with **three** stacked
  actions ([adr/020](adr/020-view-route-override-either-route.md), widening
  [adr/017](adr/017-user-consent-view-gate-override.md)):
  - **Retake photo** sets status `rejected` and returns to the camera, on either verdict. No
    override is recorded. Dismissing the dialog counts as Retake.
  - **Check health only** takes the `health_only` route. On a `reject` it records a
    `view_override` `PipelineEvent` with status `override:health_only`; on a `health_only`
    verdict it is the verdict's own route and records nothing.
  - **Check weight and health** records a `view_override` event with status
    `override:dorsal_valid` and takes the `dorsal_valid` route.

  The override event is keyed to that image's sha256, never to the scan, and the verdict's own
  `view` event is never rewritten. After the dialog, routing follows the effective route (the
  override when one was chosen, otherwise the verdict) exactly as below.
- `health_only` (verdict or chosen route) → `skipReference = true` → status `analyzing`, an
  `analysis`/`queued` event explaining the skip, push `/analysis`. Reference marking exists
  only to scale a weight, so it has nothing to serve here.
- `dorsal_valid` (verdict or chosen route), or a gate failure (`viewLabel == null`) →
  Reference mode goes to status `referenceReview` and `/reference-marking`; height mode goes
  straight to `analyzing` and `/analysis`.

A view-gate failure is caught and logged, then falls through to unfiltered routing rather
than blocking the user — `AGENTS.md` rule 4 applied to the gate itself.

### Reference marking (`/reference-marking`)

`ReferenceMarkingScreen` collects a reference object and two endpoints, computes
`cm_per_pixel = lengthCm / originalPixelLength`, and persists it. Endpoint coordinates map
to the **displayed image rectangle including `BoxFit` letterboxing**, not raw widget bounds
(`AGENTS.md` rule 9), then convert to original-image pixels.

Only a fully confirmed annotation counts as a scale (`AGENTS.md` rule 7). The use case
requires `userConfirmed`, `sameFloorPlaneConfirmed`, and `cmPerPixel > 0`; anything else —
in progress, unconfirmed, or predating the feature — is treated exactly like "no reference
marked" and passes `null`.

## Stage B — analysis (`/analysis` → `ResultsScreen`)

`ResultsScreen` lazily runs the pipeline the first time a scan has an image but no stored
health result, then reloads the bundle and renders. A retake, or a scan with no image, just
renders stored state.

### Where the work runs, and what the user sees

The native call does not run on the UI isolate. `MlRuntime` hands each native entrypoint to
`Isolate.run` and serializes every call through a `CallQueue`, so the UI isolate keeps pumping
frames for the whole 12–71 second run
([plan-phase-2/1](plan-phase-2/1-isolate-offload.md); `docs/device-metrics-results.md` for the
latency figures). The worker opens its own bindings rather than closing over the caller's, and
reads `instaham_ml_last_error` on its own thread, since that value is `thread_local`.

While `_bundle` is unresolved the screen renders `AnalysisProgressView`, which shows an
indeterminate indicator, an elapsed-seconds counter, an expectation line, and a label naming
the phase Dart is actually in — `loadingBundle` → `runningPipeline` → `reloadingBundle`. Those
three are the only boundaries Dart can observe: the native call is one opaque blocking call,
so there is no per-stage checklist and must not be one. Inventing ticks for
segmentation/measurement/weight would be a fabricated completed state (`AGENTS.md`).

Leaving mid-analysis is safe and is **not** blocked. The run continues on the worker isolate
and persists whether or not this screen is alive, so `PopScope` warns once — "Analysis will
finish in the background" — and lets the second press through. The warning is armed only while
the pipeline itself is running, not during the cheap bundle load and reload either side of it.
There is no cancel affordance, because a native call already in flight cannot be interrupted.

`RunAndPersistPipelineUseCase.execute` then:

1. Reads the persisted view gate, and on any verdict looks up a `view_override` event whose
   image identity matches the image being analyzed (`viewRouteOverride()`; a legacy round 9
   `override` status reads as `dorsal_valid`). A `reject` with no override saves both branches
   ineligible, sets status `rejected`, and returns. Otherwise the chosen route, if any, is
   passed down as `viewRouteOverride` to the native call, which sends it as
   `view_route_override` ([ffi-bridge.md](ffi-bridge.md)).
2. Resolves `cmPerPixel` from the reference annotation under the three conditions above.
3. Makes **one** native call — `PipelineServiceImpl.run` → `MlRuntime.runPipeline` →
   `instaham_ml_run_pipeline_request_json` — and rejects a non-OK status or a `stopped`
   envelope.
4. Persists the envelope block by block: a `scale` event, the health result (always, and
   independent of weight — `AGENTS.md` rule 4), the **whole** `segmentation` and
   `construction` blocks as event messages, the `features` block on every run whether or not
   it succeeded, and the weight result.
5. Sets status `completed` only when the weight branch produced a number, otherwise
   `blocked`.

Blocks are persisted whole, not reduced to a couple of fields, so a scan can be diagnosed
from a stored envelope instead of a code read — that is what `rungs_tried`, `ladder_rung`,
`content_scale`, and `mask_diagonal_fraction` are for.

A successful weight result also stores the reference values and the RA/LC/BL/BW/E vector
that produced it, so a stored scan can be re-derived later. An `extrapolated` flag from the
regressor is folded into the model-version note: a feature past the trained range is answered
from an edge leaf, which is a pinned ceiling or floor, not an interpolated estimate.

`execute` never throws. A native or ORT failure is caught, recorded as a `pipeline`/`error`
event with both branches saved ineligible and status `blocked`, because surfacing an
exception to the UI would leave the user with no explanation.

## Result states the UI must distinguish

Collapsing these into one "Unavailable" is a regression that has already happened twice
(historical: `old_mds/TASKS.md`, Cause B/C); each card splits them deliberately.

| Card | State | Meaning |
|---|---|---|
| Health | ok | label + confidence; `uncertain` badge below 0.60 |
| Health | ok, **re-checked** | the whole photo was not `Healthy`, so the pig alone was classified again and that label is shown (`preprocessingVersion` `cascade_v1:segmentation_masked`); worded as a possible indicator, never a confirmed diagnosis — [pipeline/health.md](pipeline/health.md) |
| Health | Unavailable | classifier failed — never blocked by the weight branch |
| Weight | **Skipped** | routing outcome: the route that ran was not `dorsal_valid`. Not a failure. |
| Weight | **Unavailable** | genuinely no number: no pig detected, segmentation failed, no confirmed reference scale, or an eligibility/domain check rejected the features |
| Weight | ok | a kg value |

Never display an invented score, and never show a completed state for a branch that did not
produce one.

The photo check itself has no card. Round 10 removed the "Photo framing" card and the
"Photo check overridden" banner ([adr/020](adr/020-view-route-override-either-route.md)); an
override is kept only in the database and the envelope, and nothing on screen shows it. Both
cards read `LocalScanBundle.effectiveRoute` — the override when present, otherwise the verdict
— so **Skipped** means the route that actually ran, never the raw verdict: weight is Skipped
only when that route is not `dorsal_valid`, and health is Skipped only for a `reject` with no
override.

Why a weight number is or is not available at all — the `weight.available` manifest flag — is
in [pipeline/prediction.md](pipeline/prediction.md). The blocking reason is no longer the cutter
identity stub: that was ported ([adr/009-cutter-ported-after-all.md](adr/009-cutter-ported-after-all.md),
superseding [adr/001](adr/001-cutter-identity-stub.md)). The shipped manifest currently sets
`weight.available: true` under the `--enable-for-testing` export override, with
`stability: temporary`, so numbers do reach this card; the `else` branch's
`weight_pending_field_validation` is what a non-override build would carry.

**Every kg value this card shows is provisional, and the UI must keep saying so.** The
`cm_per_px_target` behind it is 0.34, a seven-row host measurement rather than a field
calibration ([adr/012-measured-scale-target.md](adr/012-measured-scale-target.md)), and the same
round measured a ~5% residual error that persists with scaling contributing nothing at all. Below
roughly 85 kg the number is systematically high, because the regressor cannot emit a value under
about 73 kg ([adr/010-regressor-training-domain-floor.md](adr/010-regressor-training-domain-floor.md)).
The manifest's `weight.note` carries this and the envelope passes it through — surface it rather
than presenting a bare figure, and never round it into a confident-looking result.
