# Phase 3 — Reconcile the frame and scale constants

Status: done 2026-09-19

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

## Result (2026-09-19)

Verified with the real host CLI (`weight_branch_cli.exe`, rebuilt against this phase's
changes) against corpus A (4 images) and corpus B (5 images) — the same 9 images phase 2
measured — and `ctest`: 8/9 pass, the same two pre-existing failures as before this phase
(`test_abi`, `test_scale_normalization`).

1. **`training_frame_px` (720x720): no change.** It is read only in the scale/height_ratio
   gate (`pipeline.cpp`), via `sqrt(w*h)`, an area term that is aspect-independent. It is
   **not** read by the mask-plausibility gate at all. F62's stated mechanism — that
   `training_frame_px` and `min_mask_diagonal_fraction` are "read together" to gate
   plausibility — does not hold in the current (post-1.1) code. Corrected in a
   `pipeline.cpp` comment rather than silently dropped.
2. **`min_mask_diagonal_fraction` (0.35): no change.** The gate's real denominator is
   `PigMask::width/height`, i.e. the normalize-first `content` rectangle (post-resize,
   pre-canvas-placement) — not the 960x540 canvas and not `training_frame_px`. Measured
   directly: `mask_diagonal_fraction` ranged 0.44–0.74 across all 9 corpus images, well
   above 0.35 and consistent with `ref_fix.md` F23's original 0.62–0.74 measurement. This is
   the Verification section's own "if none do, say so" outcome — no verdict changed.
   `mask_diagonal_fraction()` was pulled out of `pipeline.cpp`'s anonymous namespace into
   `stages/mask_geometry.h` so it is unit-testable; `test_segmentation_canvas.cpp` gained a
   regression checking a plausible (~0.62) and an implausible (~0.10) bbox against both the
   pre-README 720x720-aspect frame and the README's 960x540-aspect frame (same 518400 px
   area) — 0.35 sits outside both ranges on both shapes.
3. **Provenance added.** `canvas_scale.h`'s 960x540 now cites
   `INSTAHAM_CAMERA_SCALE_NORMALIZATION.md:29` (released PIGRGB `RGB_9579` frame size) as
   its source. **Flag (not a gate):** that same document says a normalized image "does not
   need to be exactly 960 x 540" (lines 287/685), while the README requires an exact fit and
   halts otherwise (section 6). This round ships the README's exact-fit reading; the
   divergence is unresolved.
4. **304 px/m standing note added** to the top of
   `INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`: superseded on the `cm_per_px_target` *value* by
   the round-28 sweep's 0.34 (`docs/scale-constant-sweep-results-2.md`, ADR-011/012), still
   authoritative on the underlying PIGRGB geometry (1.88 m camera height, 960x540 frame)
   that both 0.34 and the app's canvas derive from.
5. **`segmentation.input_scale.cm_per_px` renamed to `legacy_ladder_base_cm_per_px`**
   (`assets/ml/manifest.json`, `ML/export/export_yolo.py` — the actual exporter source of
   this fragment, not `export_xgboost.py` — `manifest.h`, `manifest.cpp`), so it can no
   longer be misread as the README path's scale (`weight.capture_contract.cm_per_px_target`).
   Value unchanged (1.10); the field is dead on the README path and lives on only for
   `pipeline.cpp`'s not-yet-removed retry ladder, which phase 4 deletes along with this
   whole `input_scale` block. **Flag:** `segmentation.model.sha256` and the shipped ONNX
   binary were deliberately not touched — re-running `export_yolo.py`'s ONNX export is
   non-deterministic (its self-check numbers and graph hash drift run to run against the
   same checkpoint), and re-staging a new binary for a JSON-key-only rename is outside this
   phase's scope. The renamed key's value was carried over from the exporter's own updated
   source by hand, not by a full re-export — a one-line deviation from "regenerated through
   the exporter, never hand-edited." Worth deciding whether phase 4's ladder removal should
   absorb this rename instead, alongside a real re-export.

6. **F61 retracted — found while checking this phase's own corpus runs.** Both pieces of
   evidence for "README §6 halts on ordinary captures" pair a capture size with a
   `cm_per_px_actual` measured at a different resolution, which is invalid because that value
   is centimetres per pixel *of the image it was measured on*.
   - Phase 1.1's smoke test gave `.pig_pictures/118kg_pig_porac_stick.jpg` (**3024x4032**) the
     0.0653 measured on `corpus_a/118kg_pig_porac_stick.jpg` (**2250x3000**). With that file's
     own scale (0.0486, from `131 cm / ~2695 px`) it fits: `oversize: false`, predicted
     125.49 kg against a true 118 kg.
   - The original adb-log derivation applied ~0.0644 to a hypothetical 4032x3024 frame. That
     same log's `height_ratio = 0.66431` at `cm_per_px_target = 0.35` inverts to
     `sqrt(w·h) = 0.66431 × 720 / 0.18410 = 2598.1`, and `sqrt(2250 × 3000) = 2598.1` exactly
     (`sqrt(3024 × 4032) = 3491.8`). The device was processing **2250x3000**, covering 145.0 cm
     on the short side and needing **426 of 540 px**.
   - All nine corpus images re-run this phase fit, using 418–432 px of 540.

   Restated physically: the invariant bounds ground coverage, not pixels — at most
   `960 × 0.34 = 326 cm` on the long side, `540 × 0.34 = 184 cm` on the short side. Halving an
   image's pixels doubles its `cm_per_px_actual`, so the product is unchanged and resolution
   cannot decide the fit. §6 halts a capture taken from too far back.
   Corrected in `fix-4.md` (Root cause + open flag + phase 1.1 row + plan rating Cons),
   `fix-phase-4/1.1-readme-is-the-path.md`, `fix-phase-4/1-normalize-before-segment.md`,
   `fix-phase-4/4-app-wiring.md` and `fix-phase-4/5-debug-and-assertions.md`. **Consequence:
   no §6 ruling is needed before phase 4**, and a halt appearing on device is now a signal —
   most likely a reference-mark coordinate-space mismatch (AGENTS.md rules 6 and 9), not a
   too-small canvas.

Files changed: `ML/export/export_yolo.py`, `assets/ml/manifest.json`,
`docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`, `packages/instaham_ml_ffi/src/manifest.h`,
`packages/instaham_ml_ffi/src/manifest.cpp`, `packages/instaham_ml_ffi/src/pipeline.cpp`,
`packages/instaham_ml_ffi/src/stages/canvas_scale.h`,
`packages/instaham_ml_ffi/src/stages/mask_geometry.h`,
`packages/instaham_ml_ffi/src/test/test_segmentation_canvas.cpp`.
