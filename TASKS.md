# Plan — Misclassification, spurious "Unavailable", and the un-skipped reference step

**Status:** proposed, not implemented. Written 2026-08-29 after the first on-device run of the
slice 3/4 build.

## Observed symptoms

1. Classification sometimes reads "Unavailable".
2. Classification is sometimes wrong.
3. The app still asks for reference-object marking on photos that are not dorsal, even though a
   non-dorsal photo can never produce a weight.

These have three different causes. Symptom 3 and most of symptom 1 are code defects. Symptom 2 is
substantially a model/data problem that no amount of app code will fix.

## Cause A — Reference marking is routed before the view model ever runs (code defect)

`lib/features/capture/presentation/screens/capture_screen.dart`, `_usePhoto()` chooses the next
screen purely from `_mode`, a user-facing toggle that defaults to `MeasurementMode.referenceObject`:

```dart
if (_mode == MeasurementMode.referenceObject) {
  context.push('/reference-marking', extra: args);   // always, regardless of view type
} else {
  context.push('/analysis', extra: args);
}
```

The view classifier does not run here. It runs later, inside `ResultsScreen`, via
`RunAndPersistPipelineUseCase`. So the effective order in the shipped app is:

```
capture -> reference marking -> analysis (view -> health -> segmentation)
```

The order this file specifies at the top is:

```
capture -> view type -> segment -> dorsal? -> (reference/scale + weight) or (health only)
```

The view gate is supposed to be the first thing that runs and the thing that decides whether the
weight branch — and therefore the reference-object step that exists only to serve it — happens at
all. Today it is the last thing that runs, so it cannot gate anything upstream of itself. This is
purely an ordering defect in the Flutter navigation flow; the classifier itself is not involved.

## Cause B — An app-invented confidence threshold manufactures rejects (code defect)

`RunAndPersistPipelineUseCase` declares `kViewConfidenceThreshold = 0.70` and rewrites any
prediction below it to `reject`. That constant is not in the manifest, is not in the checkpoint,
and is not the rule the model was evaluated under. The model's recorded 0.9727 accuracy is an
argmax number.

Replaying `ML/view_model/test_predictions.csv` (5898 rows) through the app's exact logic:

| Threshold | Forced to `reject` | ...of which the model was **correct** | True `dorsal_valid` destroyed |
|---|---|---|---|
| none (argmax) | 0 | 0 | 0 |
| 0.60 | 63 | 26 | 26 |
| **0.70 (shipped)** | **127** | **70** | **70** |
| 0.80 | 222 | 145 | 144 |

The shipped threshold discards 70 correctly-classified dorsal images out of 2599 — a 2.7 % extra
false-reject rate stacked on top of the model's own recorded 2.89 % (`safety_metrics.json`),
roughly doubling it. Every one of those surfaces to the user as a scan that refuses to proceed.

`ML_implementation_plan.md` section 2.1 already states the view-gate safety numbers are "recorded
metrics, never runtime thresholds". The shipped code does the opposite.

`kHealthConfidenceThreshold = 0.60` has the same provenance problem, though it only sets an
`uncertain` flag rather than suppressing a result.

## Cause C — "Unavailable" is the wrong word for "the view gate stopped this" (code defect)

When the view gate rejects, `RunAndPersistPipelineUseCase` writes a health row with
`eligible: false`, and `_healthCard` renders any non-eligible row as the single word
**"Unavailable"**. Meanwhile there is no view card in `ResultsScreen` at all — only `_weightCard`
and `_healthCard` are rendered. `ViewResultEntity` exists in
`lib/features/view_suitability/` but nothing in the running flow displays it.

The user is therefore shown a health failure for what is really a framing decision made two stages
earlier, with no indication of which stage failed, what it decided, or how confident it was. Much
of the reported "unavailable" confusion is this labelling, not a model failure.

## Cause D — Both classifiers are being run outside their training distribution (model/data problem)

This is the part that is genuinely not a code bug.

**View model.** Its three classes are drawn from disjoint source datasets
(`test_predictions.csv` sample-id prefixes):

- `dorsal_valid` (2599) — `pigrgb_rgb`, `pigrgb_masked`, `piglife`, `porac`
- `health_only` (2859) — **entirely** the `health` Roboflow set
- `reject` (440) — weakest class, recall 0.8045

Because `health_only` is exactly one source and `dorsal_valid` is a different set of sources, the
easiest decision boundary available during training was "which dataset did this image come from",
not "what pose is this pig in". A phone photo taken in a real pen resembles none of those sources
closely, so the model is extrapolating, and its 0.9727 test accuracy does not transfer. This is
consistent with the user seeing confident-but-wrong labels on real photos.

**Health model.** `ML/health_cnn/test_predictions.csv` is 2812 rows, 100 % from the `health`
source — close-up skin-lesion crops. The shipped manifest runs it with
`health.input.protocol = "full_frame"` on the whole phone photo. A distant full-frame shot of an
entire pig is a large distribution shift away from a close-up lesion crop, and the model will
still return a confident-looking label because softmax always does.

Note this is also where the pipeline at the top of this file and the current build disagree: that
pipeline says health should consume the **base segmentation mask**, but the shipped manifest feeds
`full_frame`. `ML_implementation_plan.md` section 1.1(c) chose `full_frame` deliberately, arguing
the checkpoint was trained on unmasked photos so a masked crop would be its own train/serve skew.
Both readings are defensible and the question is currently unresolved by evidence: the probe that
would settle it (`ML/export/probe_health_input.py`) reports `probe_status: "not_run"` because the
2812 test images are not in the repository.

## Proposed work, in order

### P0 — Move the view gate ahead of reference marking

Run view classification immediately after capture, before any routing decision, and let its result
drive the flow:

- `dorsal_valid` and reference mode selected → reference marking, then analysis (as today).
- `health_only` → skip reference marking entirely, go straight to analysis; record that the weight
  branch was skipped because the pose was not dorsal.
- `reject` → do not proceed to reference marking or analysis; show a retake prompt explaining why.

Practically this means a small "classify then route" step in `capture_screen.dart`'s `_usePhoto()`,
with `RunAndPersistPipelineUseCase` refactored so the view stage can be invoked on its own and its
result persisted once, rather than being re-run inside `ResultsScreen`. Guard the flow so a native
runtime failure falls back to today's behaviour rather than trapping the user.

Directly resolves symptom 3.

### P1 — Stop suppressing predictions with an invented threshold

Delete `kViewConfidenceThreshold`'s suppression behaviour. Take the model's argmax label as the
decision, which is the rule under which every recorded metric was produced. If a confidence floor
is genuinely wanted later, it must come from the manifest, be justified against a real
precision/recall trade-off on held-out data, and be recorded as such — not hardcoded in a use case.

Keep `kHealthConfidenceThreshold` only as the `uncertain` display flag it already is, and move its
value into the manifest.

Recovers 70 of 127 spurious rejects on the recorded test set.

### P2 — Show the view stage in the UI, and name failures accurately

Add a view/framing card to `ResultsScreen` showing the label and confidence, wired to the existing
`ViewResultEntity`. Change the health card so a view-gated scan reads as
"Skipped — photo was not usable for health screening" rather than "Unavailable", and so a genuine
inference error reads as an error. Persist the view label so the card survives a reload.

This alone will remove most of the reported confusion even before P3.

### P3 — Establish whether the models actually work on real photos

Nothing above improves accuracy; it only stops the app from misrepresenting the models. To answer
"is it a model problem", collect a small labelled set of real photos taken with the app on the
target phone — on the order of 100–200 images spanning dorsal, non-dorsal, and non-pig — and score
both classifiers against it. That produces the first honest accuracy number for the deployed
conditions, as distinct from the training-set numbers, and tells you whether the gap is large
enough to require fine-tuning or recapture of training data.

This subsumes the outstanding slice −1 work: the same collection effort supplies the images
`probe_health_input.py` needs to finally decide `health.input.protocol` on evidence, and the
fixture corpus gate A and gate B are both blocked on.

### P4 — Revisit the health input protocol once P3 has data

With a real labelled set in hand, run the health checkpoint under `full_frame`,
`segmentation_crop`, and `segmentation_masked` and pick the winner by measured accuracy. This
resolves the standing disagreement between this file's pipeline and section 1.1(c) of the
implementation plan with a number instead of an argument. `segmentation_crop` requires the mask
decode that is currently deferred, so this depends on that port landing.

## What this plan deliberately does not do

- It does not touch the native C ABI, the ONNX exports, or the manifest schema.
- It does not implement the weight branch or the mask/geometry port.
- It does not retrain or fine-tune anything; P3 is measurement, and any retraining decision comes
  after its result.

## Plan rating: 7.5 / 10

**Pros.** P0–P2 are small, well-localised Flutter changes against causes verified against the
source and the recorded prediction CSVs, not inferred. They fix the stated complaint and, more
importantly, stop the app from presenting model limitations as failures the user can do nothing
about. P1 is a deletion that measurably improves behaviour. The ordering is honest: it puts the
cheap certain fixes first and does not pretend they improve accuracy.

**Cons.** The plan cannot promise better classification, which is probably what is actually wanted
— P3 is data collection with an open-ended outcome, and if it confirms a large distribution gap,
the real remedy is retraining, which is outside this plan and potentially expensive. P0 also
changes the capture flow's shape, which risks regressions in a screen that currently works, and it
introduces a user-visible dependency on native inference succeeding at capture time rather than at
results time, so its fallback path needs care. P4 is blocked on the deferred mask decode and may
sit unresolved for a while. Rating held below 8 mainly because the highest-value item (P3) is the
least defined and the least under the app's control.
