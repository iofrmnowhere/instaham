# Fix: reference-object scale never reaches the segmenter, and the regressor answers from its ceiling

Active fix document. Source material, all at the repository root and left there:
`instruction.md` (the original reference-object request, pre-round-4), `ref_log.md` (device
scan log for the three `.pig_pictures/` photos), `ref_fix.md` (the round-4 write-up,
F18–F24). Rounds 2 (F6–F11), 3 (F12–F17) and 4 (F18–F23) are all applied and in the working
tree. Numbering continues at **F25** — never reuse F1–F24, or the source comments citing them
start pointing at the wrong thing.

## Symptom

Three field photos with a marked reference object, all of pigs whose true weights are known
(92 kg, 118 kg, 96 kg). Before round 4: two were rejected outright and the third predicted
141.1 kg for a 96 kg animal. The rejection messages named the reference object, which was
correctly marked in every case — `cm_per_px` came out at 0.0633–0.0653 on all three, a
spread of under 3%.

After round 4 the measured harness result is three predictions within ±15% (−2.1%, −8.7%,
+14.9%), but **that number has not been confirmed on device**. What is left is verification
and tweaking, plus one unexplained discrepancy the harness turned up.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Diagnosis | done | [fix-phase/1-diagnosis.md](fix-phase/1-diagnosis.md) |
| 2 | Applied changes (F18–F23) | done | [fix-phase/2-applied-changes.md](fix-phase/2-applied-changes.md) |
| 3 | Open verification and tweaking | in progress | [fix-phase/3-open-verification.md](fix-phase/3-open-verification.md) |

Read only the phase relevant to the current work. Phase 3 is where all remaining work lives;
phases 1 and 2 are the record of what was already established and shipped.

## Root cause

Two independent defects, stacked, each of which hides the other:

1. **The segmenter was run at an input scale at which it does not detect a pig.** The whole
   frame was letterboxed into 640×640, leaving the animal ~220×400 px, and the model returns
   confident detections of ears, feet and flip-flops instead. Not a marginal miss: across all
   8400 anchors on all three photos, every box larger than roughly 100×100 px carried a class
   score of 0.000, so lowering the confidence threshold could not have recovered it.
   `scale_mask_to_training_space` corrects the *measurement* space after segmentation and does
   nothing for the *detection* space.
2. **`cm_per_px_target` was about 35% too small**, so even a correct mask produced a feature
   vector above the regressor's trained maximum. A gradient-boosted tree ensemble cannot
   extrapolate; every such vector is answered from the top leaf, measured at ≈182 kg with a
   floor at ≈83.5 kg. Fixing only the mask converts two rejections and one inflated number
   into three ceiling values.

Full derivation, with the measurements behind each claim, in phase 1.

## Change made

F18 scale-aware canvas composition, F19 the retry ladder, F20 segmentation/construction
telemetry persisted to Drift, F21 recalibrated `cm_per_px_target`, F22 the `extrapolated`
flag, F23 `min_mask_diagonal_fraction` raised to 0.35. All present in the working tree and
verified against source in phase 2. Rounds 2 and 3 were correct fixes at the wrong layer;
nothing they shipped was reverted.

## Verification

Not complete. Phase 3 carries the outstanding items:

- The device run against all three `.pig_pictures/` photos, against round 4's stated
  acceptance and non-acceptance criteria.
- **F24**, still open: the harness reports `RA` = 0.00728 on the 118 kg photo where the app
  reported 0.00086 — a factor of 8.5 on a mask whose `BL`, `BW`, `LC` and `E` all agree
  within 5%. F20's telemetry now makes this a log read rather than a guess.
- Orientation sensitivity (`ref_fix.md` §1.5), which F20's telemetry should now settle.
- `cm_per_px_target` must be retuned **downward** the moment the real cutter lands — F21
  knowingly absorbs part of the missing cutter's bias.

Two questions the device run has to answer: whether the harness result reproduces on device
at all, and whether `input_cm_per_px = 1.10` plus the ladder holds outside these three
photos — one animal type, one photographer, one phone.
