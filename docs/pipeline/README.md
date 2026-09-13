# Pipeline Stages

Redirect table, not a table of contents. Open the one file that answers the question.

| Stage | File | One-line description |
|---|---|---|
| Segmentation (1) + construction (2) | [segmentation.md](segmentation.md) | Runs YOLO11s-seg on a scale-aware canvas, picks one instance, decodes one 640×640 mask, and unletterboxes it to original image coordinates for the quality gates |
| Construction (2), continued | [segmentation-2.md](segmentation-2.md) | The weight branch's `transform_mask_to_training_space()`: one composed crop-and-resize from the 640 mask into training pixel space (F55/F57), what it replaced and why, and how to reproduce the stage off-device |
| Cutter (3) | [cutter.md](cutter.md) | Ported V176 shoulder selector + V144 circle cut that removes the head/neck; what it runs, its `status` values, and why there is no oracle for a single cut |
| Cutter (3), continued | [cutter-2.md](cutter-2.md) | The two `computeBodyCurve()` calls, the truncation/posture quality gates and their manifest switches, what the weight branch now trusts, OpenCV build implications |
| Features (4) + weight prediction (5) | [prediction.md](prediction.md) | Order of eligibility checks, `k` and the scale range check, and the `feature_family`-selected extractors (chen16_noheight shipped, baseline5 rollback) |
| Domain gate, regression, persistence | [prediction-3.md](prediction-3.md) | The keyed `feature_domain` gate and its `gate`/`dimension` data, the `[1,N]` ONNX call, and what Dart writes to Drift |
| Weight sensitivity + calibration | [prediction-2.md](prediction-2.md) | Why area enters squared, why `cm_per_px_target` cannot be fitted against a tree ensemble, F46's on-device comparison of the fitted 0.35 against the derived 0.3289 (neither landed; both arms predate round 7's composed transform), and F53's four amplifiers of reference-marking noise (5–13% band per photo; the cutter and the boundary features dominate) |
| Calibration guidance | [prediction-4.md](prediction-4.md) | The standing rules drawn from those measurements: do not fit the constant, judge changes on repeat captures with a stated spread, why the shipped `cm_per_px_target` is now the derived 0.3289473684210526 with no accuracy measurement behind it yet ([ADR-011](../adr/011-derived-scale-target.md)), the ~73 kg floor below which no calibration helps, and what is still unmeasured for `chen16_noheight` |

Not yet documented here: the view gate and the health classifier branch. Both live in
`src/classifier.cpp` + `src/health_input.cpp`; the routing rules they drive are in
[../app-flow.md](../app-flow.md), and the native boundary in
[../architecture.md](../architecture.md) under "Boundaries that matter".
