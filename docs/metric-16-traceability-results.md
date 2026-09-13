# §16 traceability results, and the threshold gap

Status: **implemented and passing.** Recorded 2026-09-13.

Source: `test/assets/model_package_size_test.dart`, task 7 of
`docs/metrics-phase/6-device-metrics.md`. Host test, `flutter test`, no device. This is not
numbered as a "device metric" — §14's six device metrics do not include traceability — it
answers §16 directly and lives in the same file as metrics 4 and 6 because it is the same
shape of check: read the manifest, assert.

## What it checks

`assets/ml/manifest.json` is asserted to carry:

- `bundle_id`, `reference_commit`, `schema_version` — present and non-empty at the manifest's
  top level.
- `protocol_version` — present and non-empty **per capability** (`health`, `segmentation`,
  `view`, `weight`). There is no single top-level `protocol_version` field in this manifest;
  each capability versions its own protocol independently.
- **Per-model `sha256`** — not just present, but **recomputed from the file on disk and
  compared**. This is the one field in this test that is verified against reality rather than
  only checked for presence: presence alone would not catch a model file swapped into the
  bundle without the manifest being updated to match, which is the failure mode this field
  exists to catch.

**Deliberately not pinned to today's exact values.** `bundle_id`, `reference_commit` and
`schema_version` are asserted present and non-empty, not asserted to equal today's strings.
Pinning them would make every routine re-export a test failure unrelated to traceability —
the point is that the fields exist and are filled in, not that they never change.

## A real structural finding along the way

The first version of this test asserted `capabilities.<name>.protocol_version` directly and
failed on `weight`. That was not a manifest defect: `weight`'s `protocol_version`
(`chen16_noheight_centerchord_v2`) lives one level deeper, at
`capabilities.weight.feature_extractor.protocol_version`, not at
`capabilities.weight.protocol_version` like the other three capabilities. Confirmed by
searching the whole manifest for every `protocol_version` occurrence — `weight` is the only
capability that nests it under a sub-object rather than carrying it directly.

The test was corrected to search each capability's subtree generically rather than only its
top level, the same approach metric 4 already uses for `.onnx` paths, so a field that is
present-but-nested is not misreported as absent. The asymmetry itself is not fixed — it is a
genuine structural inconsistency in the manifest, left as-is per the standing instruction not
to modify manifest-generation code as a side effect of a test task. Worth knowing if the
manifest's schema is ever revisited.

## Results

| field | value | outcome |
|---|---|---|
| `bundle_id` | `instaham-ml-e13b1f4` | present |
| `reference_commit` | `e13b1f4` | present |
| `schema_version` | `1` | present |
| `capabilities.health.protocol_version` | `health_v1` | present |
| `capabilities.segmentation.protocol_version` | `yolo11s_ldconv_acmix_fixed_seed42` | present |
| `capabilities.view.protocol_version` | `view_v2` | present |
| `capabilities.weight.protocol_version` (nested, see above) | `chen16_noheight_centerchord_v2` | present |

Per-model `sha256`, manifest value vs. recomputed from the file on disk:

| model | manifest sha256 | matches file on disk? |
|---|---|---|
| `health/model.onnx` | `a58704...b430a07` | **yes** |
| `segmentation/yolo.onnx` | `a6467c...c0e508a` | **yes** |
| `view/model.onnx` | `703dab...5356b` | **yes** |
| `weight/xgboost.onnx` | `79ac21...edab543` | **yes** |

All four models on disk match their manifest-recorded hash exactly. (`weight`'s model is
declared under `capabilities.weight.regressor`, not `capabilities.weight.model` like the other
three — found generically the same way as the nesting difference above, not hardcoded.)

## The threshold gap — recorded, not invented

There is no `thresholds.json` anywhere in the repository. Two calibration thresholds exist
today and neither is manifest-declared:

- **`kHealthUncertainBelow = 0.60`** — a bare `const double` at
  `lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart:51`.
  Its own comment states it is display-only, not a gate: the health label is always the
  model's argmax, and a real gating threshold "belongs in the manifest with its own
  precision/recall justification, not hardcoded here" (that comment's own words).
- **The view classifier has no confidence threshold at all.** No cutoff of any kind gates or
  flags a low-confidence view classification.

This task does not add a `thresholds.json`, does not move `kHealthUncertainBelow` into the
manifest, and does not invent a threshold for the view classifier. Per the standing rule
against inventing a version to fill a gap that shouldn't be papered over, this section exists
to record that the gap is real and unaddressed — not to close it.

## Validation run

```
dart format test/assets/model_package_size_test.dart   -> clean
flutter analyze test/assets/model_package_size_test.dart -> No issues found!
flutter test test/assets/model_package_size_test.dart
```

```
+3: All tests passed!
```

All three tests in the file (metric 4, metric 6, §16 traceability) pass together.

## Known limitations

- `bundle_id`, `reference_commit` and `schema_version` are checked for presence, not for
  correctness — nothing here confirms `reference_commit` actually names a real commit, only
  that the field is filled in.
- The `sha256` verification proves the file on disk matches what the manifest claims; it does
  not prove the manifest's claim was correct when it was written; if a model and its recorded
  hash were both wrong together at export time, this test cannot detect that.
- The threshold gap above is unaddressed by design — see that section.
