# Pipeline Stages

Redirect table, not a table of contents. Open the one file that answers the question.

| Stage | File | One-line description |
|---|---|---|
| Segmentation (1) + construction (2) | [segmentation.md](segmentation.md) | Normalizes the capture to `cm_per_px_target` before running YOLO11s-seg ([ADR-013](../adr/013-normalize-first-segmentation-order.md)), picks one instance, decodes one 640×640 mask, and unletterboxes it to original image coordinates for the quality gates |
| Construction (2), continued | [segmentation-2.md](segmentation-2.md) | The weight branch's `transform_mask_to_training_space()`: one composed crop-and-resize from the 640 mask into training pixel space (F55/F57), what it replaced and why, and how to reproduce the stage off-device |
| Cutter (3) | [cutter.md](cutter.md) | Ported V176 shoulder selector + V144 circle cut that removes the head/neck; what it runs, its `status` values, and why there is no oracle for a single cut |
| Cutter (3), continued | [cutter-2.md](cutter-2.md) | The two `computeBodyCurve()` calls, the truncation/posture quality gates and their manifest switches, what the weight branch now trusts, OpenCV build implications |
| Features (4) + weight prediction (5) | [prediction.md](prediction.md) | Order of eligibility checks, `k` and the scale range check, and the `feature_family`-selected extractors (chen16_noheight shipped, baseline5 rollback) |
| Domain gate, regression, persistence | [prediction-3.md](prediction-3.md) | The keyed `feature_domain` gate and its `gate`/`dimension` data, the `[1,N]` ONNX call, and what Dart writes to Drift |
| Weight sensitivity + calibration | [prediction-2.md](prediction-2.md) | Why area enters squared, why `cm_per_px_target` cannot be fitted against a tree ensemble, F46's on-device comparison of the fitted 0.35 against the derived 0.3289 (neither landed; both arms predate round 7's composed transform), and F53's four amplifiers of reference-marking noise (5–13% band per photo; the cutter and the boundary features dominate) |
| Calibration guidance | [prediction-4.md](prediction-4.md) | The standing rules drawn from those measurements: do not fit the constant, judge changes on repeat captures with a stated spread, round 28's measured `cm_per_px_target` = 0.34 with its two-corpus MAE figures and the 0.32-0.36 plateau ([ADR-012](../adr/012-measured-scale-target.md)), the `k = 1.0` arm's ~5% residual that no constant can fix, the ~73 kg floor below which no calibration helps, and what is still unmeasured for `chen16_noheight` |
| Health classifier | [health.md](health.md) | Input protocols (full frame, crop, masked), where the pig region comes from, the two-stage cascade (whole photo decides healthy; the masked pig gives a second reading of any other label), its envelope, and what the evidence does and does not support |

Not yet documented here: the view gate. It lives in `src/classifier.cpp`; the routing rules
it drives are in [../app-flow.md](../app-flow.md), and the native boundary in
[../architecture.md](../architecture.md) under "Boundaries that matter".

One exception to that stage table's routing assumptions: `run_pipeline`'s
`view_route_override` parameter (`""`, `"dorsal_valid"` or `"health_only"`, resolved by
`stages::resolve_view_route()` in `src/stages/view_route.h`) lets a `reject` take either
route instead of returning the `stopped` envelope, and lets a `health_only` take the
`dorsal_valid` route, so every stage below can run on a photograph the view model refused or
routed to health only. It is set only from an explicit per-photograph user choice
([../adr/017](../adr/017-user-consent-view-gate-override.md),
[../adr/020](../adr/020-view-route-override-either-route.md)) and weakens no other gate —
truncation, posture, scale and feature-domain all still apply as documented above.
