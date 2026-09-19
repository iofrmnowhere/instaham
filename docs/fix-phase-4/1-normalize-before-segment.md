# Phase 1 — Host-side normalize-before-segment path, behind a manifest switch

Status: done 2026-09-18 — **superseded 2026-09-19 by [`1.1-readme-is-the-path.md`](1.1-readme-is-the-path.md)**

**Superseded, not repeated.** The composition arithmetic this phase built
(`decide_normalize_first_composition()` in `stages/canvas_scale.h`, the block at
`stages/segmentation.cpp:79-114`, the rotation pair and the inverse transforms) is correct and
stays. Three structural choices recorded below are withdrawn under the user's 2026-09-19
brute-force instruction and are undone by phase 1.1: the manifest mode switch defaulting to the
old path, the retained retry ladder, and the F61 oversize fallback that stands where README §6
requires a halt. Read this file for what was built; read phase 1.1 for what ships.

Parent: [`../fix-4.md`](../fix-4.md). Authority for the intended behaviour:
[`INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md`](../../INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md)
sections 2 to 8 and 13. Authority for what in it had to change:
[`../scaling-rotation-readme-analysis.md`](../scaling-rotation-readme-analysis.md).

## Symptom

The segmenter is handed the capture composed at 1.1 cm/px; no code path exists that hands it
the photograph resized to `cm_per_px_target`. The change cannot be measured because it cannot
be run.

## Root cause

F60, stated in the parent document. This phase does not diagnose; it builds the alternative so
phase 2 can measure it.

## Change made

*(As built on 2026-09-18. The switch, the ladder and the fallback described here are withdrawn
by phase 1.1; the six numbered steps are not.)*

Add a second composition path to `stages/segmentation.cpp`, selected by a new manifest field
(proposed `capabilities.segmentation.input_scale.mode`, values `canvas_scale` for today's
behaviour and `normalize_first` for the new one), defaulting to `canvas_scale` so the shipped
behaviour is unchanged until phase 2 says otherwise.

The new path, in order:

1. Resize the decoded RGB uniformly by `resize_factor = cm_per_px_actual / cm_per_px_target`,
   both axes by the same factor, `INTER_AREA` when the factor is below 1 and `INTER_LINEAR`
   otherwise. This normalized image is the authoritative coordinate space for everything
   downstream.
2. If `normalizedHeight > normalizedWidth`, rotate 90 degrees clockwise and record
   `was_rotated_clockwise = true`. No dynamic head-direction inference (README §4).
3. Centre the rotated image, unresized, on a 960x540 canvas filled with (114, 114, 114).
   Record `x_offset`, `y_offset`, `rotated_width`, `rotated_height`.
4. Run the segmenter on the canvas at `imgsz = 640`, letting it letterbox internally.
5. Crop the returned mask back to `[y_offset, y_offset + rotated_height) x [x_offset, x_offset
   + rotated_width)`.
6. If `was_rotated_clockwise`, rotate the mask 90 degrees counterclockwise.

The result is the base mask in normalized 0.34 cm/px coordinates, the same shape as the
normalized RGB.

### The oversize fallback (F61)

README §6 asserts the normalized image always fits 960x540 and says to halt otherwise. F61
shows a 4032x3024 field capture normalizes to 764x573, which does not fit. Define the
behaviour instead of asserting:

- Enlarge the canvas to the smallest multiple-of-32 box that contains the normalized image
  while keeping the 16:9 proportion, and record the canvas size actually used. This preserves
  the physical scale, which is the requirement the README's invariant exists to protect, and
  gives up only exact frame-geometry parity with 960x540 — which phase 2 can then see in the
  numbers as a separate arm.
- Never shrink the normalized image to make it fit. That is the one thing the README is
  unambiguously right to forbid, and it would silently break `cm_per_px_target`.
- Record both the requested and the used canvas size in the envelope so an oversize capture is
  visible without a code read, the way `clamped_to_letterbox` already works.

### What does not change

The mask-to-training-space transform (`transform_mask_to_training_space`, round 7's F55) is
unchanged. On the new path `k` is 1.0 by construction, because the photograph was already
normalized, so the transform becomes a no-op rather than dead code — the same self-consistency
arm the scale sweep used. Quality gates keep their position before Ji-Duan. The cutter, the 16
`chen16_noheight` features, the feature order and the XGBoost model are untouched.

The retry ladder stays wired on both paths. On the new path its multipliers apply to the canvas
size decision, not to the pig's physical scale, which must remain exactly
`cm_per_px_target`.

## Verification

- `ML/host_scale_test/weight_branch_cli.cpp` can run either path on one image, selected by the
  manifest, and reports which path ran.
- Unit test alongside `test_segmentation_canvas.cpp`: the composition decision, the offsets, the
  crop bounds and the rotate/inverse-rotate pair are pure array math and must be testable
  without a model or a photograph, the way `canvas_scale.h` already is.
- Round-trip test: for a synthetic mask, crop-then-inverse-rotate returns exactly the input
  shape, and the mask is bit-identical after a rotate/inverse-rotate pair.
- Oversize test: a 4032x3024 capture at `cm_per_px_actual = 0.0644` produces the enlarged
  canvas, not a halt and not a shrunk image, and the envelope says so.
- `dart format` is not applicable (no Dart changes in this phase). `flutter analyze` is not
  applicable. Report the exact native build and ctest commands run, and confirm the binaries
  under test are newer than the sources before quoting any pass counts.

## Deferred

No app wiring, no APK, no device run. This phase ends at a host binary that can run both paths.
