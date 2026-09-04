# Phase 2 — Applied changes (F18–F23)

Status: done

Every item below was verified present in the working tree while writing this file, by
reading the named source, not by trusting `ref_fix.md`. Nothing from rounds 2 or 3 was
reverted; both were correct fixes at the wrong layer, and they now guard a stage that is
finally fed a usable input.

## F20 — persist the telemetry (done first, deliberately)

`run_and_persist_pipeline_use_case.dart` now `jsonEncode`s the **whole**
`envelope["segmentation"]` and `envelope["construction"]` blocks into their pipeline events,
the way F4 already did for `scale` and F6 for `features`. Previously the segmentation event
carried only `pig_count=… confidence=…` and construction was never persisted at all, which
is why round 3 had to be judged from three sentences of user-visible text.

This was shipped first and alone because it is what makes everything after it checkable
without a code read.

## F18 — scale-aware canvas composition

`stages/canvas_scale.h` (new) holds `decide_canvas_scale()`; `stages/segmentation.cpp` calls
it and uses `place_at_scale()` instead of `letterbox()` when it returns true. Composition is
at `content_scale = cm_per_px_actual / input_cm_per_px`, with
`segmentation.input_scale.cm_per_px = 1.10` in `assets/ml/manifest.json` — the measured
value, in the manifest rather than in C++, because it is a property of the exported
segmenter and must travel with it.

`construct_pig_mask()` needed **no change**: it already un-pads and rescales using the
carried `letterbox_scale` / `letterbox_pad_left` / `letterbox_pad_top`, so a mask found on
the new canvas maps back through the same code. F14 made that carried-parameter contract
honest and this reuses it rather than adding a second path, which is also why AGENTS.md
rules 6 and 9 stay satisfied.

Three guards, all failing closed:

- Content that would overflow the canvas falls back to the plain letterbox and sets
  `clamped_to_letterbox` — never clipped, never distorted, never silent.
- No `cm_per_px` available (health-only route, or no reference marked) keeps the existing
  full-frame letterbox.
- A `cm_per_px` is never invented.

`decide_canvas_scale()` is header-only and free of OpenCV and ORT, so
`test_segmentation_canvas.cpp` exercises it without a model or a photo.

## F19 — the retry ladder

`pipeline.cpp` walks `segmentation.input_scale.ladder_multipliers` = `[1.0, 1.32, 1.68,
0.77]`, then repeats the whole ladder at `retry_conf_threshold` = 0.10, stopping at the
**first** rung whose constructed mask reaches `min_mask_diagonal_fraction`. "Largest mask
across rungs" was rejected as a new selection criterion with its own failure modes and no
evidence behind it.

Measured on the three photos: 92 kg picks rung 1 (conf 0.91), 96 kg rung 1 (conf 0.91),
118 kg rung 2 (conf 0.28). Worst case is up to eight passes on a photo that would otherwise
be rejected outright; the common case is one, since the ladder is only entered once the
first mask is already known to be unusable.

Every attempt is recorded in `envelope["segmentation"]["rungs_tried"]` with its multiplier,
`conf_threshold_used`, `input_cm_per_px_used`, `content_scale`, `clamped_to_letterbox` and
outcome, alongside the selected `ladder_rung`.

## F21 — recalibrated `cm_per_px_target`

`assets/ml/manifest.json` now carries `cm_per_px_target = 0.35` (was 0.26),
`cm_per_px_target_uncertainty = 1.30` (was 1.15), and
`cm_per_px_target_source = "three_sample_field_estimate_pending_1p88m_calibration_capture"`,
replacing the previous `UNCALIBRATED_…` label. Derivation in
[1-diagnosis.md](1-diagnosis.md). This was kept on its own commit so the calibration change
can be reverted independently of the segmentation fix.

The uncertainty widens the size features' domain bounds by `uncertainty²` for the area ratio
`RA` and `uncertainty¹` for the lengths, leaving the scale-invariant `E` untouched, so the
gate is never stricter than the calibration it rests on.

## F22 — say when the answer is a clamp

After the F3 domain gate passes, `pipeline.cpp` re-checks each size feature against its
**unwidened** trained `[min, max]` — the raw CSV bounds, before `upper_multiplier` and the
uncertainty widening — and sets `envelope["weight"]["extrapolated"]` with
`extrapolated_features` listing which. The prediction is kept, not withheld.

This names a real tension rather than resolving it: F8's `upper_multiplier` of 1.35 on `LC`
and `BL` exists to admit uncut masks, and every vector it admits above the trained max is
one the regressor can only answer from its top leaf. The multipliers keep the branch usable
while the cutter is missing; they buy that availability with silent saturation, and the user
is entitled to know which they got. No Drift schema change — it folds into the existing
free-text note column.

## F23 — `min_mask_diagonal_fraction` raised to 0.35

Measured across all three photos: a correct whole-pig mask has a bbox diagonal of
**0.62–0.74** of the frame diagonal, and every wrong mask measured **0.06–0.15**. The old
threshold of 0.15 sat exactly on the wrong edge of that gap — the 118 kg junk mask measured
0.149 and only just failed to slip through. Still manifest-tunable, and it is what each of
F19's rungs is tested against.

## Not in scope, then or now

1. **The cutter.** Still an identity stub, owned by another team member. F21 partially
   absorbs its bias, which is a compromise, not a fix.
2. **Retraining or re-exporting the segmenter.** F18 and F19 work around a model that only
   detects pigs in a narrow apparent-size band. Scale jitter in training, or a larger
   `imgsz` export, is the real repair. Phase 1's detection sweep is a complete, reproducible
   bug report to hand to whoever owns `ML/segmentation/`.
3. **The 1.88 m calibration capture.** Several deliberate captures at a measured 1.88 m,
   median of the resulting `cm_per_px`, is the only thing that lets
   `cm_per_px_target_uncertainty` go back to 1.0.
