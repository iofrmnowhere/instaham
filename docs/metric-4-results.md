# Metric 4 results — mobile model package file sizes

Status: **implemented and passing.** Recorded 2026-09-13.

Source: `test/assets/model_package_size_test.dart`, task 2 of
`docs/metrics-phase/6-device-metrics.md`. Host test, `flutter test`, no device.

## What it checks

Every `.onnx` model path declared in `assets/ml/manifest.json`, found by walking the JSON
tree for any `path` field ending in `.onnx` — not a hardcoded list, so a model added to the
bundle is covered automatically. Each model file is stat'd on disk and asserted individually
against a 50 MB ceiling.

**Target provenance.** The `< 50 MB` figure is a product decision recorded in
`docs/metrics-phase/6-device-metrics.md` ("Agreed targets"), dated 2026-09-12.
`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §14 states no numeric size target for any
metric — its device-testing list says only "model file sizes", no number. This check is
per-model, deliberately: the bundle total is not asserted.

## Results

| model | path | size | vs. 50 MB target |
|---|---|---|---|
| health classifier | `assets/ml/health/model.onnx` | **18.68 MB** (19 589 042 bytes) | passes, 31.32 MB margin |
| segmentation | `assets/ml/segmentation/yolo.onnx` | **38.46 MB** (40 329 357 bytes) | passes, 11.54 MB margin |
| view classifier | `assets/ml/view/model.onnx` | **9.50 MB** (9 960 393 bytes) | passes, 40.50 MB margin |
| weight regressor | `assets/ml/weight/xgboost.onnx` | **0.97 MB** (1 022 014 bytes) | passes, 49.03 MB margin |

**Bundle total: ~67.61 MB** across the four models — not asserted, reported here for context
only. The segmentation model is the one with the least margin; it is the only model within an
order of magnitude of the 50 MB ceiling.

## Validation run

```
dart format test/assets/model_package_size_test.dart   -> 1 file formatted, clean
flutter analyze test/assets/model_package_size_test.dart -> No issues found!
flutter test test/assets/model_package_size_test.dart
```

```
MODEL_SIZE: health/model.onnx = 18.68 MB (19589042 bytes)
MODEL_SIZE: segmentation/yolo.onnx = 38.46 MB (40329357 bytes)
MODEL_SIZE: view/model.onnx = 9.50 MB (9960393 bytes)
MODEL_SIZE: weight/xgboost.onnx = 0.97 MB (1022014 bytes)
+1: Device metric 6 ... Skip: Not yet implemented — see docs/metrics-phase/6-device-metrics.md task 6
+1 ~1: All tests passed!
```

Metric 6 in the same file remains an explicit skip — task 6 wires it, not this task.

## Known limitations

- These are the sizes of the files checked into the repo today. The test re-derives the list
  and re-stats on every run, so it will catch a size regression the next time it runs — it is
  not a one-time snapshot.
- Bundle total is informational only; nothing in this task asserts it, per task 2's own
  instruction.
