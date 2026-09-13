# Segmentation, continued — the weight branch's composed transform

Continues [segmentation.md](segmentation.md). That file covers stage 1 and
`construct_pig_mask()`, which since round 7 serves the quality gates only. This file covers
the second consumer of the same decoded 640×640 mask — the weight branch's
`transform_mask_to_training_space()` — and how to reproduce the stage off-device.

## Why the mask is no longer rasterized twice

Until round 7 the weight branch reached training pixel space in two steps: `construct_pig_mask()`
unletterboxed to full capture resolution (nearest-neighbour), then
`scale_mask_to_training_space()` resized that by `k = cm_per_px_actual / cm_per_px_target`,
again nearest-neighbour. Both steps grid-snapped, and both snapped *as a function of `k`* — so
one pixel of movement in a reference mark shifted the whole contour's quantization and moved
the estimate by up to ~13% (F53's measured bands, in
[../fix-phase-2/2.1-reference-length-sensitivity.md](../fix-phase-2/2.1-reference-length-sensitivity.md)).
Replacing the second step's interpolation alone was tried first and measured *worse*; the
count of rasterizations, not their kernel, was the thing to fix (F55).

## What `transform_mask_to_training_space()` does

One crop-and-resize, straight from `decode_binary_640()`'s output into training pixel space,
composing three transforms that used to be applied separately:

```
x_final = (x_640 − padX) · k / r        # r = seg.letterbox_scale, k = cm_per_px_actual / target
```

- **The crop is exact, not a resample.** `letterbox_pad_left/top` are integer pixel counts and
  the crop width reproduces `letterbox()`'s own `new_w`, so removing the pad is a view.
- **`r` is read verbatim from `seg.letterbox_scale`** — *not* recomputed as `min(640/W, 640/H)`
  (F57). The two agree only for a plain whole-frame letterbox; this app composes the canvas
  through `place_at_scale()` whenever a reference is marked, and then they differ.
- **One `cv::resize` is the only rasterization**: `INTER_AREA` when shrinking (the usual case),
  `INTER_LINEAR` when enlarging, then re-thresholded to strict 0/255 — both kernels produce
  grey from a 0/255 source and every downstream stage assumes a binary mask.
- **Not `cv::warpAffine`**, which cannot do `INTER_AREA` and so cannot serve the shrink case.
- The signature is `(seg, k)`, not `(seg, binary_640, k)`, so `pipeline.cpp` needs no OpenCV
  types of its own.

It returns an **empty** `PigMask` — never an unscaled copy — when `k` is not finite and
positive, when `seg.has_detection` is false, or when the composed output dimensions would be
non-positive. `pipeline.cpp` then clears `scale_ok` and reports
`scale: {status: unavailable, reason: scale_resample_failed}`.

## What did not change

The truncation and posture gates still run on `construct_pig_mask()`'s mask in **original
capture coordinates**, before the weight branch's transform — the two branches now consume the
same decode independently. That path is byte-identical across the change (`mask_area_px`
103267 on the round's reference photo). The no-reference fallback still goes through
`scale_mask_to_training_space()`, which has no calibrated target space to compose into; F43's
`kUnscaledCutterMaxDimPx` cap rides on it.

`envelope["construction"]["composed_transform"]` carries `letterbox_scale`, `k`, `out_w`,
`out_h` and `out_area_px` whenever the composed path ran. `test_mask_transform` covers the
function directly.

## Measured effect

Host-harness jitter sweeps (`ML/host_scale_test/jitter_sweep.py`), worst-case spread over a
band of reference marks, before → after: 1280-upscale corpus 14.7% → 10.9%; native 1.78 m
11.9% → 10.3%; native 1.88 m 6.4% → 6.2%. **Per image the result is mixed** — three of five
images in the 1280 corpus got slightly worse. No on-device measurement exists yet; the F53
re-mark against the 5.18% / 12.04% / 12.55% bands is the real verdict and is still open.

## Reproducing this stage offline

`ML/tools/replicate_native_weight_branch.py` re-implements this stage and the weight branch in
Python against the same manifest and `.onnx` files — seconds rather than an APK cycle. Its
fidelity is not uniform across the stage, and the difference matters:

- **Measurement is faithful.** Given a mask, the harness's five features land within 2% of the
  native pipeline's on the same photo, and the regressor agrees exactly (see
  [prediction-2.md](prediction-2.md)).
- **Detection is not.** The harness reports no detection at all on a field photo that the
  device segments at confidence 0.92 on the same rung. Its own image loading re-encodes
  through a JPEG round-trip at quality 92 and caps the long edge at 3000 px before the
  segmenter sees anything, which the native decode path does not do.

So a harness result about *what the mask measures* is usable evidence; a harness result about
*whether a pig is detected*, or which rung detects it, is not. Confirm detection behaviour
against persisted `rungs_tried` from a real device scan instead.
