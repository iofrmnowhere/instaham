# Phase 1 — coordinate recovery and the masked crop

Status: done

## Result

Implemented as designed below. `bbox_padding_ratio`/`background_fill` were already present
in `assets/ml/manifest.json` under `capabilities.health.input` (0.06 / "imagenet_mean") but
unparsed; `manifest.{h,cpp}` now reads them into `ClassifierCapability`. `PigRegion`'s bbox is
divided by `SegmentationOutput::content_scale` in `pipeline.cpp` before being handed to
`health_input.cpp`, so the struct's own "ORIGINAL image coordinates" contract is now true; the
mask bitmap is resampled with `cv::resize(..., cv::INTER_NEAREST)`, matching
`stages::construction`'s own convention for every mask resample it performs.

The "small patch after resize" reconciliation (open question at the end of this file) turned
out to be moot: `resize_shorter_then_crop()` always upscales the shorter side to
`resize_shorter_side` (255) before cropping to 224, so its output is never smaller than the
crop in either implementation — the reference's zero-pad branch for that case is dead code
too, for the same reason. No change was needed.

`PigMask::pixels` is confirmed 0/255 (not 0/1 as `health_input.h` previously said); the header
comment is corrected and every comparison in the new code uses `> 0`, never `== 1`.

**Verification run:**
- `ninja` (full rebuild, host, MSVC/vcvars64): clean, 20/20 targets, no new warnings.
- `ctest --output-on-failure`: 8/10 passed. `test_abi` and `test_scale_normalization` failed —
  both are the same pre-existing failures the handoff already carries (not new breakage);
  binaries were rebuilt in this run, not stale.
- `flutter test`/`flutter analyze` not run — this phase touches no Dart.

**Left for later phases, unchanged from the plan:** `kAbnormalityCrop` still stubs to full
frame; the manifest's `protocol` still ships `"full_frame"`; no native unit tests yet (phase
2); no measurement yet (phase 3).

## Goal

Replace the stub block in `prepare_health_input()`
(`packages/instaham_ml_ffi/src/health_input.cpp:61-76`) with a real implementation of
`segmentation_crop` and `segmentation_masked`, including the coordinate recovery that maps the
pig mask from BASE_MASK space into the captured photo's own pixel space. Behaviour with
`protocol == "full_frame"` — which is what the shipped manifest still asks for — must be
byte-identical to today's.

## Design/Approach

### The coordinate problem, stated precisely

`prepare_health_input(src, requested, region, resize_shorter_side, crop)` is called from
`classifier.cpp:57` with `src` being the decoded capture, and `region` being filled at
`pipeline.cpp:503-510` from `stages::PigMask pig_mask`. Those two are in different spaces:

- `src` is `decode_image_rgb(image_path)` — the captured photo at its own dimensions.
- `pig_mask` is in BASE_MASK space: `segmentation.cpp:108` resizes the capture uniformly by
  `comp.resize_factor` to reach the regressor's training scale, the segmenter runs on a canvas
  composed from that, `construct_pig_mask()` unletterboxes back to the rotated normalized
  content, and `rotate_pig_mask_90_ccw()` then undoes README section 4's rotation. The mask
  that reaches `PigRegion` therefore matches the *normalized, un-rotated* image, whose size is
  `SegmentationOutput::normalized_w/h`.

Because the only geometric difference is one uniform resize, recovery is one scalar per axis
and they are equal. There is no offset, no padding and no rotation left to undo.

### Carrying the factor to where it is needed

`PigRegion` does not currently carry the factor. Two options, and the second is preferred:

1. Scale the region in `pipeline.cpp` before handing it over, so `PigRegion` is documented as
   original-image coordinates and `health_input.cpp` needs no new field. This matches the
   Python reference's docstring, which already says `PigRegion` is "in ORIGINAL image
   coordinates", and matches `health_input.h`'s existing comment saying the same.
2. Add the factor to `PigRegion` and scale inside `health_input.cpp`.

**Take option 1 for the bounding box and option 2's spirit for the bitmap**: scale `x0..y1` in
`pipeline.cpp` so the struct's documented contract becomes true, and let `health_input.cpp`
resample the mask bitmap itself to `src.width x src.height` — which is what the reference's
`interior_mask()` does, and which needs no extra field because the target size is already
known from `src`. `mask_w`/`mask_h` then describe the incoming bitmap and the resample is
driven by the ratio between them and `src`, so the two paths cannot disagree.

Record in the header that `PigRegion` is now genuinely original-image coordinates and that
`pipeline.cpp` is responsible for making it so.

### What each protocol does

Both follow `ML/parity/reference_health_input.py` exactly:

- **`segmentation_crop`**: clamp the region box to the image, pad it by
  `bbox_padding_ratio` (0.06) of the box's own width and height, crop, then the existing
  resize-shorter-then-crop tail. Background inside the padded box is retained.
- **`segmentation_masked`**: the same padded crop, but every pixel whose mask value is zero is
  overwritten with the fill colour before the resize. `background_fill: imagenet_mean` means
  `round(255 * [0.485, 0.456, 0.406])`, per `_imagenet_mean_rgb_uint8()`.

The resize tail is the existing `resize_shorter_then_crop()` — unchanged, shared with the view
classifier, and the thing every recorded classifier metric was produced under. The reference
also pads to `crop x crop` when the patch is smaller than the crop after resizing; the current
C++ clamps instead. Reconcile these in favour of the reference and note the change.

No OpenCV. The repo has `resize_exact`/`resize_uniform` in `util/image_io.h`; a nearest-
neighbour path for a binary mask is a short loop, matching `construct_pig_mask`'s own
unletterbox resample.

### Degradation rules that must survive

- `region == nullptr` or `!region->valid()` — fall back to full frame, `degraded = true`,
  `protocol_applied = "full_frame"`. This is the `health_only` route and every failed
  segmentation. AGENTS.md rule 4.
- An all-zero mask — same fall back. `region_source` still reports `"mask"` was offered.
- A degenerate padded box (zero or negative extent after clamping) — same fall back.
- `protocol_applied` must name what actually ran, never what was asked for. Nothing in this
  phase may report a crop it did not perform.

## Steps

- [ ] Add the bbox scaling in `pipeline.cpp`, using `seg_output.content_scale`, so `PigRegion`
      is genuinely in captured-image coordinates; update `health_input.h`'s comment to state
      that contract and name `pipeline.cpp` as its enforcer.
- [ ] Add a nearest-neighbour binary-mask resample helper (mask bitmap → `src` dimensions),
      producing 0/1 or 0/255 consistently with `PigMask`'s own convention.
- [ ] Implement `_crop_to_bbox`'s equivalent: clamp, pad by `bbox_padding_ratio`, crop, and
      optionally mean-fill outside the mask.
- [ ] Implement the `kSegmentationCrop` and `kSegmentationMasked` branches of
      `prepare_health_input()`, replacing the STUB block, with the degradation rules above.
- [ ] Read `bbox_padding_ratio` and `background_fill` from the manifest rather than hardcoding
      them — `manifest.json` already carries both under `capabilities.health.input`, and
      `manifest.{h,cpp}` needs the two fields added if they are not parsed today.
- [ ] Reconcile the small-patch case with the reference (pad to crop rather than clamp).
- [ ] Leave `kAbnormalityCrop` on the stub path, and leave the STUB comment block in the header
      accurate about what is now implemented and what is not.
- [ ] `dart format` is not applicable; run `clang-format` only if the repo already enforces it
      on this directory, otherwise match surrounding style by hand.

## Open questions

1. Are `bbox_padding_ratio` and `background_fill` already parsed into
   `ClassifierCapability`? If not, adding them is part of this phase and touches
   `manifest.{h,cpp}` and `test_shipped_manifest`.
2. Does `PigMask::pixels` use 0/255 while the reference expects 0/1? The struct comment says
   0/255; the comparison must be `> 0` throughout so the convention cannot bite.
3. Whether scaling the bbox in `pipeline.cpp` disturbs any other reader of `PigRegion`. Grep
   says `pipeline.cpp` is the only site that ever sets `has_mask = true`, so this should be
   contained, but confirm before editing.
