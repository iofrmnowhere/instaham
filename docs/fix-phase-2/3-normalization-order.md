# Phase 3 — Normalization order: resize the image, not the mask

> **Superseded 2026-09-10 by `docs/fix-3.md` (round 7).** Never started. F48 describes
> the same defect round 7 fixes at its source; working both would produce two competing
> changes to the same code path.

Status: not started — blocked on phases 1 and 2

## Symptom

`docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` specifies that physical scale normalization is a
uniform resize of the **whole photograph, before segmentation**. The shipped pipeline segments
at native capture resolution and then resamples only the **binary mask**, after the fact.

No user-visible defect is attributed to this yet. It is recorded because it is a divergence
from a written specification that nothing in the codebase currently follows, and because it
changes the geometry of eight of the sixteen features.

**Since this was written, phase 2.1 attached a measured behaviour to the same mechanic.** F53
(`docs/fix-phase-2/2.1-reference-length-sensitivity.md`) records the predicted weight moving
5.2% on one photo from reference marking alone, and identifies the `lround` + `INTER_NEAREST`
resample as one of its three terms — the term F48 below describes from the conformance side.
Adopting the specification's order removes that term outright, since no separate mask resample
would remain to quantize.

It does **not** remove F53's first term: under the specification's order the user's reference
length still sets how large the photograph is when the segmenter sees it, so a one-pixel
marking change can still yield a different mask. This phase must not be presented as the fix
for F53 on its own. Consume 2.1's attribution measurement before deciding — it says how much
of the 5.2% swing this phase would actually remove.

## Root cause

### F48 — the specification's order and the implementation's order differ

The specification's section 5 gives the processing order: load the photograph, measure the
reference, compute `scale_factor`, **resize the full image uniformly**, transform any existing
coordinates by the same factor, and only then run segmentation, the gates, the cut and the
16-feature extraction. Section 16 repeats it as the preferred implementation and warns against
mixing measurements taken at different resolutions. Section 6 separately warns that YOLO's
640×640 letterbox is not a substitute for physical normalization.

The implementation runs `run_segmentation` on the image at its original size
(`pipeline.cpp:345`), reconstructs the mask back to `seg.orig_w × seg.orig_h`
(`construction.cpp:99`), and then calls `scale_mask_to_training_space`
(`construction.cpp:129`), which resamples the mask alone with `cv::INTER_NEAREST`.

Two consequences follow, and they pull in opposite directions:

1. **Against the current order.** Nearest-neighbour resampling of a binary mask moves the
   boundary by up to half a pixel per edge and quantises it to the new grid. Area survives that
   reasonably well; perimeter, `outline_curve`, `body_curve` and the seven Hu moments are
   boundary statistics and do not. Eight of the sixteen `chen16_noheight` features are
   boundary-derived. The specification's section 17 makes the related point that linear
   quantities scale with `s` and area with `s²`, which is why it wants one consistent
   coordinate system rather than a late correction.
2. **For the current order.** Resizing the photograph before segmentation changes what YOLO
   sees, and the segmenter has its own separate scale contract —
   `segmentation.input_scale.cm_per_px: 1.1` with a retry ladder — that was tuned in round 4
   (F18/F19) and is confirmed working on device. The specification's own section 22 states that
   normalization "must not change the already accepted behavior of YOLO segmentation". Taken
   literally, the two requirements are in tension: normalizing before segmentation is exactly
   what changes the segmenter's input.

Resolving that tension is the substance of this phase. It is not obvious that the specification
is right and the implementation wrong; it is obvious that the two disagree and that nobody has
written down which one governs.

### F49 — the specification is not referenced anywhere in the project

`304`, `TARGET_PPM`, `observed_ppm` and `pixels_per_meter` appear nowhere in `packages/`,
`lib/`, `ML/` or `assets/`. No document under `docs/` links to
`INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` — not `docs/spec.md`, not `docs/plan.md`, not
`docs/architecture.md`, not any ADR. There is no record of the file being read, adopted,
rejected, or superseded.

That is the more actionable half of this phase. A specification that no code cites and no ADR
answers will keep resurfacing as a surprise, as it did here.

## Change made

Nothing. Reordering the pipeline would invalidate round 4's segmentation tuning and every
field measurement taken since, so it must not happen before phase 2's constant is settled.

## Steps

- [ ] **F49 — decide the specification's standing, and record the decision.** **Reopened
      2026-09-19.** It was marked closed on 2026-09-18 by `fix-4.md` phase 2 as "measured,
      reject, supersede it." The user overruled that verdict: phase 2 was a gate this project's
      own plan invented, and it was not entitled to discard
      `INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md`, which the user had
      designated as the basis for the work. **Nothing is superseded.** The answer to this item
      is now the README's order — normalize the photograph to `cm_per_px_target` before
      segmentation — settled by instruction rather than by measurement, and implemented by
      `fix-4.md` phases 1.1 and 4.
      The phase 2 numbers stand as observations and are a recorded counter-indication on corpus
      B; see [`../fix-phase-4-2-results.md`](../fix-phase-4-2-results.md). This item closes when
      the app actually runs that order, not before. Of the three honest options it named, the
      outcome is **adopt it.**
- [ ] **F48 — quantify the resampling cost before reordering anything.** Take the post-cut
      field masks, compute the sixteen features once from a mask resampled by `k` and once from
      a mask segmented at the normalized resolution, and compare feature by feature. If the
      boundary features move by less than the model's 4.56 kg MAE, the current order is
      defensible and only needs documenting. This is measurable off-device against
      `ML/weight_prediction/fixed_test_predictions_POSTHOC.csv` and does not need a rebuild.
- [ ] **F48 — if reordering is adopted, transform the reference endpoints too.** The
      specification's section 15 requires every existing coordinate to move by the same factor.
      The reference endpoints are persisted in original-image coordinates by
      `reference_marking_screen.dart`, and AGENTS.md rule 6 forbids resizing after the user
      marks them unless the coordinates are transformed exactly.
- [ ] **F48 — re-tune or re-verify the segmenter's scale ladder if the image is resized before
      segmentation.** `segmentation.input_scale.cm_per_px: 1.1` and its ladder multipliers were
      fitted against native-resolution input. Reordering invalidates that fit, and round 4's
      F18/F19 exist because getting it wrong means the segmenter does not detect a pig at all.
- [ ] Flag an ADR once the standing is decided — this is an architectural decision about stage
      order, which is `pipeline-docs`' file to write, not this skill's.

## Verification

- The specification's standing is written down somewhere a future session will find it, with
  the reasoning, whichever way it goes.
- If the order is left as it is, the boundary-feature cost of nearest-neighbour mask
  resampling is measured and stated rather than assumed to be negligible.
- If the order is changed, segmentation detection is re-verified on all three field photos
  before any weight number from the new order is trusted.
