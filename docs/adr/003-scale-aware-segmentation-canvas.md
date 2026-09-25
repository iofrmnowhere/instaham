# ADR-003: Compose the segmenter's canvas from the reference scale, and walk a ladder

Status: Superseded by [ADR-013](013-normalize-first-segmentation-order.md)

Context: The segmenter was fed a plain fit-to-canvas letterbox of the whole frame. For a
typical 2250×3000 phone capture that leaves the pig roughly 220×400 px inside the 640×640
input — below what YOLO11s-seg reliably responds to. Field photos that a human reads as
obviously containing a pig either produced no detection above threshold or a tiny spurious
one. The apparent size of the subject in the model's input was being decided by the capture's
pixel resolution rather than by the animal's real-world size, even though a user-confirmed
reference object already gives the real-world scale.

Decision: When a user-confirmed `cm_per_px` exists and the manifest declares
`segmentation.input_scale.cm_per_px`, compose the canvas at
`content_scale = cm_per_px_actual / input_cm_per_px` via `place_at_scale()` instead of
`letterbox()`. Because the segmenter proved brittle at any single scale, `pipeline.cpp` walks
`ladder_multipliers` (`[1.0, 1.32, 1.68, 0.77]`) and then repeats the ladder at
`retry_conf_threshold` (0.10), stopping at the first rung whose constructed mask reaches
`weight.min_mask_diagonal_fraction`. The decision itself lives in `decide_canvas_scale()` in a
header-only, OpenCV- and ORT-free unit, so it is testable without a model or a photo.

Consequences: Segmentation now costs up to eight model passes on a hard photo instead of one,
paid only when earlier rungs fail. A requested scale that would overflow the canvas falls back
to the plain letterbox and sets `clamped_to_letterbox` — content is never clipped or distorted
silently. Every rung is recorded in `envelope["segmentation"]["rungs_tried"]`, so a photo whose
only usable rung is not rung 0 is visible from a saved envelope. With no confirmed reference,
or with a manifest whose `input_cm_per_px` is 0.0, behaviour is exactly the pre-existing single
plain-letterbox attempt: AGENTS.md rule 7 forbids inventing a scale, so the health-only route
and unreferenced scans keep the old path.
