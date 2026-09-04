# ref_fix.md — round 4

Rounds 2 (F6–F11) and 3 (F12–F17) are **implemented and in the working tree**, and their
items are cited from source comments. Numbering therefore continues at **F18** — never
reuse F1–F17 or those comments start pointing at the wrong thing.

**This round is different from the previous two in one important way: it was not diagnosed
by reading code.** Python 3.13 with `numpy`, `opencv`, `onnxruntime` and `pillow-heif` is
available in this environment, and `assets/ml/` carries the real exported models. The whole
native weight branch was therefore replicated in Python, run against the three photos in
`.pig_pictures/`, and the failure reproduced exactly. Every number below is measured, not
inferred. The harness is checked in at `ML/tools/replicate_native_weight_branch.py`.

Round 3 was **right about its bug and wrong about the layer**, in the same way round 2 was.
F12 was a real divergence from the Python reference and it did change behaviour — but the
correct instance was never among the candidates it was choosing between, so fixing the
choice could not help. The defect is one stage further up still: **the segmenter is being
run at an input scale at which it does not detect a pig at all.**

---

## 1. What the new log proves

### 1.1 Round 3's effect on the three samples

| photo | before round 3 | after round 3 | true |
| --- | --- | --- | --- |
| 92 kg meter stick | rejected, `BL` = 64.0 | rejected — `mask_implausibly_small`, 9.5% of frame diagonal | 92 kg |
| 118 kg porac stick | rejected, `BL` = 14.0, `BW` = 3.0 | rejected — `subject_smaller_than_trained`, `BL` = 140.1, `BW` = 49.9 | 118 kg |
| 96 kg porac stick | 141.1 kg | 139.3 kg | 96 kg |

F12 grew the 118 kg mask by 10× and the 92 kg mask by ~1.4×, so it did what it said. Both
results are still worthless, and F16's new gate correctly caught the 92 kg case with the
right message. **Nothing round 3 shipped needs reverting.** It is all still doing its job;
it is just guarding a stage that is being fed a broken input.

### 1.2 The replication

`ML/tools/replicate_native_weight_branch.py` mirrors, function for function:
`ImageService.processRawBytes` + the picker's 3000 px cap, `util/image_io.cpp::letterbox`,
`stages/segmentation.cpp::run_segmentation` (including `mask_geometry.h`'s F12 selection),
`construct_pig_mask`, `scale_mask_to_training_space` and `extract_five_features`.

Run on the 118 kg photo it reproduces the app's reported `BL` / `BW` / `LC` / `E` to within
5% (134.0 / 48.6 / 400.9 / 0.942 against the app's 140.1 / 49.9 / 385.3 / 0.945), and it
reproduces the 92 kg photo's mask-diagonal fraction to within 0.1 pp (0.096 against the
app's 0.095). It is faithful.

### 1.3 The root cause, visible in one picture

Drawing every surviving detection box on the 640×640 letterboxed input the model actually
receives:

| photo | detections above conf 0.25 | what they are | largest box |
| --- | --- | --- | --- |
| 92 kg | 34 (5 after NMS) | both **ears**, two **flip-flops** | 49×69 px |
| 118 kg | 21 (4 after NMS) | both **ears**, a person's **foot** | 78×96 px |
| 96 kg | 20 (2 after NMS) | the **feet**, another pig's **snout** through a grate | 72×55 px |

The pig itself measures roughly 220×400 px in that same 640×640 input. It is never
proposed. Confidence on the ears runs to 0.87–0.92, so this is not a marginal miss — the
model is confidently detecting pig-*parts* at pig-*sized* scale.

The decisive check: across all 8400 anchors, on all three photos, **every box larger than
about 100×100 px carries a class score of 0.000.** There is no whole-pig detection sitting
just under the threshold. Lowering `conf` cannot recover this.

### 1.4 Why it recovers when the image is made smaller

Placing the same image inside the same 640×640 canvas at a fraction of its fitted size —
i.e. padding the field of view rather than cropping it — and re-running:

| photo | content at 100% | at 60% | at 40% | at 30% |
| --- | --- | --- | --- | --- |
| 92 kg | 49×69 (ear) | 32×33 | 14×17 | **56×140, conf 0.87 — the pig** |
| 96 kg | 72×55 (snout) | **129×301, conf 0.53** | **84×207, conf 0.89** | **63×155, conf 0.67** |
| 118 kg | 78×96 (ear) | 37×29 | none | none |

At the recovered scales the mask is not merely present, it is **clean and complete** —
nose to tail, both flanks, no leakage into the floor or the stick.

Expressed in the only unit that transfers between photos: the app knows `cm_per_px_actual`
from the user's reference object, so it knows how many centimetres one canvas pixel spans.
The model detects reliably when that figure is around **0.9–1.9 cm per canvas pixel**, and
fails completely at the ~0.30 cm/px the current full-frame letterbox produces for a
2250×3000 phone photo. That is a **3–6× scale mismatch**, and it is the entire bug.

### 1.5 Why exactly one of the three photos ever predicted

The 96 kg photo is the only one in which the *current* pipeline can produce a whole-pig
mask, and only in one specific configuration: **rotated 90° clockwise** (landscape, pig's
long axis horizontal), where the model returns a 523×206 box at conf 0.30 and a complete
mask. Upright it returns a 72×55 snout. The other two photos recover in no rotation at
100% scale.

That is consistent with the 96 kg photo being the one scan that ever produced a number, and
with the app having handled its HEIC `irot` differently from the other two. It is not a
complete reconstruction — replaying that rotated path end to end predicts 172.6 kg where the
app reported 139.3 kg, so the app's exact mask is not reproduced. Treat 1.5 as the best
available explanation of the anomaly, not as a settled fact, and confirm it from the
envelope once F20 lands.

### 1.6 The second problem, which only becomes visible once the mask is right

With a correct whole-pig mask, at the manifest's current `cm_per_px_target = 0.26`:

| photo | RA | LC | BL | BW | E | predicted | true |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 92 kg | 0.1599 | 1573 | 543 | 203 | 0.948 | **180.7 kg** | 92 |
| 118 kg | 0.1529 | 1942 | 619 | 233 | 0.936 | **173.8 kg** | 118 |
| 96 kg | 0.1704 | 1765 | 624 | 200 | 0.960 | **181.2 kg** | 96 |

All three land within 5% of each other regardless of a 26 kg spread in true weight. `LC`
(1573–1942) is above the trained maximum of 1540 on all three; `BL` (543–624) and `BW`
(200–233) sit at or above the top of their trained ranges. **The regressor is a gradient-
boosted tree ensemble: it cannot extrapolate.** Once a feature vector passes the top of the
training distribution the prediction pins to the top leaf — measured empirically at
**≈182 kg**, with a symmetric floor at **≈83.5 kg**. Every one of the three photos is being
answered with the ceiling.

So fixing the mask alone converts "two rejections and one +45% number" into "three ceiling
values". F21 is not optional polish; it is the other half of this round.

---

## 2. Root cause

### F18 — segmentation is run at an input scale the model does not detect at (`stages/segmentation.cpp:74-79`)

`run_segmentation` letterboxes the whole frame into 640×640:

```cpp
RgbImage lb = letterbox(img, cap.imgsz, cap.imgsz, cap.letterbox_color, &scale, &pad_left, &pad_top);
```

`letterbox()` fits the *entire image* to the canvas. For a 2250×3000 phone photo that is
`scale = 0.2133`, giving 480×640 of content and a pig ~220×400 px inside it. The model's
detection head does not fire on a pig at that apparent size — §1.3 and §1.4 measure this
directly. This is a property of what the segmenter was trained on, and it is invisible to
every check the pipeline currently runs, because a confident detection *is* returned; it is
just of an ear.

Note what this means for the existing scale handling: `scale_mask_to_training_space` applies
`k = cm_per_px_actual / cm_per_px_target` to the **mask, after segmentation**. That corrects
the *measurement* space and does nothing for the *detection* space, because
`letterbox()` normalises the whole frame to 640 either way — resizing the image before
segmentation, as written today, changes the model's input by nothing at all. Only **padding
the field of view** changes the apparent object scale.

**The fix.** Give `run_segmentation` the user's `cm_per_px_actual` and a new manifest field
`segmentation.input_cm_per_px` (the centimetres one 640-canvas pixel should span). Compose
the canvas at

```
content_scale = cm_per_px_actual / input_cm_per_px
```

instead of `min(640/w, 640/h)`, centre it, pad with `letterbox_color`, and carry
`content_scale` / `pad_left` / `pad_top` through on `SegmentationOutput` exactly as the
existing letterbox parameters already are (F14 made that contract honest — reuse it, do not
add a second path). `construct_pig_mask` then needs **no change at all**: it already
un-pads and rescales using the carried `letterbox_scale` / `letterbox_pad_left/top`, so a
mask found on the new canvas maps back into original image coordinates through the same
code. AGENTS.md rules 6 and 9 are satisfied for the same reason — nothing is resized after
marking without an exact coordinate transform; the transform is the one already there.

Guards, all of which must fail closed rather than silently degrade:

- If `content_scale` would put the content outside the canvas (`round(w*s) > 640` or
  `round(h*s) > 640`), clamp to the plain letterbox fit and record that it was clamped.
- If no `cm_per_px` is available (health-only route, or no reference marked), keep the
  existing full-frame letterbox. The weight branch already refuses without a reference
  (AGENTS.md rule 7), and health degrades to `full_frame` regardless.
- Never invent a `cm_per_px`.

**Measured value for `input_cm_per_px`.** Sweeping it against the three photos, the whole
pig is recovered at:

| `input_cm_per_px` | 0.80 | 0.90 | 1.00 | 1.10 | 1.20 | 1.30 | 1.40 | 1.60 | 1.80 | 2.00 | 2.40 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 92 kg | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 96 kg | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 118 kg | ~ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ |

(✓ = mask bbox diagonal ≥ 35% of the frame diagonal; ~ = 36%, partial.)

**Use 1.10 as the manifest default.** Two of three photos are stable across the whole range
above 0.90; the 118 kg photo is not stable at any single value, which is what F19 exists
for. Put the number in the manifest, not in C++ — it is a property of the exported
segmenter and must travel with it.

### F19 — a scale ladder, because one constant is not enough

The 118 kg row above is erratic in a way no single constant fixes: it detects at 1.30, 1.60,
1.80 and 2.40 and not at 0.90–1.20, 1.40 or 2.00. This is the segmenter being brittle, not
a bug in the scale calculation, and it is exactly the kind of thing a retry ladder handles.

When the first pass at `input_cm_per_px` yields a mask that fails F16's plausibility check,
retry at a small manifest-declared ladder of multipliers of that value and keep the first
mask that passes. Measured ladder that recovers all three photos:

```
input_cm_per_px x { 1.0, 1.32, 1.68 }   -> 1.10, 1.45, 1.85
then, only if all three fail, x 0.77    -> 0.85
then, only if all four fail, conf_threshold 0.10 over the same ladder
```

Result on the three photos: 92 kg picks the first rung (conf 0.91), 96 kg picks the first
rung (conf 0.91), 118 kg picks the second (conf 0.28). Worst case is four extra 640×640 YOLO
passes on a photo that would otherwise have been rejected outright, and the common case is
one pass — the ladder is only entered when the first mask is already known to be unusable.

Record every rung tried and the one selected (F20). Stop at the **first** plausible mask, not
the largest across rungs: "largest mask across scales" is a new selection criterion with its
own failure modes and there is no evidence for it.

### F20 — persist the segmentation telemetry F15 already produces

F15 added `candidates_kept`, `selected_mask_area_proto`, `runner_up_mask_area_proto`,
`selected_box_orig` and `selected_box_frame_fraction` to `envelope["segmentation"]`. The
Dart side then throws all of it away:

```dart
message: 'pig_count=$pigCount confidence=${segmentationJson['confidence'] ?? 0.0}',
```

(`run_and_persist_pipeline_use_case.dart`, the `segmentation` event.) `envelope["construction"]`
— mask area and bbox — is never persisted at all. That is why round 3's fix had to be
evaluated from three user-visible sentences instead of from the data it deliberately
produced.

Persist the whole `segmentation` and `construction` blocks with `jsonEncode`, exactly the way
F4 does for `scale` and F6 for `features`. Add to `envelope["segmentation"]`, for this round:
`input_cm_per_px_used`, `content_scale`, `ladder_rung`, `rungs_tried`, `conf_threshold_used`
and `clamped_to_letterbox`.

This is the cheapest item in the round and the one that decides whether round 5 needs a
device or not. **Do it first.**

---

## 3. Calibration and honesty about the number

### F21 — `cm_per_px_target = 0.26` is roughly 35% too small

The manifest itself labels this value `UNCALIBRATED_seed_estimate_pending_1p88m_calibration_capture`.
With correct masks it can finally be measured, and it is wrong by well over its declared
`cm_per_px_target_uncertainty` of 1.15.

**Derivation, without fitting to the answer.** `ML/weight_prediction/fixed_test_predictions_POSTHOC.csv`
gives the median feature vector of the regressor's own eval rows, by weight bin, on
head-removed masks:

| bin | n | RA | LC | BL | BW |
| --- | --- | --- | --- | --- | --- |
| 85–95 kg | 371 | 0.0797 | 956 | 384.6 | 129.1 |
| 90–100 kg | 505 | 0.0859 | 984 | 394.6 | 133.6 |
| 95–105 kg | 524 | 0.0883 | 997 | 400.2 | 136.1 |

Compare the measured vectors from §1.6 against the bin matching each photo's true weight,
and divide out the uncut-cutter inflation the manifest already documents (`BW` × 1.10, `LC`
× 1.35 — measured from `whole_mask_area_px` / `body_mask_area_px` in the same CSV):

| photo | measured BW | trained BW | ratio | implied target from BW | implied target from LC |
| --- | --- | --- | --- | --- | --- |
| 92 kg | 203 | 130 | 1.56 | **0.368** | 0.311 |
| 96 kg | 200 | 136 | 1.47 | **0.347** | 0.345 |

`BW` is the minor axis of the `minAreaRect`, the one feature the head barely perturbs, so it
carries the least cutter contamination of the five. Both photos put the target in
**0.33–0.37**.

**Independent cross-check.** Sweeping `cm_per_px_target` and reading the regressor's output
lands in the same place — and this is a genuinely separate signal, since it goes through the
trees rather than through the feature medians:

| target | 92 kg | 118 kg | 96 kg |
| --- | --- | --- | --- |
| 0.26 (shipped) | 180.7 (+96%) | 173.8 (+47%) | 181.2 (+89%) |
| 0.30 | 131.8 (+43%) | 135.8 (+15%) | 136.8 (+43%) |
| 0.32 | 117.5 (+28%) | 103.6 (−12%) | 104.5 (+9%) |
| 0.34 | 103.5 (+13%) | 99.0 (−16%) | 107.0 (+12%) |
| **0.35** | **90.0 (−2%)** | **107.7 (−9%)** | **110.3 (+15%)** |
| 0.36 | 87.1 (−5%) | 92.6 (−22%) | 95.8 (−0.2%) |
| 0.38 | 87.5 (−5%) | 82.6 (−30%) | 83.8 (−13%) |

Two independent methods, same band. **Set `cm_per_px_target = 0.35` and
`cm_per_px_target_uncertainty = 1.30`**, and change `cm_per_px_target_source` to say what it
now is: `three_sample_field_estimate_pending_1p88m_calibration_capture`. Do not read the
per-row differences between 0.34, 0.35 and 0.36 as signal — they are three samples through a
step function, and the whole 0.32–0.36 band is equivalent on this evidence.

**What this is and is not.** It is not the 1.88 m calibration capture, and it partially
absorbs the missing cutter rather than separating it — the head/neck inflation and the scale
error both push the same direction, and three photos cannot untangle them. It is a
measured field estimate replacing an admitted guess, and it takes the error from +47…+96%
to roughly ±10%, which is what "the margin shouldn't be too large without the cutter" asks
for. Retune it, downward, the moment the real cutter lands — and record in the manifest that
it must be retuned then, because a cutter landing against a target fitted to uncut masks
would otherwise silently make things worse.

### F22 — say when the answer is a clamp, not an estimate

§1.6's ceiling is a real, permanent property of the model and it is currently invisible: a
saturated 182 kg is presented with the same confidence as a genuine mid-range prediction.

After the F3 domain gate passes, compare the vector against the **unwidened** trained
`[min, max]` — the raw CSV bounds, before `upper_multiplier` and the uncertainty widening.
When any of `RA`, `LC`, `BL`, `BW` is outside them, keep the prediction but mark it:
`envelope["weight"]["extrapolated"] = true`, plus which features and in which direction.
Surface it in the weight card as a range or an "at least / at most" qualifier rather than a
point value.

This also exposes a tension worth naming: F8's `upper_multiplier` of 1.35 on `LC` and `BL`
was chosen to *admit* uncut masks, and every vector it admits above the trained max is a
vector the regressor can only answer with its top leaf. The multipliers are not wrong — they
keep the branch usable while the cutter is missing — but they buy availability with silent
saturation, and the user is entitled to know which they got.

### F23 — raise `min_mask_diagonal_fraction`

Measured, across all three photos: a correct whole-pig mask has a bbox diagonal of
**0.62–0.74** of the frame diagonal. Every wrong mask measured **0.06–0.15**. The gap is
enormous and the current threshold of 0.15 sits exactly on the wrong edge of it — the 118 kg
junk mask measured 0.149 and only just failed to slip through.

Raise `min_mask_diagonal_fraction` to **0.35**. It stays manifest-tunable, it is what F19's
ladder tests each rung against, and no observed correct mask comes within 0.27 of it.

### F24 — check the RA discrepancy the harness turned up

The replication matches the app's `BL` / `BW` / `LC` / `E` on the 118 kg photo to within 5%,
but its `RA` is 0.00728 against the app's 0.00086 — a factor of 8.5 on the same mask that
agrees on every other feature. A 5% difference in outline cannot produce that.

This may be nothing (the two masks are not bit-identical, and `RA` is the only feature that
depends on filled area rather than outline geometry), or it may be a real defect in how the
native side counts area or picks the `RA` denominator. Do not guess: F20 makes the answer a
log read. Check it on the first device run after this round, against the harness on the same
photo.

---

## 4. Validation

| # | command | covers |
| --- | --- | --- |
| 1 | `python ML/tools/replicate_native_weight_branch.py . T` | **F18, F19, F21 — run this before writing any C++.** It is the loop that produced every number above and it takes seconds, not an APK cycle |
| 2 | new `packages/instaham_ml_ffi/src/test/test_segmentation_canvas.cpp` | F18's canvas composition: a known `cm_per_px_actual` and `input_cm_per_px` produce the expected `content_scale` / pads; oversized content clamps to the letterbox fit and sets the flag; a missing `cm_per_px` falls back to the plain letterbox |
| 3 | extend `test_mask_selection.cpp` | F19's ladder: an implausible mask on rung 1 advances to rung 2; a plausible one stops immediately; all rungs failing returns no detection rather than the least-bad mask |
| 4 | `ctest` for `test_feature_domain` | F21's new manifest values parse; F22's unwidened-bounds comparison |
| 5 | `dart format` on changed Dart files | AGENTS.md step 1 |
| 6 | `flutter analyze` | F20, F22 |
| 7 | `flutter test test/features/inference_pipeline/` | F20's persisted blocks, F22's `extrapolated` rendering; extend `weight_domain_failure_test.dart` |
| 8 | `python ML/export/export_xgboost.py` and re-diff `assets/ml/manifest.json` | F21/F23 — the manifest is currently hand-edited; regenerate it properly now that the ML toolchain question is only `xgboost` + `onnxmltools` |
| 9 | rebuild native, sideload, re-run all three `.pig_pictures/` scans | end to end |

**Acceptance.** All three photos must produce a weight. Mask bbox diagonal ≥ 0.55 of the
frame diagonal on all three (measured: 0.62 / 0.71 / 0.72). Predictions within ±20% of true
on all three and within ±10% on at least two (measured at target 0.35: −2.1%, −8.7%,
+14.9%). `candidates_kept`, `ladder_rung` and `content_scale` present in the persisted
`segmentation` event for every scan.

**Non-acceptance.** Do not accept a build where the two currently-failing photos predict but
the 96 kg photo regresses — that photo is the only one with a known-good history and it is
the control.

No Drift schema change: no `schemaVersion` bump, no migration, no `build_runner`. F18, F19
and F23 need a native rebuild; F20, F22 and F21's manifest half do not.

**Order.** F20 first and alone — it costs an hour and it is what makes everything after it
checkable. Then F18, then F23, then F19 (F19 is only meaningful once F18 defines the rung
the ladder is a multiple of). F21 next, on its own commit, so the calibration change can be
reverted independently of the segmentation fix. F22 and F24 last.

---

## 5. What is still out of scope

1. **The cutter.** Still an identity stub, still owned by another team member. F21 partially
   absorbs its bias, which is a compromise, not a fix, and F21 must be retuned when the real
   cutter lands.
2. **Retraining or re-exporting the segmenter.** F18 and F19 work around a model that only
   detects pigs in a narrow apparent-size band. Augmenting its training with scale jitter, or
   re-exporting at a larger `imgsz`, is the real repair. Worth raising with whoever owns
   `ML/segmentation/`, with §1.3 and §1.4 attached — they are a complete, reproducible bug
   report on their own.
3. **The 1.88 m calibration capture.** F21 is a three-sample field estimate. Several
   deliberate captures at a measured 1.88 m, median of the resulting `cm_per_px`, remains the
   correct way to set this, and it is the only thing that lets
   `cm_per_px_target_uncertainty` go back to 1.0.
4. **Orientation sensitivity (§1.5).** The segmenter behaves differently on the same photo
   rotated. F20's telemetry will show whether it is still biting after F18; if it is, the
   answer is the same as (2).

---

## 6. Plan rating: 9/10

**Pros.** The diagnosis is reproduced, not argued. The failure was replayed offline against
the real exported models on the real photos, the wrong detections were rendered and looked
at, and the fix was validated end to end before a line of C++ was proposed — all three
photos go from two rejections and one +45% number to three predictions within ±15%. The two
halves of the round are established by independent methods that agree: the scale mismatch
from a detection sweep, the calibration error from the regressor's own training CSV *and*
from a prediction sweep. The round is explicit that rounds 2 and 3 were correct fixes at the
wrong layer, and reverts nothing they shipped. Every constant it introduces goes in the
manifest with the measurement that produced it, and the harness that produced them is checked
in, so round 5 does not need a device to make progress.

**Cons.** Three photos, one animal type, one photographer, one phone — `input_cm_per_px` and
`cm_per_px_target` are both fitted to that, and the 118 kg photo already shows the ladder is
papering over genuine model brittleness rather than removing it. F21 knowingly conflates the
scale error with the missing cutter because three samples cannot separate them, which means
the number is right for today's build and wrong for the build after the cutter lands. F19
costs up to four extra YOLO passes on hard photos, on a phone. §1.5 is not fully reconstructed
— the rotated 96 kg path predicts 172.6 kg where the app reported 139.3 kg, so something
about that run is still unexplained, and F24 is an admission that the replication is not
byte-exact. And the honest framing of this round's own result is that it makes the weight
branch *usable*, not *accurate*: the real repair is a segmenter that tolerates scale and a
cutter that exists, and neither is in scope here.
