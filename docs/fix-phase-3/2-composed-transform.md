# Phase 2 — The composed 640 → calibrated transform

Status: done — 2026-09-10. `transform_mask_to_training_space` added to
`stages/construction.{h,cpp}`, `test_mask_transform` added and passing. Not yet called by
`pipeline.cpp` (phase 3). Two deviations from the plan below are recorded in Outcome.

## Symptom

`construction.cpp:97` and `pipeline.cpp:670` between them rasterize the mask twice. See
`docs/fix-3.md`'s Root cause for F55 in full; this phase builds the replacement, and phase 3
switches the pipeline over to it.

## Root cause

There is no function in the codebase that can map the 640×640 binary mask directly into the
training pixel space. `construct_pig_mask` ends in capture coordinates and
`scale_mask_to_training_space` starts from them, so the full-resolution intermediate is
structural rather than incidental — the only way to get from one to the other today is
through it.

## Change made

Add a new function to `stages/construction.{h,cpp}`, beside the existing two rather than
replacing either:

```cpp
PigMask transform_mask_to_training_space(const SegmentationOutput& seg,
                                         const cv::Mat& binary_640,
                                         double k);
```

**Leave `construct_pig_mask` untouched.** Its output is what gate B's IoU ≥ 0.95 parity check
against `ML/pipeline/construction.py` compares, and phase 3 keeps it as the gates' input. A
new function beside it is what preserves that test; editing it in place is what would break
it.

This requires `construct_pig_mask` to expose the 640×640 binary mask it currently builds and
discards at line 97. Return it on `PigMask`, or split the decode into a small helper both
functions call — the second is preferable, since it keeps the two consumers from sharing
mutable state, but either satisfies the phase.

### The transform

Compose the whole mapping into one operation. Per the corrected-pipeline document's section 5,
with F57's correction applied:

```
r    = seg.letterbox_scale        // NOT min(640/W, 640/H) — see fix-3.md, F57
padX = seg.letterbox_pad_left
padY = seg.letterbox_pad_top

x_final = (x_640 - padX) * (k / r)
y_final = (y_640 - padY) * (k / r)

finalWidth  = round(seg.orig_w * k)
finalHeight = round(seg.orig_h * k)
```

`letterbox_scale` holds whichever composition actually ran for this call — the plain
whole-frame letterbox, `place_at_scale` at the selected scale-ladder rung, or the clamped
fallback. It must be read, never recomputed. `SegmentationOutput` already carries all three
values verbatim for exactly this reason.

Implement as a single `warpAffine` with the composed matrix, rather than a crop followed by a
resize. A crop-then-resize is two operations again, and reintroduces a rounding step at the
crop boundary that the composed matrix does not have.

### Interpolation

Per the document's section 10, chosen against the source 640 mask, not against the capture:

- Shrinking (`finalWidth < 640 || finalHeight < 640`): `INTER_AREA`.
- Enlarging: `INTER_LINEAR`.

Then threshold back to binary at 127.5. Both interpolations produce intermediate grey values
from a 0/255 source, so the re-threshold is mandatory, not optional — every downstream stage
assumes a strictly binary mask, and `clean_binary_mask` and the cutter both behave
differently on a soft one.

### Guard clauses

Match `scale_mask_to_training_space`'s existing contract: return an empty `PigMask`, never an
unscaled copy, when `k` is not finite and strictly positive. There is no implicit `k = 1.0`
fallback (AGENTS.md rule 8). Return empty rather than crashing when the composed transform
would produce a zero or negative output dimension.

Populate `area_px` and the bbox fields the same way both existing functions do — the envelope
and `instaham_ml_segment_json` read them.

## Verification

- Unit test: for a synthetic `SegmentationOutput` with a known letterbox and `k = 1.0`,
  the composed transform and the existing two-step path agree to within a small IoU
  tolerance. They will not be identical — that is the point of the change — but a large
  disagreement at `k = 1.0` indicates a coordinate error rather than a resampling
  difference.
- Unit test: a `place_at_scale`-style `SegmentationOutput` where `letterbox_scale` differs
  from `min(640/W, 640/H)` produces the correct `finalWidth`/`finalHeight`. This is the test
  that would catch F57 regressing.
- Unit test: non-finite, zero and negative `k` all return an empty `PigMask`.
- The output mask contains only 0 and 255.
- Host CLI rebuilds clean, all targets, zero warnings.

## Exit condition — met

The function exists, is tested (`test_mask_transform`, 6 cases), and is not called by
`pipeline.cpp`. Phase 3 does the switch.

## Outcome

### Deviation 1 — signature: no `binary_640` parameter

Implemented as `transform_mask_to_training_space(const SegmentationOutput& seg, double k)`,
not the planned `(seg, const cv::Mat& binary_640, k)`. `pipeline.cpp` includes no OpenCV
today and the stage boundary keeps it that way (construction.cpp owns all OpenCV array math);
taking a `cv::Mat` parameter would force `<opencv2/core.hpp>` into `pipeline.cpp`. Instead the
function decodes the 640 mask itself through a new file-static helper `decode_binary_640`,
which `construct_pig_mask` now also calls — so both branches decode through identical code and
cannot diverge, which was the plan's stated goal for the shared helper anyway. The cost is
one extra prototype decode per weight prediction (a 160×160×32 dot product plus a 640×640
resize, ~milliseconds). **Phase 3 is simpler as a result**: it passes the already-selected
`seg_output` and `k`, with no `cv::Mat` to carry out of the scale-ladder loop.

### Deviation 2 — not `warpAffine`

The plan called for a single `warpAffine` with the composed matrix. `cv::warpAffine` does not
support `INTER_AREA`, which section 10 of the corrected-pipeline document requires for the
shrink case. Since the transform is pure scale + integer translation (letterbox pads are
`int`), it is implemented as an exact integer crop (`binary_640(rect)`, a view — not a
resample) followed by one `cv::resize` with `INTER_AREA`/`INTER_LINEAR`. This is still "ONE
composed transform … ONE geometric resampling operation" (document sections 4, 16): the crop
does no resampling, so exactly one rasterization occurs. `x_final = (x_640 - padX) · (k/r)`
holds exactly — the crop subtracts `padX`, and resizing the `(orig_w·r)`-wide crop to
`(orig_w·k)` applies `k/r`. `r` is `seg.letterbox_scale`, read via `letterbox_content_rect`,
never recomputed (F57).

### Refactor of `construct_pig_mask`

Its decode-and-threshold body moved into `decode_binary_640`; its letterbox-rect math into
`letterbox_content_rect`; its bbox/area loop into `fill_bbox_area`. Behavior is byte-identical
— verified by running the full host pipeline (`weight_branch_cli`) on
`133.42kg_5.png`: `predicted_kg`, `mask_area_px` (103267), `scaled_w/h` (854×481) and
`kept_fraction` (0.8133088460361187) all match the pre-change values exactly.

### Pre-existing failure noticed, not caused

`test_scale_normalization` fails at its `k = 2.0` length-doubling assertion
(`doubled->lc ≈ base->lc·2` within 3%). **This fails on pristine `construction.cpp` too** —
confirmed by reverting and rebuilding — so it is not a phase 2 regression. It is a fragile
ellipse-fit tolerance on a synthetic resampled disc, and `scale_mask_to_training_space`'s body
was not touched this phase. Flagged for phase 4 / a separate fix; not this round's scope.

### Validation run

- `test_mask_transform` — built clean (zero warnings), passes: guard clauses (k = 0, −1, NaN,
  +inf, `!has_detection` → empty), output dims `= round(orig·k)`, strict 0/255 output,
  blob-centroid geometry `(x_640 − padX)·(k/r)` with `r = letterbox_scale ≠ min(640/W,640/H)`,
  IoU ≥ 0.9 vs the old two-step path, degenerate-letterbox → empty.
- `weight_branch_cli` and `host_scale_smoke` (both compile `construction.cpp` in the real
  pipeline source set) — rebuilt clean, zero warnings.
- Other OpenCV-gated host tests unaffected: `test_cutter_identity`, `test_body_curve_dual_call`,
  `test_feature_domain`, `test_mask_selection`, `test_segmentation_canvas` all pass.
- `test_abi` / the full `instaham_ml` shared lib do not build in this host config (missing ORT
  headers — pre-existing; that is why `ML/host_scale_test` exists as a separate build).
