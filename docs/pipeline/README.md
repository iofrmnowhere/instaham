# Pipeline Stages

Redirect table, not a table of contents. Open the one file that answers the question.

| Stage | File | One-line description |
|---|---|---|
| Segmentation (1) + construction (2) | [segmentation.md](segmentation.md) | Runs YOLO11s-seg on a scale-aware canvas, picks one instance, builds its mask in original image coordinates |
| Cutter (3), features (4), weight prediction (5) | [prediction.md](prediction.md) | Normalizes the mask into training pixel space, extracts RA/LC/BL/BW/E, gates them, runs the XGBoost regressor |

Not yet documented here: the view gate and the health classifier branch. Both live in
`src/classifier.cpp` + `src/health_input.cpp`; the routing rules they drive are summarised
in [../architecture.md](../architecture.md) under "Boundaries that matter".
