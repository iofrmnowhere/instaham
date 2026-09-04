# Segmentation and Mask Construction

Stage 1 (`src/stages/segmentation.cpp`) runs the segmenter and selects one instance. Stage 2
(`src/stages/construction.cpp`) turns that selection into a binary mask in original image
coordinates. They are separate files on purpose, but they share one geometry contract, so
they are documented together.

Runs only on the `dorsal_valid` route. On `health_only` both stages report
`skipped: not_required_for_route` — the health classifier's region protocols are stubs that
degrade to full-frame, so a 640×640 YOLO pass would feed nothing.

## Model

YOLO11s-seg with LDConv + ACmix (`assets/ml/segmentation/yolo.onnx`, opset 17). Input
`images`, NCHW, RGB, 640×640, pixels scaled to `[0,1]`. Two outputs:

- `outputs[0]` — `[1, 4 + nc + 32, num_anchors]`: box `cx, cy, w, h`, then `nc` class
  scores, then 32 mask coefficients.
- `outputs[1]` — `[1, 32, proto_h, proto_w]`: the prototype plane, 160×160 at mask ratio 4.

`nc` is **derived** as `channels - 4 - num_coeffs`, never assumed to be 1. The pig model is
single-class today, but a hardcoded channel layout would silently misread both class scores
and coefficients on any future multi-class export.

## Canvas composition — the scale ladder

A plain fit-to-canvas letterbox makes a typical 2250×3000 phone capture's pig roughly
220×400 px in the model's input, below what the segmenter reliably responds to. So when a
user-confirmed `cm_per_px` exists **and** the manifest declares
`segmentation.input_scale.cm_per_px` (1.10), the canvas is composed at
`content_scale = cm_per_px_actual / input_cm_per_px` via `place_at_scale()` — the pig's
apparent size in the model's input then reflects its real-world size rather than the
capture's pixel count.

`decide_canvas_scale()` (`stages/canvas_scale.h`) owns that decision. It is header-only and
free of OpenCV and ORT so it can be unit-tested without a model or a photo
(`test_segmentation_canvas.cpp`). It refuses the scale-aware path — returning
`use_scale_aware = false` — when either input is missing, non-finite, or non-positive, or
when the scaled content would overflow the 640×640 canvas. The caller then falls back to the
plain letterbox and records `clamped_to_letterbox = true`; content is never clipped or
distorted silently.

The segmenter is brittle at any single scale, so `pipeline.cpp` walks a ladder rather than
trying one composition:

1. Each multiplier in `segmentation.input_scale.ladder_multipliers` — `[1.0, 1.32, 1.68,
   0.77]` — applied to `input_cm_per_px`, at the manifest's normal `conf` of 0.25.
2. If no rung produced a plausible mask, the whole ladder again at
   `retry_conf_threshold` (0.10). A `retry_conf_threshold` of 0.0 disables this pass rather
   than silently lowering the bar.

The loop stops at the **first** rung whose constructed mask reaches
`weight.min_mask_diagonal_fraction` (0.35) — not the best across all rungs, which would be a
different and unvalidated selection criterion. If none reach it, the highest-diagonal rung is
kept so the plausibility gate downstream rejects with a real mask and a real fraction. Every
attempt is recorded in `envelope["segmentation"]["rungs_tried"]` with its multiplier,
confidence used, `content_scale`, `clamped_to_letterbox`, and outcome.

With no confirmed reference, or with an older manifest whose `input_cm_per_px` is 0.0, there
is exactly one attempt using the plain letterbox.

## Instance selection

Candidates above the confidence threshold go through single-class NMS at `iou` 0.7. The
survivor is chosen by **thresholded mask area, not confidence** — matching the Python
reference's `_largest_mask_index`.

The area is measured on the mask **cropped to that candidate's own detection box**, via
`proto_box_bounds()` + `cropped_mask_area()` in `stages/mask_geometry.h`. This is the same
crop `construct_pig_mask()` applies, and sharing the header is the point: selection used to
score each candidate's raw coefficient response across the whole 160×160 proto plane while
construction cropped to the box, so a small, wrong detection whose coefficients responded
strongly *outside* its own box could win selection and then be built from its tiny box —
producing masks as small as 14×3 px against a 2250×3000 frame. The two can no longer diverge
on which pixels count.

`mask_geometry.h` is header-only and OpenCV-free, so `segmentation.cpp` (which links no
OpenCV) shares it with `construction.cpp` without gaining a dependency, and both are
testable in `test_mask_selection.cpp`.

No detection above threshold is **not an error**: `has_detection` stays false and the stage
returns true. An instance is never fabricated.

## Handoff contract (stage 1 → stage 2)

`SegmentationOutput` carries the selected box, its 32 coefficients, the whole proto tensor,
and the letterbox parameters **verbatim** — `letterbox_scale`, `letterbox_pad_left`,
`letterbox_pad_top`, `model_imgsz`, `orig_w`, `orig_h`. Construction re-derives none of them.
Recomputing the pad would duplicate `letterbox()`'s own rounding and could drift by a pixel
if the two were edited out of step.

## Construction

`construct_pig_mask()` mirrors ultralytics' `process_mask`, in this order:

1. Decode `coefficients × prototype` at proto resolution and apply a sigmoid.
2. Zero everything outside `proto_box_bounds()` — crop **before** the upsample.
3. Bilinear upsample to 640×640, then threshold at 0.5 — ultralytics thresholds after.
4. Unletterbox: remove the carried pad, nearest-neighbour resize to `orig_w × orig_h`.

No cleanup is applied; this reproduces the Python reference's raw output, which is what the
IoU ≥ 0.95 parity gate compares. An empty crop yields an empty `PigMask`, never a crash.
The result carries its own nonzero-pixel `area_px` and bounding box.

`scale_mask_to_training_space()` lives in the same file but belongs to the weight branch —
see [prediction.md](prediction.md).

## Envelope fields

`envelope["segmentation"]` on success: `confidence`, `instances_found`, `candidates_kept`,
`selected_mask_area_proto`, `runner_up_mask_area_proto`, `selected_box_orig`,
`selected_box_frame_fraction`, `ladder_rung`, `rungs_tried`, `content_scale`,
`input_cm_per_px_used`, `clamped_to_letterbox`.

These exist so a future selection or scale bug is visible from a saved envelope without a
code read. A near-tie between `selected_mask_area_proto` and `runner_up_mask_area_proto`, or
a `selected_box_frame_fraction` of a few percent where a real pig fills 55–85% of the frame,
names the failure directly.

On failure: `{"status":"error","reason":<seg error>|"no_instance_above_conf"|"empty_mask",
"rungs_tried":[...]}`, and `envelope["construction"]` reports `skipped` with the matching
reason. `envelope["construction"]` on success carries `mask_protocol`
(`original_coordinate_polygon_v1`), `mask_area_px`, `bbox`, and `mask_diagonal_fraction`.
