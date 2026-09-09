# Phase 4 — Analysis, reporting, and what invalidates the result

Status: not started

## Goal

Turn `out/results.csv` into a stated conclusion about `cm_per_px_target`, written into
`docs/fix-phase-2/2-scale-target-conflict.md` alongside the round 2 and round 3 device data,
and say plainly what the result does and does not license.

## What the comparison is

For each constant, over the five images: signed `error_pct` per image, the mean of the signed
errors (the bias term), and the mean of the absolute errors (the accuracy term). Report both
— rounds 2 and 3 turned on the distinction, where 0.35 read uniformly low at −5.4%, −9.7%,
−9.6% while 0.3289 read high and scattered at +6.45%, +4.24%, +15.83%. A systematic bias is
a different problem from a scattered one, and averaging absolute errors alone hides which
one this is.

Report per-image rows, not just aggregates. Five points is small enough that one image
driving the mean must be visible.

## The prior this test is checking

Rounds 2 and 3 measured, on three field photos with a hand-marked reference:

| photo | true kg | 0.35 median (error) | 0.3289 median (error) |
|---|---|---|---|
| 92 kg meter stick | 92 | 87.07 (−5.4%) | 97.93 (+6.45%) |
| 96 kg porac stick | 96 | 86.66 (−9.7%) | 100.07 (+4.24%) |
| 118 kg porac stick | 118 | 106.72 (−9.6%) | 136.65 (+15.83%) |

0.35 was closer on two of three, including the worst case. The hypothesis this phase tests is
whether that ranking survives when the hand-marking jitter (5.18%, 12.04%, 12.55% bands) is
removed and the images come from the regressor's own acquisition geometry.

Three outcomes and what each means:

- **0.35 wins again.** Two independent methods agree. The revert deferred at the end of the
  last session becomes the obvious call, and `docs/fix-phase-2/2-scale-target-conflict.md`'s
  "it should be reverted to 0.35" line can be closed rather than left open.
- **0.3289 wins here.** The two methods disagree, and the difference between them is the
  interesting object: field photos with a marked reference versus training-geometry images.
  That points at the reference-marking path, not at the constant. Do not resolve this by
  picking the winner of the larger sample — write it up as a conflict and open a new
  numbered subphase for it.
- **Both read badly in the same direction on all five.** The constant is not the live term.
  This is the outcome `docs/pipeline/prediction-2.md`'s thesis predicts — that the constant
  must not be fitted at all — and it redirects effort to phase 2.1's cutter work rather than
  to any value of `cm_per_px_target`.

## Secondary reads worth extracting

- **`kept_fraction` across the two arms.** Phase 2.1 found a step discontinuity where a 0.04%
  change in mask area moved the regressor 5.84 kg. If `kept_fraction` jumps between arms on
  any image, that image's weight difference is a cutter artefact, not a scale effect, and
  must be labelled as such.
- **Whether `cutter_status` differs between arms.** A constant that changes whether the head
  is removed at all is a larger finding than one that shifts kilograms.
- **`Hu_3` through `Hu_7`.** Carried forward across sessions as unstable with no fix candidate
  targeting them. Five clean images with known weights is the first chance to see their
  spread on in-distribution input. Report their per-image values even though nothing acts on
  them yet.
- **Domain gate verdicts.** If either arm trips the gate on any image, quote it — the app
  would have withheld that weight, and a comparison of numbers the app would never show is a
  different claim from a comparison of numbers it would.

## What would invalidate this test

State each of these in the write-up if it applies. They are not hypotheticals; several are
live.

1. **`cm_per_px_actual` was tuned.** `0.3114504` is derived from
   `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`'s 304 px/m at 1.88 m and the images' stated
   1.78 m. If the implementer adjusted it to make results look better, the test measures
   nothing. It is an input, not a parameter.
2. **The 1.78 m figure is unverified.** It comes from the user's description of the folder,
   not from a document in the repository. Everything downstream scales with it: a 5% error in
   the height is a 5% error in `cm_per_px_actual` and therefore in `k`. Say so.
3. **The images are training data.** These are PIGRGB images and the regressor was trained on
   PIGRGB. Good agreement is partly memorization, so a small error here does not predict the
   same error on a field photo. This test ranks two constants; it does not validate the
   model.
4. **The canvas mode may not be the app's.** If phase 2 fell back to plain letterbox because
   scale-aware composition failed to detect at 960x540, the harness measured the constant
   under a canvas mode the app would not have used. The ranking still holds — nothing
   upstream of the resample reads `cm_per_px_target` — but the absolute kilograms do not
   transfer to the device.
5. **ONNX Runtime version differs from the device.** Host 1.29.0 against whatever
   `third_party/onnxruntime/lib/android/arm64-v8a/libonnxruntime.so` carries. Same graphs,
   not bit-identical. State the host version.
6. **The 1.780 m implied camera height is not evidence.** At the 0.3289 arm,
   `implied_camera_height_m` lands at 1.780 m against the images' actual 1.78 m. This is the
   geometry chain being self-consistent — 0.3289 and `cm_per_px_actual` both descend from the
   same 304 px/m figure — and it will look like a striking confirmation to anyone reading the
   envelope without this note. It says nothing about predicted weight. If it appears in the
   write-up at all, it appears with this caveat attached.
7. **Five images.** Not a calibration set. The output is a direction.

## Steps

- [ ] Compute per-image and aggregate errors for both arms from `out/results.csv`.
- [ ] Write the comparison into `docs/fix-phase-2/2-scale-target-conflict.md` as a new
      section, following the shape of its existing "What the 0.3289 sweep shows" section, and
      update that file's `Status:` line.
- [ ] Update the F-numbering. The last handoff records F-numbering continuing at **F54**;
      open the next free number for this host measurement rather than reusing F46, which was
      the device sweep.
- [ ] Answer, in that file, the revert question the last session left open: whether
      `cm_per_px_target` goes back to 0.35. If the answer is yes, the mechanics are in
      `docs/handoff.md`'s "Next steps" — `ML/export/export_xgboost.py` around line 289,
      re-export with `--enable-for-testing`, rebuild the manifest with `--allow-key-removal`,
      restore the `_source` tag, re-run `spec-drift`.
- [ ] Note whether F38 is retracted or stands. Its post-cut `RA` table implied targets near
      0.35 (0.347, 0.361); this test either supports or contradicts it, and the question has
      been left open across two sessions.
- [ ] If a genuine architectural decision comes out of this — for instance that the constant
      must not be fitted at all — flag that an ADR is owed. Do not write it here; that is
      `pipeline-docs`' job, and ADR-005's replacement is already owed from round 5.

## Deferred, not part of this phase

- The ground-truth-mask arm described in `docs/test-plan.md` open question 3. If
  `Instaham/PIGRGB-Weight/MASK_3394/` turns out to contain masks for these five images, an
  arm that feeds the mask directly would separate segmentation error from scale error. Worth
  doing, but it is a second experiment and belongs in its own phase.
- The live-camera path remains entirely unmeasured. All device data across rounds 2 and 3 is
  the gallery-import path at 2250x3000, and this host test does not touch the camera path
  either. Carry that forward unchanged.
- Removing the temporary `INSTAHAM_ENVELOPE` dump in
  `lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`.
  It is marked TEMPORARY and is owed once no further device sweeps are planned. This host
  harness may well be what makes further device sweeps unnecessary, so revisit it after this
  phase closes — but do not remove it as part of this phase.

## Closing out

When this phase completes, the test plan is done. Per the planner contract, append one line
to `docs/changelog.md`:

```
- YYYY-MM-DD [plan] host replication harness settles cm_per_px_target 0.35 vs 0.3289 on five PIGRGB images
```

`ML/host_scale_test/` is a keeper, not scratch — it is the reusable instrument this round
was missing, and the next constant or cutter change should be swept with it rather than with
another 18-scan sideload cycle. Leave it in the tree with its `README.md`. Only the patched
`assets/ml/manifest.test_*.json` copies are temporary.
