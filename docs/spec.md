# Model I/O Spec

Initial capture, not a drift check — `docs/spec.md` did not exist before today, so there was
nothing to compare against. Everything below was derived from the code and from
`assets/ml/manifest.json` as they stand now.

Four ONNX graphs. `OnnxRunner` consumes outputs **positionally, in declaration order** —
output names are never looked up, so a re-export that reorders outputs breaks the pipeline
silently. Input names are recorded in the manifest for reference only; the runner passes a
single input tensor.

Every model receives an **already-EXIF-normalised** image. Correction happens once, Dart-side
at capture (`ImageService.processRawBytes` → `bakeOrientation`); the native layer never
rotates.

## View classifier — `assets/ml/view/model.onnx`

GhostNetV3-100, opset 17, `protocol_version: view_v1`.

### Input
- Shape: `1x3x224x224`, NCHW, RGB, float32. Input name `input`.
- Preprocessing: decode → resize shorter side to 255 (bilinear) → centre crop 224 →
  `(v * 1/255 − mean) / std`, mean `[0.485, 0.456, 0.406]`, std `[0.229, 0.224, 0.225]`.
  Runs on the raw photo, before segmentation; it has no input-protocol switch.

### Output
- Format: `[1, 3]` logits, positionally mapped to `view/classes.json`:
  `dorsal_valid` 0, `health_only` 1, `reject` 2. Class count is checked against
  `classes.json` at runtime; a mismatch is `INSTAHAM_ML_ERR_CONTRACT`, never a guess.
- Postprocessing: softmax → argmax label + confidence + full per-class probability map.
- Contract: the label **gates the whole graph**. `reject` stops the pipeline;
  `health_only` skips segmentation; `dorsal_valid` runs everything. Any other value, or an
  unavailable capability, fails closed with every downstream stage `skipped`.

## Health classifier — `assets/ml/health/model.onnx`

GhostNetV3-100, opset 17, `protocol_version: health_v1`.

### Input
- Shape: `1x3x224x224`, NCHW, RGB, float32. Input name `input`.
- Preprocessing: identical to the view classifier — same resize/crop/normalization
  constants, shared code path (`resize_shorter_then_crop` in `health_input.cpp`).
- Input protocol: manifest declares `full_frame`. `segmentation_crop` and
  `segmentation_masked` are declared as *supported* but their implementations are stubs that
  degrade to `full_frame`. When the manifest asks for anything but `full_frame`, the envelope
  reports `input_protocol_requested`, `input_protocol_applied` and `input_degraded: true`, so
  a scan can never claim a crop that did not happen.

### Output
- Format: `[1, 10]` logits over `health/classes.json`: `Healthy` 0, then nine
  `Infected_*` classes (bacterial erysipelas, greasy pig disease, environmental dermatitis,
  sunburn, fungal pityriasis rosea, ringworm, parasitic mange, viral FMD, swinepox).
- Postprocessing: softmax → argmax label + confidence + probability map.
- Contract: independent of the weight branch. A failed weight branch must never suppress
  this result, and health runs on both the `dorsal_valid` and `health_only` routes.

## Segmenter — `assets/ml/segmentation/yolo.onnx`

YOLO11s-seg with LDConv + ACmix, opset 17,
`protocol_version: yolo11s_ldconv_acmix_fixed_seed42`.

### Input
- Shape: `1x3x640x640`, NCHW, RGB, float32 in `[0,1]` (plain `v/255`, **no** ImageNet
  normalization — unlike the two classifiers). Input name `images`.
- Canvas composition: with a user-confirmed `cm_per_px` and a manifest
  `segmentation.input_scale.cm_per_px` (1.10), content is placed at
  `content_scale = cm_per_px_actual / input_cm_per_px`, padded with fill 114. Otherwise, or
  when that scale would overflow the canvas, a plain whole-frame letterbox (fill 114,
  `scaleup: false`, stride 32) with `clamped_to_letterbox` recorded.
- Retry ladder: multipliers `[1.0, 1.32, 1.68, 0.77]`, then the same ladder again at
  `retry_conf_threshold` 0.10.

### Output
- `outputs[0]`: `[1, 4 + nc + 32, num_anchors]` — `cx, cy, w, h`, then `nc` class scores,
  then 32 mask coefficients. **`nc` is derived** as `channels − 4 − num_coeffs`, never
  assumed to be 1.
- `outputs[1]`: `[1, 32, proto_h, proto_w]` — prototype plane, 160×160 at mask ratio 4.
- Postprocessing: threshold at `conf` 0.25 → single-class NMS at `iou` 0.70 → select the
  candidate with the largest sigmoid-thresholded mask area **cropped to its own detection
  box** (`mask_geometry.h`, shared with construction so the two cannot diverge) → decode
  coefficients × prototype → crop → bilinear upsample to 640 → threshold 0.5 → unletterbox
  with the carried pad/scale → nearest-neighbour resize to original dimensions.
- Mask protocol: `original_coordinate_polygon_v1`. Letterbox parameters are carried through
  on `SegmentationOutput` verbatim and never recomputed downstream.
- No detection above threshold is **not** an error; an instance is never fabricated.

## Weight regressor — `assets/ml/weight/xgboost.onnx`

XGBoost, 300 estimators, `reg:squarederror`, target `weight_kg`, feature family
`baseline5`.

### Input
- Shape: `[1, 5]`, float32, matching the export's `FloatTensorType([None, 5])`.
- Order is fixed and non-negotiable: **`RA, LC, BL, BW, E`**. Asserted three times — at
  export against `BASELINE5`, at manifest load against `weight/feature_order.json`, and in
  the packing itself. A manifest whose order disagrees fails to load with
  `INSTAHAM_ML_ERR_CONTRACT`.
- Features are measured on a mask resampled into the regressor's training pixel space by
  `k = cm_per_px_actual / cm_per_px_target` (target 0.35 cm/px), with `RA`'s denominator the
  720×720 training frame. `cm_per_px` comes **only** from the user-confirmed reference
  object; there is no implicit `k = 1.0`.
- Definitions: `RA` = filled area / frame area; `LC` = contour arc length; `BL`/`BW` = longer
  and shorter side of `minAreaRect`; `E` = `sqrt(1 − (minor/major)²)` of `fitEllipse`.

### Output
- Format: `[1, 1]`; `outputs[0].data[0]` is kilograms.
- Postprocessing: no transform. Two gates surround it — a **pre**-gate against the widened
  `feature_domain` bounds (widened by the per-feature multipliers and by
  `cm_per_px_target_uncertainty` 1.30, squared for `RA`, first power for the lengths, not at
  all for `E`), and a **post**-check against the *unwidened* trained `[min, max]` that sets
  `extrapolated` + `extrapolated_features` when the ensemble can only answer from an edge
  leaf.
- Standing caveat: the cutter is a permanent identity stub, so every number here is measured
  on an uncut mask (head and neck included) and overestimates the research protocol.
  `protocol_implemented` is always `false` and the envelope carries an explicit note.
  `cm_per_px_target` is a three-sample field estimate and must be retuned downward when the
  real cutter lands.

## Envelope and ABI

Payloads cross `dart:ffi` as UTF-8 JSON strings, never C structs, so envelope fields are
additive and `INSTAHAM_ML_ABI_VERSION` stays 1. Callers branch on the `InstahamMlStatus`
return code, never on JSON shape. Manifest `schema_version` is 1; every referenced model and
class-map file's sha256 is verified before any ORT session is created.

## Last verified against code: 2026-09-05
