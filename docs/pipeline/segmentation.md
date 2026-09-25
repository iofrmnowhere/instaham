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

## Canvas composition — normalize before segmenting

A plain fit-to-canvas letterbox makes a typical 2250×3000 phone capture's pig roughly
220×400 px in the model's input, below what the segmenter reliably responds to. Round 8
([ADR-013](../adr/013-normalize-first-segmentation-order.md)) fixes this by normalizing the
*photograph* to physical scale before the segmenter ever sees it, rather than composing a
scale-aware canvas around the capture's own pixel count: the source image is uniformly resized
so it is exactly `cm_per_px_target` cm/pixel, rotated 90° clockwise when that leaves it
portrait (README §4 — no dynamic head-direction inference;
[ADR-014](../adr/014-capture-orientation-contract.md) makes that assumption true at capture
time), then centred unresized on a 960×540 canvas before the model's own 640×640 letterbox is
applied on top.

`decide_normalize_first_composition()` (`stages/canvas_scale.h`) owns that arithmetic — the
resize factor, the rotation decision, the canvas offsets, and README §6's fit check. It is
header-only and free of OpenCV and ORT so it can be unit-tested without a model or a photo
(`test_segmentation_canvas.cpp`). Both `cm_per_px_actual` (the user-confirmed reference) and
`cm_per_px_target` (the manifest's training scale) must be positive and finite, or the
composition is invalid — there is no plain-letterbox fallback (README §15 forbids treating
normalization as optional; AGENTS.md rule 7 forbids inventing a scale). If the normalized,
rotated content does not fit the 960×540 canvas, the stage returns a declared failure
(`oversize = true`, `out->normalized_w/h` and the canvas bound recorded) rather than enlarging
or shrinking anything — README §6's halt, with no fallback.

`run_segmentation()` (`stages/segmentation.cpp`) performs exactly **one** composition per call
— README §13 is a single pass at one scale, not a ladder; a caller wanting to retry at a
different scale would call this function again, and nothing in this round does. The round-4
scale ladder and its four `ladder_multipliers` rungs are removed outright, not disabled behind
a switch.

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

## Construction — one decode, two branches

Steps 1–3 are the shared `decode_binary_640()` helper; both branches start from its mask:

1. Decode `coefficients × prototype` at proto resolution and apply a sigmoid.
2. Zero everything outside `proto_box_bounds()` — crop **before** the upsample.
3. Bilinear upsample to 640×640, then threshold at 0.5 — ultralytics thresholds after.

`construct_pig_mask()` adds step 4 — unletterbox: remove the carried pad, nearest-neighbour
resize to `orig_w × orig_h` — and since round 7 serves the **gate branch only**, because the
truncation and posture gates must see original capture coordinates. No cleanup is applied, so
it matches the Python reference's raw output, which the IoU ≥ 0.95 parity gate compares; an
empty crop yields an empty `PigMask` (never a crash) carrying its own `area_px` and bbox.

The **weight branch** never takes step 4: it composes its own transform from the same decoded
640 mask straight into training pixel space — see [segmentation-2.md](segmentation-2.md).

## Envelope fields

`envelope["segmentation"]` on success: `confidence`, `instances_found`, `candidates_kept`,
`selected_mask_area_proto`, `runner_up_mask_area_proto`, `selected_box_orig`,
`selected_box_frame_fraction`, plus round 8's normalize-first fields —
`was_rotated_clockwise`, `resize_factor`, `normalized_w`/`h`, `x_offset`/`y_offset`,
`rotated_width`/`height`, `content_scale`, `input_cm_per_px_used`. `ladder_rung`,
`rungs_tried`, and `clamped_to_letterbox` are round-4 fields removed with the scale ladder
([ADR-013](../adr/013-normalize-first-segmentation-order.md)) and no longer appear.

These exist so a future selection or scale bug is visible from a saved envelope without a
code read. A near-tie between `selected_mask_area_proto` and `runner_up_mask_area_proto`, or
a `selected_box_frame_fraction` of a few percent where a real pig fills 55–85% of the frame,
names the failure directly.

On failure: `{"status":"error","reason":<seg error>|"no_instance_above_conf"|"empty_mask"|
"oversize"}` — the last is README §6's fit halt, carrying `normalized_w`/`h` and the 960x540
bound — and `envelope["construction"]` reports `skipped` with the matching reason.
`envelope["construction"]` on success carries `mask_protocol`
(`original_coordinate_polygon_v1`), `mask_area_px`, `bbox`, and `mask_diagonal_fraction`.

> Continued in segmentation-2.md — the weight branch's composed mask transform, and
> reproducing this stage offline.
