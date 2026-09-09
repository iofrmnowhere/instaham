# Phase 1 — ONNX export of the Chen16 booster

Status: done

## Goal

Turn `model_and_cutter/weight prediction/weight prediction/model.json` into
`assets/ml/weight/xgboost.onnx` plus its sidecars, using the same
`ML/export/export_xgboost.py` path every other model uses, with a numerical self-check
strong enough that a silent conversion error cannot reach the device.

## What the source model actually is

Read directly from `model.json` and its siblings:

| Property | Value |
|---|---|
| `learner.feature_names` | the 16 `chen16_noheight` names, in the order below |
| `learner_model_param.num_feature` | 16 |
| `learner_model_param.base_score` | `1.21669174E2` |
| `objective.name` | `reg:squarederror` |
| `gradient_booster.name` | `gbtree` |
| `gbtree_model_param.num_trees` | 600 |
| `version` | `[3, 4, 1]` (XGBoost 3.4.1 — matches the pin in `requirements-export.txt`) |
| categorical splits | none (`cats.enc` is empty) |

Feature order (this is the new "one true order", replacing `BASELINE5`):

```
mask_area, convex_hull_area, difference, dif_mask, body_curve, perimeter,
outline_curve, longest, shortest, Hu_1, Hu_2, Hu_3, Hu_4, Hu_5, Hu_6, Hu_7
```

Hyperparameters from `selected_params.json`: `n_estimators 600`, `learning_rate 0.03`,
`max_depth 5`, `min_child_weight 3`, `subsample 0.8`, `colsample_bytree 1.0`,
`reg_alpha 0.0`, `reg_lambda 2.0`.

## Design/Approach

### Where the source files live

Copy the vendor drop into a tracked, conventionally-named location rather than exporting
out of `model_and_cutter/` (which has doubled directory names and a space in the path that
breaks CLI invocations):

```
ML/weight_prediction_chen16/
  model.json
  feature_order.json
  selected_params.json
  fixed_test_metrics.json
  feature_importance.csv
  fixed_test_predictions.csv          # the parity + domain oracle; ~2.2 MB
  fixed_test_source_group_metrics.csv
  fixed_test_weight_band_metrics.csv
```

Leave `ML/weight_prediction/` (the baseline5 model) in place until phase 5 signs off, so a
rollback is a manifest edit rather than a file recovery.

### Generalizing the exporter

`ML/export/export_xgboost.py` currently hardcodes `BASELINE5` in seven places and refuses
any other feature order. Parameterize it by feature family instead of forking it:

- `ML/export/common.py`: add `CHEN16_NOHEIGHT = [...]` (the 16 names above) next to the
  existing `BASELINE5`, and a `FEATURE_FAMILIES = {"baseline5": BASELINE5,
  "chen16_noheight": CHEN16_NOHEIGHT}` map. Keep `BASELINE5` exported — phase 5 still needs
  it for the rollback path.
- `export_xgboost.py`: add `--feature-family` (default `chen16_noheight`). The existing
  assertion stays, retargeted: `booster.feature_names` must equal the selected family's
  list exactly, or exit. This preserves the intent of AGENTS.md rule 2 — the order is still
  asserted against a single named constant, it is just no longer a single hardcoded one.
- The `f0..fN` rename for onnxmltools stays, now `range(len(family))`.
- `FloatTensorType([None, len(family)])` instead of `[None, 5]`.
- `target_opset` stays 15 — the onnxmltools XGBoost converter caps there regardless of the
  value passed, as `requirements-export.txt` already records.

### The self-check must be stronger than the current one

The existing check feeds 8 rows of `np.random.rand` and compares `booster.predict` to ORT.
That catches a broken graph but not a wrong feature order or a dropped `base_score` — random
uniform rows in [0,1) are nowhere near this model's real input scale (`mask_area` runs
36 647 to 95 247). Replace it with two checks, both required:

1. **Graph transparency**: 64 rows sampled from the real per-feature ranges,
   `max_abs(booster.predict - ORT) < 1e-3`. Record the value in `xgboost.meta.json` as
   `onnx_max_abs_diff`, matching what `export_classifier.py` already records.
2. **End-to-end reproduction**: feed all 1821 rows of `fixed_test_predictions.csv` (the 16
   feature columns, in the declared order) through the ONNX graph and compare against that
   file's own `prediction` column. `max_abs < 1e-3` and recomputed `MAE` within `1e-6` of
   `fixed_test_metrics.json`'s `4.563722454911072`. This check simultaneously proves the
   feature order, the `base_score`, the objective, and the tree walk. Record the recomputed
   MAE in the meta file as `reproduced_test_mae`.

Check 2 is the one that matters. If it passes, the conversion is correct by construction.

### Sidecar and manifest fragment output

- `weight/feature_order.json` — `{"feature_family": "chen16_noheight", "features": [...16]}`.
  Byte-identical in content to the vendor's own `feature_order.json`, which is a free
  cross-check.
- `weight/xgboost.meta.json` — `feature_names` (16), `n_estimators 600`, `objective`,
  `base_score`, `source_model_sha256`, `onnx_max_abs_diff`, `reproduced_test_mae`,
  `target "weight_kg"`.
- `weight/manifest_fragment.json` — see phase 3 for the full new `weight` block shape. Phase
  1 emits it; phase 3 defines what the native loader demands of it.

### Risk: onnxmltools 1.16.0 against an XGBoost 3.4.1 booster

`onnxmltools`' XGBoost converter reads the booster's JSON dump, and 3.x changed that dump's
shape more than once. If `convert_xgboost` raises or produces a graph that fails check 2,
try in this order before considering anything else:

1. Round-trip the booster through the installed `xgboost` (`Booster.load_model` then
   `save_model` to a fresh path) so the dump is written by the exact pinned version.
2. Upgrade only `onnxmltools` and re-run both checks.
3. Convert via `skl2onnx` with the `XGBRegressor` wrapper, which uses the same underlying
   `onnxmltools` shape calculator but a different entry path.

Only if all three fail does the vendored `XGBoostJsonPredictor.cpp` (native JSON tree
evaluation, no ONNX) become the shipping path — and that is an ADR-worthy deviation from
"every model ships as ONNX", not a quiet substitution. Record it in `docs/fix.md` and stop
for a decision.

## Steps

- [x] Confirm the export environment: `python -c "import xgboost, onnxmltools, onnxruntime"`
      currently fails (`No module named 'xgboost'`), so create/activate the export venv and
      `pip install -r ML/export/requirements-export.txt` first.
- [x] Copy the eight vendor files into `ML/weight_prediction_chen16/`.
- [x] Add `CHEN16_NOHEIGHT` and `FEATURE_FAMILIES` to `ML/export/common.py`.
- [x] Parameterize `ML/export/export_xgboost.py` by `--feature-family`; keep the order
      assertion, retargeted.
- [x] Replace the random-row self-check with the two checks above.
- [x] Emit the new `feature_order.json` / `xgboost.meta.json` / `manifest_fragment.json`
      (fragment body specified in phase 3).
- [x] Run the export into `build/ml_export/weight`, confirm check 2 passes, then copy the
      three artifacts into `assets/ml/weight/`.
- [x] Rebuild `assets/ml/manifest.json` via `ML/export/build_manifest.py` and validate it
      against `ML/export/manifest.schema.json` (the schema itself may need the phase-3
      changes first — if so, do phase 3's schema edit before this step).
      **Deviation:** `build/ml_export/{health,segmentation}` carry stale fragments that no
      longer match the shipped manifest (health's probe-input merge, segmentation), so a
      full `build_manifest` run would regress those capabilities. The `weight` capability
      was patched into `assets/ml/manifest.json` surgically instead and the whole manifest
      re-validated against the schema; `build_manifest --check` passes. The schema's
      `weightCapability` was widened here (feature_family/feature_order/quality_gates,
      keyed feature_domain with `dimension`+`gate`, `regressor.base_score`) — phase 3 owns
      the native loader side of that contract.

## Results

- Export env: `.venv-export/` (dev only, gitignored). Phase-1 subset of
  `requirements-export.txt` installed (`xgboost 3.4.1`, `onnxmltools 1.16.0`,
  `onnxruntime 1.29.0`, `onnx 1.22.0`, `numpy 2.5.2`, `jsonschema 4.26.0`); torch/timm/
  ultralytics/opencv not needed for this phase and have no 3.13 wheel at the pinned
  versions anyway.
- `onnxmltools` converted the XGBoost 3.4.1 booster on the first try — none of the phase's
  three fallback routes were needed.
- Self-check 1 (graph transparency, 64 rows from real per-feature ranges):
  `onnx_max_abs_diff = 2.899e-4` (< 1e-3).
- Self-check 2 (all 1821 eval rows through ONNX vs the CSV `prediction` column):
  `max_abs 8.5e-4` (< 1e-3). The CSV's own `prediction` column reproduces
  `fixed_test_metrics.json` MAE to 8e-9 (float64). The ONNX float32 graph's recomputed
  MAE is `4.563711` vs `4.563722` — within the 1e-3 per-row bound, not the plan's 1e-6
  (float32 inference cannot hit 1e-6; the 1e-6 assertion was moved to the float64
  CSV-vs-metrics consistency check).
- `feature_order.json` is byte-identical in content to the vendor's own.
- `weight.available` stays `false` (`unavailable_reason: "cutter_identity_stub"`) — the
  real V176/V144 cutter is phase 2.

## Open questions

- Should `assets/ml/weight/` keep the old `baseline5` ONNX alongside the new one for a
  runtime A/B? Recommendation: no. Two regressors in one manifest is a contract the native
  loader does not model, and phase 5's rollback is a git revert of a single export.
