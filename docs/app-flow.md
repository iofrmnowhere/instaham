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
| `health_only` | skipped | runs | skipped |
| `reject` | stopped | stopped | n/a — retake dialog |

## Stage A — capture-time routing

`CaptureScreen._usePhoto()` bakes EXIF orientation once via
`ImageService.processRawBytes` (`AGENTS.md` rule 5 — no later stage rotates), creates the
scan row, then calls `RunAndPersistPipelineUseCase.resolveViewGate`, which runs the view
classifier and persists the label as a `view` `PipelineEvent`. That event is reused at
analysis time, so the model never runs twice.

Routing on the label:

- `reject` → status `rejected`, "Photo not usable" dialog, retake.
- `health_only` → `skipReference = true` → status `analyzing`, an `analysis`/`queued`
  event explaining the skip, push `/analysis`. Reference marking exists only to scale a
  weight, so it has nothing to serve here.
- `dorsal_valid`, or a gate failure (`viewLabel == null`) → Reference mode goes to status
  `referenceReview` and `/reference-marking`; height mode goes straight to `analyzing` and
  `/analysis`.

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

`RunAndPersistPipelineUseCase.execute` then:

1. Reads the persisted view gate. On `reject` it saves both branches ineligible, sets status
   `rejected`, and returns.
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
| View | `dorsal_valid` / `health_only` / `reject` | the routing decision itself, shown as its own card |
| Health | ok | label + confidence; `uncertain` badge below 0.60 |
| Health | Unavailable | classifier failed — never blocked by the weight branch |
| Weight | **Skipped** | routing outcome: not a dorsal photo. Not a failure. |
| Weight | **Unavailable** | genuinely no number: no pig detected, segmentation failed, no confirmed reference scale, or an eligibility/domain check rejected the features |
| Weight | ok | a kg value |

Never display an invented score, and never show a completed state for a branch that did not
produce one.

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
