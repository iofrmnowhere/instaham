# Metric 6 results — quantization and model export parity

Status: **implemented and passing.** Recorded 2026-09-13.

Source: `test/assets/model_package_size_test.dart`, task 6 of
`docs/metrics-phase/6-device-metrics.md`. Host test, `flutter test`, no device.

## What it checks

§14 device bullet 6: "accuracy after model export or quantization". The manifest
(`assets/ml/manifest.json`) already records each model's export self-check delta from when it
was exported to ONNX; this test asserts those five recorded values are present and within a
stated tolerance.

**This is not a re-verification of the export.** The test reads the recorded deltas — it does
not re-run the export or independently recompute anything. A pass means no model was swapped
into the bundle without its self-check re-run, and no recorded delta has grown past its bound
since it was last written. It must not be read as "export verified today".

**Two tolerances, not one.** Four of the five deltas are float32 round-trip noise, all
~1e-6, and share a `1e-4` bound. `box_mask_max_abs_diff` is three orders of magnitude larger
(~1.4e-3) and gets its own `5e-3` bound — folding it into the tight bound would either make
that check meaningless or make the noise check flake on ordinary variation.

## Results

| field | recorded value | tolerance | outcome |
|---|---|---|---|
| `capabilities.view.model.onnx_max_abs_diff` | 5.7220458984375e-06 | 1e-4 | passes |
| `capabilities.health.model.onnx_max_abs_diff` | 3.337860107421875e-06 | 1e-4 | passes |
| `capabilities.health.model.fusion_max_abs_diff` | 4.231929779052734e-06 | 1e-4 | passes |
| `capabilities.segmentation.model.onnx_self_check.proto_max_abs_diff` | 8.821487426757812e-06 | 1e-4 | passes |
| `capabilities.segmentation.model.onnx_self_check.box_mask_max_abs_diff` | 0.001434326171875 | 5e-3 | passes |

All five fields were present in the manifest and all five values are within their assigned
tolerance. `box_mask_max_abs_diff` has the least margin relative to its own bound (about 3.5x
under `5e-3`); every other value is at least two orders of magnitude under its `1e-4` bound.

## Validation run

```
dart format test/assets/model_package_size_test.dart   -> 1 file formatted, clean
flutter analyze test/assets/model_package_size_test.dart -> No issues found!
flutter test test/assets/model_package_size_test.dart
```

```
EXPORT_DELTA: view.model.onnx_max_abs_diff = 0.0000057220458984375 (tolerance 1.0e-4)
EXPORT_DELTA: health.model.onnx_max_abs_diff = 0.000003337860107421875 (tolerance 1.0e-4)
EXPORT_DELTA: health.model.fusion_max_abs_diff = 0.000004231929779052734 (tolerance 1.0e-4)
EXPORT_DELTA: segmentation.model.onnx_self_check.proto_max_abs_diff = 0.000008821487426757812 (tolerance 1.0e-4)
EXPORT_DELTA: segmentation.model.onnx_self_check.box_mask_max_abs_diff = 0.001434326171875 (tolerance 5.0e-3)
+2: All tests passed!
```

Both device metric 4 and metric 6 now run and pass in the same file (`+2`); metric 4's own
results are in `docs/metric-4-results.md`.

## Known limitations

- This is a manifest-freshness check, not an export re-verification — stated above and in the
  test's own comment so it is not misread later.
- The `box_mask_max_abs_diff` tolerance (`5e-3`) was chosen to be roughly 3.5x the single
  observed value, not derived from any stated accuracy requirement — §14 sets no numeric bound
  for this metric either, same as metrics 2, 3 and 4's 50 MB figure. If this delta grows on a
  future re-export, the bound may need revisiting rather than being treated as authoritative.
