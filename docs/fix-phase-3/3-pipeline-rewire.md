# Phase 3 — Rewire the weight branch; keep the gate branch in capture coordinates

Status: done — 2026-09-10. `pipeline.cpp:670` and the host harness now call
`transform_mask_to_training_space`; the F58 no-reference cap path and the whole gate branch
are untouched. The composed transform is live end to end. Jitter numbers in Outcome — worst
case improved on all three corpora, per-image mixed; the full table and the on-device check
are phase 4.

## Symptom

Phase 2's transform exists but nothing calls it. `pipeline.cpp:670` still routes the weight
path through `scale_mask_to_training_space(pig_mask, k)`, which is the second of F55's two
rasterizations.

## Root cause

One mask currently serves two consumers with incompatible requirements. `pig_mask` — the
capture-coordinate output of `construct_pig_mask` — feeds both the quality gates, which need
capture coordinates and must keep them, and the cutter, which does not. Splitting the two
consumers is the whole of this phase.

## Change made

### Branch A — quality gates: no change

`pipeline.cpp:609-658` keeps reading `pig_mask` exactly as it does now. The posture and
truncation gates stay in original capture coordinates, stay in their current order
(truncation first, then posture), and stay ahead of the cutter. This is the corrected-pipeline
document's sections 8 and 9, and the current code already satisfies both — the risk here is
of changing it by accident, not of needing to change it.

The full-resolution raster at `construction.cpp:97` therefore stays alive. It is no longer on
the weight path, but it is still built for the gates, so this round does not reduce that cost.

Both gate flags ship `false` in the current manifest, so this branch is dark on device and its
preservation cannot be verified there. Note that in the phase 4 write-up rather than claiming
the gates were verified.

### Branch B — weight path: switch to the composed transform

Replace the `scale_mask_to_training_space(pig_mask, k)` call at `pipeline.cpp:670` with
phase 2's `transform_mask_to_training_space(seg_output, k)`. The failure handling around it is
unchanged: an empty result still sets `scale_ok = false` and
`scale_failure_reason = "scale_resample_failed"`, and still records that same reason on
`envelope["scale"]` rather than a generic one (ref_fix F1).

Phase 2's function takes only `(seg_output, k)` — it decodes the 640 mask internally through
the shared `decode_binary_640` helper (see phase 2 Outcome, deviation 1). `pipeline.cpp`
already carries the selected `seg_output` out of the scale-ladder loop (it is read at line
432), so **no `cv::Mat` needs to be carried out and `pipeline.cpp` stays OpenCV-free**. The
decode is pure — same `seg_output` in, same 640 mask out — so running it a second time here
cannot diverge from what the ladder selected.

### F58 — the no-reference fallback keeps the old path

**Do not delete `scale_mask_to_training_space`.** `pipeline.cpp:685` calls it with `cap_k`
when no reference was marked, to bound an unscaled mask to `kUnscaledCutterMaxDimPx` (2880)
before the cutter sees it (ref_fix F43). That path has no `k` and therefore no calibrated
target space to compose a transform into — it is a size cap, not a calibration.

Leave it exactly as it is. It is a debugging-visibility path, not the weight path: without a
reference there is no scale and no prediction is produced, so its resampling quality does not
affect any shipped number.

### Envelope

Add the composed transform's output dimensions and the `r`/`k` it used to
`envelope["construction"]`, in the spirit of F15/F18/F20 — a future scale bug in this
transform should be visible from the envelope without a code read, the same way mask selection
and canvas composition already are. This is diagnostics only and gates nothing.

## Files changed

- `packages/instaham_ml_ffi/src/pipeline.cpp` — line 670: `scale_mask_to_training_space(pig_mask, k)`
  → `transform_mask_to_training_space(seg_output, k)`. Failure handling
  (`scale_resample_failed` → `scale_ok = false`, same reason on `envelope["scale"]`)
  unchanged. Added `envelope["construction"]["composed_transform"]` = `{letterbox_scale, k,
  out_w, out_h, out_area_px}` on success — diagnostics only, gates nothing (F15/F18/F20
  spirit).
- `ML/host_scale_test/weight_branch_cli.cpp` — the mirrored step 6, same one-line swap, so
  `jitter_sweep.py` measures what the app runs. Added `envelope["composed_transform_used"]`.
- **`scale_mask_to_training_space` unchanged and still called** at `pipeline.cpp` (F43 cap
  path) and `weight_branch_cli.cpp` for the no-reference fallback (F58).
- Gate branch (`pipeline.cpp:609-660`) not touched.

## Verification

- **`pipeline.cpp` compiles clean** (zero warnings) in the host config.
- **`flutter analyze`** — 7 pre-existing issues (vendor `ffi` import infos, one generated
  `unused_field`), none from this change; no Dart touched.
- **Gate branch byte-identical.** `weight_branch_cli` on `133.42kg_5.png` reports
  `mask_w`/`mask_h` = 960×540 and `mask_area_px` = 103267 — identical to the pre-round-7
  value. `construct_pig_mask`'s output, which the gates read, did not move.
- **The two masks are distinct and correctly routed.** Same run: `mask_w`/`mask_h` (gate
  input) = 960×540, `scaled_w`/`scaled_h` (cutter input) = 854×481, `composed_transform_used`
  = true, `content_scale` = 0.283 (the scale-aware `place_at_scale` value, not
  `min(640/960, 640/540)` = 0.667 — so the transform read `letterbox_scale`, F57 holds live).
  A regression that fed the gates the scaled mask would show `mask_w` = 854; one that fed the
  cutter the capture-resolution mask would show `scaled_w` = 960.
- **`test_mask_transform`, `test_cutter_identity`, `test_body_curve_dual_call`,
  `test_feature_domain`, `test_mask_selection`, `test_segmentation_canvas`** all pass.
  `test_scale_normalization` fails at its `k = 2.0` assertion — pre-existing, unrelated (see
  phase 2 Outcome / `fix-3.md` open questions).
- **Host CLI end to end** on three PIGRGB images: predictions
  139.0 / 99.5 / 96.0 kg, `cut_applied`, `kept_fraction` 0.79–0.91. Was 142.2 / 98.8 / 96.8
  before — the composed transform gives a genuinely different (crisper, area-resampled)
  boundary, so feature vectors move a little; this is F55 working, not drift.
- No pipeline-level ctest exists (`test_pipeline_routing` is still stubbed out; a real one
  needs ORT + models, which this host config lacks — the same reason `test_abi` / the
  `instaham_ml` shared lib do not build here). The envelope invariant above is the
  swap-detection check in its place.

## Outcome — jitter measured off-device

`jitter_sweep.py`, same images and `--deltas` as the phase 1 / round 6 baselines:

| corpus | before | after (r7) | worst-case image |
|---|---|---|---|
| upscale 1280 (phase 1 primary) | 14.7% | **10.9%** | 133.42kg_5 |
| native 1.78 (960×540) | 11.9% | **10.3%** | 133.42kg_5 |
| native 1.88 (960×540) | 6.4% | **6.2%** | 87.3kg_2 |

Worst-case spread improved on all three. Per-image is **mixed** — at 1280, the worst image
went 14.7% → 10.9% but three of the other four rose a few points (100.9kg_3 2.4 → 6.6;
117.9kg_2 6.6 → 7.5; 125.38kg_4 3.5 → 5.0). Native 1.78 is similar (117.9kg_2 improved a lot,
8.6 → 3.8; two others rose).

This is not the clean win the mechanism predicted, and it echoes the mixed pattern that
sank round 6's `INTER_AREA` candidate — but with the crucial difference that there the worst
case got *worse* (11.9 → 14.4), and here it improves everywhere. The composed transform also
shifts the delta-0 prediction itself (crisper boundary → different features), so the harness
is measuring a partly different mask, not only a jitter change. Phase 4 records the full
per-image table and runs the on-device F53 re-mark, which the phase docs already name as the
real verdict — the off-device proxy cannot model the reference re-composing the segmentation
canvas, and cannot see whether the boundary change helps or hurts accuracy (ADR-010's floor
dominates that regardless).

## Exit condition — met

The weight path has exactly one rasterization between the 640 binary mask and the cutter (one
`cv::resize` inside `transform_mask_to_training_space`; the crop is a view). The gate path is
byte-identical (`mask_area_px` 103267 unchanged). The envelope invariant
(`mask_w` 960 vs `scaled_w` 854 vs `composed_transform_used`) is the check that fails if the
two are swapped.
