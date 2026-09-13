# Fix (round 7): the weight branch rasterizes the mask twice

Third active fix document, opened as **round 7**, and the project's main task from
2026-09-10. It implements
[`INSTAHAM_CORRECTED_SEGMENTATION_XGBOOST_PIPELINE.md`](../INSTAHAM_CORRECTED_SEGMENTATION_XGBOOST_PIPELINE.md)
(repository root), which is the authority for this round. Where this document and that one
disagree, the disagreement is recorded explicitly below rather than resolved silently.

Numbering continues at **F55**. F54 was never assigned to anything — `docs/handoff.md`
reserved it and no phase or source comment ever used it; it stays skipped rather than
reused, so existing citations keep pointing where they point.

This round **supersedes `docs/fix-2.md` phases 2.1 and 3.** Phase 2.1's remaining fix and
phase 3's F48 are both attempts at the same underlying defect this round fixes properly, and
working them separately would produce two competing changes to the same code path. Neither is
deleted; both are marked superseded in place, with their measurements retained because this
round is validated against them.

## Symptom

The predicted weight moves by up to 12.6% when the reference endpoints are re-marked by one
or two pixels — a scale change far too small to justify it. Measured on device across three
field photos (`docs/fix-phase-2/2.1-reference-length-sensitivity.md`, bands 5.18% / 12.04% /
12.55%) and reproduced off-device by `ML/host_scale_test/jitter_sweep.py` (worst case 11.9%
at 1.78 m).

The estimate is not merely noisy. It is unstable in a way the user can see and cannot act on,
because re-marking the same reference object twice produces two different weights.

## Root cause

**F55.** The binary mask is rasterized twice on its way to the feature extractor:

1. `construction.cpp:97` resizes the 640×640 binary mask to full capture resolution with
   `INTER_NEAREST`. On a phone photo that is roughly a 4.7× nearest-neighbour upscale, which
   converts a 640-pixel contour into large staircase blocks.
2. `pipeline.cpp:670` then resizes that result again by `k = cm_per_px_actual /
   cm_per_px_target` down to the training pixel space, typically 400–1000 px.

The second resize can only average the staircase the first one created; it cannot recover the
original contour. Because both resizes snap to a pixel grid whose alignment depends on `k`,
and `k` depends directly on the marked reference length, a one-pixel change in marking shifts
which source pixels land where. Perimeter, curvature, convex-hull difference and the Hu
moments all read that boundary, so the shift propagates into the feature vector and out
through XGBoost.

This also explains why `docs/fix-phase-2/2.1`'s candidate fix failed. Switching step 2 to
`INTER_AREA` smooths a staircase that step 1 had already produced, and measured *worse*
(11.9% to 14.4%). The interpolation choice was never the problem; the number of
rasterizations was.

## Change made

Replace the two-step raster with a single composed transform, straight from the 640×640
binary mask to the final calibrated mask, and keep a separate original-coordinate mask alive
solely to feed the posture and truncation gates. This is the corrected-pipeline document's
sections 4, 5 and 8.

Nothing about the model side moves. YOLO weights, `imgsz = 640`, the 160×160 prototype
decode, the crop-before-upsample order, the single 0.5 threshold, the Ji Duan cutter, the 16
`chen16_noheight` feature definitions and the XGBoost model are all unchanged, per that
document's section 14.

## One deliberate divergence from the corrected-pipeline document

**F57.** The document's section 5 gives the letterbox scale as `r = min(640 / W, 640 / H)`.
That is correct only for a plain whole-frame letterbox, and this app does not always use one.
When a reference object has been marked — the normal weight path — `run_segmentation`
composes the canvas through `place_at_scale` at `content_scale = cm_per_px_actual /
input_cm_per_px`, so the pig's apparent size in the model input reflects its real-world size
rather than the capture's pixel resolution (ref_fix F18). `input_cm_per_px` is further
multiplied by whichever scale-ladder rung actually produced a detection (F19), and the whole
thing falls back to a plain letterbox, setting `clamped_to_letterbox`, if the requested scale
would overflow 640×640.

Recomputing `min(640 / W, 640 / H)` after the fact therefore cannot reproduce the transform
that was actually applied. The implementation reads `SegmentationOutput::letterbox_scale`,
`letterbox_pad_left` and `letterbox_pad_top`, which already carry the values used, verbatim.
The document's coordinate math is otherwise correct and generalizes as soon as `r` is the
scale actually used.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Harness baseline: does resolution change the jitter band? | **done 2026-09-10** — F56; effect is real but non-monotonic (960: 11.9%, 1280: 14.7%, 3000: 10.8%). Validate phase 2 against the 1280 baseline. | [fix-phase-3/1-harness-baseline.md](fix-phase-3/1-harness-baseline.md) |
| 2 | The composed 640 to calibrated transform | **done 2026-09-10** — `transform_mask_to_training_space` added + `test_mask_transform` passing; not yet wired. Signature is `(seg, k)` not `(seg, binary_640, k)` — keeps `pipeline.cpp` OpenCV-free. | [fix-phase-3/2-composed-transform.md](fix-phase-3/2-composed-transform.md) |
| 3 | Rewire the weight branch; keep the gate branch in capture coordinates | **done 2026-09-10** — `pipeline.cpp` + host CLI swapped to the composed transform; gate branch byte-identical. Worst-case jitter 14.7% → 10.9% (1280), 11.9% → 10.3% (native); per-image mixed. | [fix-phase-3/3-pipeline-rewire.md](fix-phase-3/3-pipeline-rewire.md) |
| 3.1 | Host-side re-mark replay of the recorded 18 marks | **done 2026-09-10** — replayed `docs/logs/recorded.md` round 2's real marks off-device; validity gate (host `segArea`/`seg_conf`/rung vs device) passes on all three photos. Band 118 kg 12.55% → 7.04%, 96 kg 12.04% → 2.29% (partly a cutter-dropout the host missed), 92 kg 5.18% → 6.03% (flat — cutter still splits on a byte-identical mask). Mixed; does not close phase 4. | [fix-phase-3/3.1-host-remark-replay.md](fix-phase-3/3.1-host-remark-replay.md) |
| 4 | Validation: jitter, parity, and the on-device rebuild | in progress — off-device jitter done in phase 3; on-device F53 re-mark + full per-image table outstanding | [fix-phase-3/4-validation.md](fix-phase-3/4-validation.md) |

Work them in order. Phase 1 is a genuine dependency, not sequencing preference: the current
harness cannot measure the defect at the magnitude a real capture produces. Phase 1 ran and
found the resolution effect is **real but non-monotonic** — worst at ~1280 px (14.7% vs
11.9% native), lower at 3000 px, for reasons its write-up explains (both raster steps are
`INTER_NEAREST`, the second is a downscale whose ratio grows with resolution, plus an
upscaling blur confounder). Phase 2 is validated primarily against phase 1's 1280 baseline,
`ML/host_scale_test/out/jitter_sweep_hires1280.json`.

## Verification

Stated per phase. The round as a whole is verified when `jitter_sweep.py` reports a lower
worst-case spread than the phase 1 before-baseline `jitter_sweep_hires1280.json` (14.7%),
with the native `jitter_sweep{,_1.88}.json` (11.9% / 6.4%) as a secondary check, and the
gate-B IoU parity check against `ML/pipeline/construction.py` still passes at 0.95 or above.

A lower spread is necessary but not sufficient. The round does not claim to move accuracy —
ADR-010's ~73 kg training-domain floor is untouched by anything here and remains the largest
open error term.

## Open questions

- **The reference implementation may not rasterize the mask at all.**
  `.old_py_files/yolo_inference.py:11` declares `MASK_COORDINATE_PROTOCOL =
  "original_coordinate_polygon_v1"`, and `predict_largest_mask` rasterizes Ultralytics'
  `masks.xy` polygon contours with a single `fillPoly` at original resolution, treating the
  resize path (`_unletterbox_native_mask`, line 182) as an explicit fallback for when
  polygons are unavailable. `weight_runtime.py:27` hard-asserts that protocol. If those
  polygons produced the XGBoost training features, then a polygon transform — contour points
  transformed, one `fillPoly` at the destination — would be strictly more faithful than any
  resampling, including this round's. **Not verified**: Ultralytics is not installed in
  `.venv-export`, so `masks2segments` and `Masks.xy` could not be read. Recorded here and
  deliberately not acted on; the corrected-pipeline document is being implemented as written.
- **`docs/fix.md` phase 7 is still open and now seven sessions untouched**, which breaks the
  project's own sequential-phase rule with this round opening ahead of it. It needs to be
  closed or explicitly parked. Not this round's work, but it should not stay implicit.
- **The live-camera path remains entirely unmeasured**, unchanged across six rounds.
- **`test_scale_normalization` fails on `main` at its `k = 2.0` assertion** (found during
  phase 2, confirmed pre-existing on pristine `construction.cpp`). A fragile 3%
  ellipse-fit tolerance on a synthetic resampled disc; `scale_mask_to_training_space` itself
  is not implicated. Needs its own small fix — either loosen the tolerance or replace the
  assertion with a more direct length check. Not this round's scope.

## Plan rating: 8/10

**Pros.** The root cause is established by reading the shipped code rather than inferred, and
it explains a previously unexplained failed experiment, which is the strongest evidence
available short of the fix itself. The change is confined to app-side C++ with no retraining,
no asset change and no model change. The gate branch is left alone, so the one part of the
pipeline with a passing parity test keeps it. Every phase has a measurable exit condition
against baselines that already exist.

**Cons.** The polygon question above is unresolved and could make this round a partial fix
rather than the right one — it is cheap to settle and is being deliberately deferred. The
posture and truncation gates both ship disabled, so the branch this round carefully preserves
is untested on device and its preservation cannot be verified. The improvement is measured on
PIGRGB images, not on the three field photos where the 12.6% band was actually observed, and
phase 1 only narrows that gap rather than closing it. Finally, a lower jitter band does not
imply a better weight; the dominant error term is untouched and will still dominate.
