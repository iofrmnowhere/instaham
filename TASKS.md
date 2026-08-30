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

---

# Addendum — Cropping the largest abnormality as health-model input

**Status:** proposed, not implemented. Written 2026-08-29 after P0–P2 landed and the health
classification and view-model flow were fixed; revised the same day to adopt the healthy-first
gate, to state the classical-CV scope explicitly, and to record that the work is not blocked on the
mask decode after all.

## The idea, and why it is well-aimed

Feed the health classifier a crop centred on the pig's largest visually abnormal region instead of
the whole photo.

This is aimed at the right target. Cause D above records that `ML/health_cnn/test_predictions.csv`
is 100 % close-up skin-lesion photos from the `health` Roboflow set, while the shipped manifest runs
the checkpoint with `health.input.protocol = "full_frame"` on a phone photo of an entire pig taken
from a distance. The dominant train/serve mismatch is one of **scale**: the model learned what a
lesion looks like when it fills the frame, and it is being shown one that occupies a few percent of
it. Cropping to a lesion-scale region is a direct attack on that mismatch, and it is the first
proposal in this file that could plausibly move accuracy rather than only stop the app
misrepresenting the model.

## Nothing here is retraining — the whole proposal is classical CV

Worth stating flatly, because the revision request asked whether CV could be used *instead* of more
training: it already is, everywhere, and no step below fine-tunes, retrains, or otherwise modifies
either checkpoint.

- The abnormality proposer (P5.2) is CIELAB statistics, morphology, and connected components —
  OpenCV and NumPy, no learned parameters at all.
- The tile sweep (P5.4) runs the *existing* checkpoint forward. It is inference used as a
  measuring instrument, not a training loop.
- The domain normalisation of P5.3 is colour constancy and scale matching, both classical.

The only place retraining appears in this document is as the acknowledged fallback if measurement
shows CV cannot close the gap — see the honest limit stated at the end of P5.3. It is named as the
thing this plan is trying to avoid, not as part of the plan.

## Where it belongs — not `pig_geometry.py`

The suggested home is the wrong one, for three independent reasons.

**1. It would break gate B.** `ML/pig_geometry.py` is the line-for-line reference that
`geometry/pig_geometry.cpp` is measured against. Section 3.1.1 of `ML_implementation_plan.md` states
the invariant plainly: "everything in `pig_geometry.cpp` has a line in `pig_geometry.py` to be
measured against, and nothing else does." Abnormality cropping has no research ancestor — it is new
logic — so putting it in that file adds C++ that gate B cannot score against anything.

**2. The plan already designates a home for exactly this.** Section 3.1.1 carves out
`geometry/health_input.{hpp,cpp}` as "the one deliberate exception" to the one-helper-file rule,
precisely because the health input protocols of section 1.1(c) "were never research code". An
abnormality crop is a fourth health input protocol alongside `full_frame`, `segmentation_crop`, and
`segmentation_masked`. It belongs in `health_input` by the plan's own rule, not by preference.

**3. Neither helper file may touch the photo.** Every function in `pig_geometry.py` takes a mask,
not pixels; abnormality detection is inherently a colour and texture operation on the image. The
other helper, `ML/pig_cutter.py`, is barred from the photo twice over — section 3.3 fixes the
runtime boundary at the segmentation mask ("No photo crosses the boundary — only a binary mask and
five floats"), and `scripts/check_cutter_purity.sh` fails the build on any file IO or non-mask
input.

The Python-side reference therefore goes in a **new `ML/parity/reference_health_input.py`**,
mirroring the established pattern where `ML/parity/reference_yolo.py` is the Python reference for
the C++ segmenter. Parity files are not helper files, so `scripts/check_one_helper.sh` stays green.

## The healthy-first gate — crop only to refine a disease, never to find one

The first draft of this addendum identified the crop's worst failure mode: every healthy pig has
*some* most-unusual patch — mud, a shadow, an ear tag, a skin fold, wet ground at the body edge —
so a pipeline that always crops to the most abnormal region and classifies it will manufacture
disease from healthy animals. `Healthy` currently has the highest recall of any class at 0.9929
(`ML/health_cnn/metrics.json`), and that is exactly what such a design spends.

The gate proposed in review resolves this structurally:

```
full-frame health pass
      |
      +-- label == Healthy      --> report Healthy. Stop. No crop, no second pass.
      |
      +-- label != Healthy      --> propose region, crop, re-run health on the crop,
                                    use the crop's label to name WHICH disease.
```

This is a better design than the first draft's, and it is adopted. Its merits are worth being
explicit about:

- **The Healthy-recall risk disappears by construction.** The crop stage is unreachable unless the
  full-frame pass has already said "disease", so cropping can never flip a healthy animal to a
  diagnosis. The first draft handled this with an acceptance criterion in P5.6 — "Healthy recall
  must not fall" — which only *detects* the regression after the fact. A routing rule that makes
  the regression impossible is strictly stronger than a test that catches it.
- **It is a routing rule, not a threshold.** It branches on the model's own argmax label, which is
  the rule every recorded metric was produced under. It invents no constant, so it does not repeat
  the mistake documented in Cause B.
- **It costs nothing on the common path.** A healthy herd is the expected case, and on it the
  pipeline does exactly one forward pass, as today. The proposer and the second pass are paid for
  only when there is something to refine.
- **It matches what the crop is actually good at.** The scale argument says a close-up view helps
  distinguish *which* lesion this is — the confusion matrix's real problem, where Mange absorbs 16
  Erysipelas and 21 Greasy Pig Disease samples, and Mange itself leaks 15 into Foot-and-Mouth. It
  was never obvious that a crop helps decide *whether* there is a lesion. The gate assigns each
  stage the job it is suited to.

### The one asymmetry the gate introduces, and how to measure it

The gate makes false-positive disease impossible and false-negative disease permanent. If the
full-frame pass misses a small, distant lesion and says `Healthy`, the pipeline stops, and the crop
stage that was most likely to catch it never runs. That is the precise case the scale argument says
full-frame is *worst* at.

For a livestock screening tool this is the more expensive error — a missed infection spreads, a
false alarm costs one inspection. So the gate should not be shipped blind, but neither should it be
complicated on speculation. The cheap resolution:

- **During the P3 measurement run only**, ignore the gate and run both stages on every photo,
  recording both labels. This costs nothing in production because it is not production.
- Count the disagreement cell: full-frame says `Healthy`, crop says disease. If it is rare, the
  gate ships exactly as described above and this paragraph is deleted. If it is common *and
  correct*, add a third outcome — "possible lesion, review" — which reports the disagreement
  rather than silently resolving it either way. Reporting a genuine disagreement between two views
  of one photo is consistent with this file's standing position on naming stage outcomes
  accurately (Cause C), and it invents no score.
- Either way the decision is made from a counted number, not from this document.

## This is not blocked on the mask decode

The first draft asserted P5 was hard-blocked behind the deferred mask decode, on the reasoning that
without a pig mask an anomaly search would be dominated by pen floor and bedding. The second half of
that reasoning is right; the premise is wrong.

`packages/instaham_ml_ffi/src/segmenter.cpp` already decodes bounding boxes — `cx, cy, w, h` per
anchor, filtered by `conf_threshold`, passed through NMS, and sorted by confidence — and
`util/image_io.h`'s `letterbox()` already returns the `scale`, `pad_left` and `pad_top` needed to
map one back to original image coordinates. What is missing is only that
`instaham_ml_segment_json` does not *emit* the box. Adding it is a few lines of arithmetic over
values that are already in memory, not the polygon and coefficient decode that P4 is waiting on.

So the proposer restricts its search to the **pig's bounding box**, which is available now, and is
upgraded to the exact mask later when the decode lands. The envelope records which was used in a
`region_source` field (`"bbox"` or `"mask"`), so the difference is visible in results rather than
assumed. The bbox is a weaker constraint — it admits background in the corners around a standing
pig — which is a reason to prefer the mask when it exists, not a reason to wait for it.

**Adjacent honesty defect, cheap to fix while in this file.** `segment_json` currently reports
`"mask_available": true` whenever any detection survives NMS, even though the header comment for
that entry point states it "does not decode the mask/coefficients into pixels". Nothing downstream
can obtain a mask from a `true` there. Rename or correct it while adding the box.

## P5 — Abnormality-crop health input protocol

Deliberately numbered after P4: it is an accuracy experiment, and P0–P2 are correctness fixes that
should ship first.

### P5.1 Emit the pig bounding box, and declare a fourth protocol

Add the un-letterboxed bounding box of the highest-confidence detection to `segment_json`, and fix
the `mask_available` claim above. Extend `health.input.supported` with `abnormality_crop` and add it
to the `PROTOCOLS` tuple in `ML/export/probe_health_input.py`. The default stays `full_frame` until
a measurement says otherwise — the same discipline P4 follows. Record the proposer's parameters in
a manifest block beside the existing `bbox_padding_ratio` and `background_fill` keys, so they are
declared and swappable rather than compiled in.

### P5.2 Write the Python reference — `ML/parity/reference_health_input.py`

One function per protocol, taking `(image, region)` and returning the 224×224 tensor. This also
retires a stub: `probe_health_input.py::_preprocess` currently raises for the two mask protocols
because no reference exists, so this file makes the existing P4 probe runnable as a side effect.

The abnormality proposer, all classical CV, in order:

1. Take the pig region — mask if available, bounding box otherwise — and erode it slightly so the
   body outline does not itself register as an anomaly.
2. Convert to CIELAB and estimate the pig's dominant skin appearance robustly over the eroded
   interior: per-channel median and median-absolute-deviation, not mean and standard deviation, so
   a large lesion cannot drag the reference toward itself.
3. Score each interior pixel by chromatic deviation on `a` and `b`, combined with a local texture
   term — local standard deviation of `L`, or gradient energy — so that scaly and crusty
   presentations (mange, ringworm, greasy pig disease) register as strongly as purely discoloured
   ones.
4. Select by **rank, not absolute value**: keep the top-k percent of interior pixels. A rank is
   self-referential and cannot silently reject an image the way an absolute cut can.
5. Connected components; keep the largest by area; take its bounding box; pad by
   `bbox_padding_ratio`; expand to at least the training crop scale; clamp to the image.
6. Fall back to the manifest's `on_segmentation_failure` value when no region, or no component, is
   available.

### P5.3 Close the domain gap with CV rather than retraining

Scale is the largest axis of the train/serve gap but not the only one. Roboflow disease photos are
lit and framed unlike a phone photo taken in a pen. Two further classical corrections are cheap,
need no training, and are applied to the crop before normalisation:

- **Colour constancy.** Grey-world or shades-of-grey on the crop, so that the warm cast of a shed
  lamp or the blue cast of open shade does not move a lesion's `a`/`b` statistics — the very
  channels several of these classes are separated on.
- **Scale matching.** Choose the crop window so that the lesion-to-frame ratio approximates the
  training distribution, rather than always cutting a fixed 224 window. The pig's pixel size gives
  the scale estimate directly.
- **Test-time augmentation**, optional and measured: average the softmax over a horizontal flip and
  a small scale jitter. Standard, training-free, and it reduces variance at the cost of forward
  passes — so it is only worth keeping if P5.6 shows it earns them.

**The honest limit.** These corrections address *framing, illumination and scale* skew, which is
what CV can reach. They cannot repair a checkpoint that learned source-specific artifacts — Cause D
notes the health set is a single Roboflow source, and if the weakness is that the model keys on that
source's idiosyncrasies rather than on lesion appearance, no input transform recovers it and
retraining is the only remedy. P5.6 is what tells the two cases apart: a real gain from the crop
means the gap was framing, a flat result means it was not.

### P5.4 Validate the proposer without lesion labels — the tile sweep

The proposer picks one region and there is no annotation to check it against. Build a second,
dumber instrument offline: grid the pig region into overlapping 224-scale tiles, run the existing
health checkpoint on every tile, and take the tile with the highest non-`Healthy` probability. That
is what the model itself considers most abnormal, so agreement between the cheap CV proposer and the
tile sweep's argmax is evidence the proposer is finding the right thing — obtained without a single
lesion annotation and without training anything.

The tile sweep stays offline. It costs one forward pass per tile, and it is far more biased toward
"infected" than a single crop is, since it maximises over a dozen chances to look diseased.

### P5.5 Port to C++ — `src/health_input.{h,cpp}`

New translation unit next to `classifier.cpp`. Note the native tree is currently flat, so this is
`packages/instaham_ml_ffi/src/health_input.*`, not `src/geometry/health_input.*`, until the
section 4.1 restructure happens; the file name fixed by section 3.1.1 is what matters.

`run_classifier` gains an optional pre-cropped image, so protocol selection happens before it and
the softmax path is untouched. The gate itself lives in the pipeline layer, not in
`health_input` — the proposer's job is to produce a region, and deciding whether to ask for one is
a pipeline decision.

### P5.6 Report both passes honestly

`classify_health_json` gains `input_protocol`, `region_source`, the selected `region` (bounding box
plus its area as a fraction of the pig region), and — when the gate fired — the full-frame
probabilities alongside the crop's. These are additive JSON fields, so `INSTAHAM_ML_ABI_VERSION`
does not move; the header's stability contract explicitly allows this.

Surface the region in `ResultsScreen` so the user can see which patch of the pig produced the
diagnosis. A wrong crop then becomes visible and reportable instead of an invisible cause of a wrong
label. When the gate did not fire, say so plainly — the health card should read as a whole-animal
assessment, not imply a close inspection that never happened.

### P5.7 Decide by measurement

On the P3 photo set, with the gate disabled so both stages run on every image, record: overall
health accuracy under `full_frame` alone versus gate-plus-crop; the confusion matrix of the second
stage on the images the gate routed to it, which is where the Mange/Erysipelas/Greasy-Pig confusions
should shrink if the scale argument holds; the size of the disagreement cell described above; and
the proposer-versus-tile-sweep agreement rate from P5.4.

`Healthy` recall is no longer an acceptance criterion, because the gate makes it structurally equal
to the full-frame model's own. It should still be reported, as the check that the gate was
implemented as specified.

## Ordering

```
available now ------> P5.1 --> P5.2 --> P5.3 --> P5.5 --> P5.6
mask decode --------> region_source upgrade: bbox -> mask   (also unblocks P4)
P3 photo set -------> P5.4, P5.7
```

Only the evidence is behind P3 now. The build is not behind anything: the bounding box needed to
start exists in `segmenter.cpp` today.

## What this addendum deliberately does not do

- It does not modify `ML/pig_geometry.py` or `ML/pig_cutter.py`; both purity gates stay green.
- It does not change any C ABI function signature.
- It does not train, fine-tune, or modify either checkpoint.
- It does not train a lesion detector or annotate lesion regions.
- It does not set a confidence threshold anywhere.

## Plan rating: 7.5 / 10

**Pros.** The healthy-first gate is what earns the increase over the first draft's 6.5. It removes
this proposal's single worst risk — cropping manufacturing disease from healthy animals — by making
that path unreachable rather than by testing for it afterwards, and it does so with a routing rule
on the model's own argmax, inventing no constant and repeating none of Cause B's mistake. It also
happens to be free on the common path, and it points the crop at the confusion the matrix actually
shows: telling diseases apart, not detecting that one exists. The second improvement is that the
work is no longer blocked: the bounding box the proposer needs is already decoded in
`segmenter.cpp` and only needs emitting, so the build can start immediately and upgrade to the
exact mask later. Everything in the proposal is classical CV against unmodified checkpoints, so
nothing here commits to a training run. P5.4 remains the strongest measurement idea — it gets real
evidence about an unsupervised component without the annotations that component would normally
need.

**Cons.** The gate's asymmetry is real and is the plan's main open risk: it converts every
full-frame false negative into a permanent one, in exactly the small-distant-lesion case the scale
argument says full-frame handles worst, and the mitigation is deferred to a count that P3 has to
supply. The proposer is still a hand-designed colour and texture heuristic with several free
parameters and no ground truth — the kind of component that reviews well and behaves unpredictably
on real pen photos with mud, wet skin, and hard shadows — and the bbox-first variant makes that
worse until the mask lands, since a bounding box around a standing pig admits a good deal of floor.
Nothing here can be shown to work until P3 exists, so there remains a real chance of building it and
measuring no gain. And the CV corrections in P5.3 reach only framing, illumination, and scale; if
Cause D's deeper reading is right and the checkpoint keys on single-source artifacts, this whole
addendum returns nothing and retraining is the answer after all.

---

## Execution log — 2026-08-29 (Python slice)

**Done.** The classical-CV reference and the probe wiring, the parts that need no build
toolchain and no P3 data:

- **P5.1 (Python half).** `ML/export/probe_health_input.py`: `abnormality_crop` added to
  `PROTOCOLS`; the manifest `input` block now carries an `abnormality` params sub-block
  (erode fraction, top-k percent, texture weight/window, target region fill, grey-world
  flag) sourced from `HEALTH_INPUT_PARAMS` so it is manifest-declared, not compiled in.
- **P5.2.** New `ML/parity/reference_health_input.py` — the single Python reference for all
  four protocols. `full_frame`, `segmentation_crop`, `segmentation_masked`, and
  `abnormality_crop`, plus `propose_abnormality_region()` (mask-erode → CIELAB median/MAD
  skin reference → chroma+texture score → top-k-percent rank → largest connected component
  → padded, scale-expanded, clamped bbox) and a `PigRegion` type that accepts a mask when
  available and the detector bbox otherwise (`source` field records which). This is the
  gate-B reference for the future `src/health_input.cpp`.
- **P5.3.** `apply_domain_corrections()` (grey-world colour constancy) in the same file;
  scale matching folded into the proposer's `target_region_fill` expansion.
- `probe_health_input.py::_preprocess` now delegates to the reference instead of raising
  `NotImplementedError` for the region protocols — the probe becomes a full four-protocol
  probe automatically once region fixtures exist. Region protocols are still skipped
  honestly in the probe loop today (no per-image masks in `test_predictions.csv`).
- Tests: `ML/parity/test_health_input.py` (7 synthetic smoke tests, all pass). Full
  `pytest ML/parity/` green (11 passed); `check_one_helper.sh` and
  `check_cutter_purity.sh` green.

**Not done — needs the Android build toolchain (cannot run/verify here):**

- **P5.1 (native half).** Emit the highest-confidence detection's un-letterboxed bbox in
  `instaham_ml_segment_json`, and correct the `"mask_available": true` claim in
  `segmenter.cpp` (it is set on any surviving NMS detection though no mask is decoded).
- **P5.5.** `packages/instaham_ml_ffi/src/health_input.{h,cpp}` — C++ port of
  `reference_health_input.py`; the healthy-first gate wired in the pipeline layer, not in
  `health_input` itself.
- **P5.6.** `classify_health_json` additive fields (`input_protocol`, `region_source`,
  `region`, full-frame probabilities when the gate fired); `ResultsScreen` region display.
- Manifest default stays `full_frame` — changing it is a measured decision (P5.7), not
  this slice.

**Not done — needs P3 data (a real labelled photo set, does not exist yet):**

- **P5.4** proposer-vs-tile-sweep agreement check.
- **P5.7** the accuracy measurement and the gate-asymmetry disagreement count that decides
  whether the healthy-first gate ships as-is or gains a "possible lesion, review" state.
