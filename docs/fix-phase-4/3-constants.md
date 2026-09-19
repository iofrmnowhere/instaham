# Phase 3 — Reconcile the frame and scale constants

Status: not started

Parent: [`../fix-4.md`](../fix-4.md). Unblocked 2026-09-19 — phase 2's gate is void and the
README is implemented by instruction. Work this after phase 1.1. The 960x540 canvas is not in
question here; only the constants that describe it are.

## Symptom

Three constants describe the same physical setup and disagree with each other, and one
repository-root README countermands a `docs/` authority in a single unsourced sentence.

## Root cause

**F62 — two training frames.** `capabilities.weight.capture_contract.training_frame_px` is
`[720, 720]`, read at `pipeline.cpp:508` together with `min_mask_diagonal_fraction = 0.35` to
gate mask plausibility. The README's frame is 960x540. Adopting the README without touching
`training_frame_px` leaves the plausibility gate measuring against a frame the pipeline no
longer uses, which changes which masks are rejected without anyone deciding that it should.

**F63 — the 304 px/m authority is countermanded, not superseded.**
[`INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`](../INSTAHAM_CAMERA_SCALE_NORMALIZATION.md) is the
standing authority for the 304 px/m (0.3289 cm/px) PIGRGB floor-plane baseline. README §1 and
§15 say not to use it, with no data pointer. The value the README wants is defensible —
[`scale-constant-sweep-results-2.md`](../scale-constant-sweep-results-2.md) measured 0.34 as the
MAE minimum on both corpora — but nothing records that the 304 px/m document is superseded on
this point, so the next session will find two live authorities.

## Change made

1. Decide what `training_frame_px` means on the new path and set it accordingly. If the
   normalized frame is the 960x540 canvas, the plausibility gate's denominator should be that
   canvas, and `min_mask_diagonal_fraction` needs re-deriving against it rather than carrying
   over a fraction fitted to 720x720. Do not change one without the other.
2. Record where 960x540 comes from, in the manifest's own provenance style: the released PIGRGB
   frame size (`INSTAHAM_CAMERA_SCALE_NORMALIZATION.md:29`) at 0.3289 cm/px, which is the reason
   the canvas is defensible at all. The README never states this and it is the strongest part of
   its case.
3. State the standing of the 304 px/m baseline document explicitly — superseded on the
   `cm_per_px_target` value by the round-28 sweep, still authoritative on the PIGRGB geometry
   the canvas size derives from. Both halves need saying; the sweep did not invalidate the
   geometry.
4. Settle `segmentation.input_scale.cm_per_px`. With phase 1.1 removing the `canvas_scale`
   path, the field's old meaning — the presentation scale — no longer exists, and the
   normalization target is the weight capability's `cm_per_px_target`. Either remove the
   segmentation field or rename it to what it actually does; do not leave two fields that could
   each plausibly be read as the scale. Whatever is decided, the manifest is regenerated through
   the exporter, never hand-edited.

## Verification

- `flutter analyze` and the manifest-parsing tests pass after any manifest change, and
  `manifest.cpp`'s required-field validation still rejects a manifest missing either constant.
- A targeted test covers the plausibility gate at the new frame size, showing which masks change
  verdict relative to 720x720. If none do, say so; that is a valid and useful result.
- No constant is changed without its provenance string changing with it. An unsourced constant
  is what produced F63 in the first place.

## Deferred

The ADR. This phase produces the constants and their provenance; `pipeline-docs` writes the
architectural decision record for the stage-order change, recording that it was settled by
instruction and that phase 2's measurement is a known counter-indication on corpus B.
