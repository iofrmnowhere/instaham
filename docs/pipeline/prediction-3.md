# Weight Prediction, part 3 — domain gate, regression, persistence

Continues [prediction.md](prediction.md), which covers the order of checks, scale
normalization, and feature calculation. Measured regressor sensitivity and the
`cm_per_px_target` calibration problem are in [prediction-2.md](prediction-2.md).

## Domain gate

The real question a sanity check should ask is whether the trained regressor has ever seen a
vector like this one. `weight.feature_domain` is a **map keyed by feature name** (it replaced
five named `domain_ra`…`domain_e` members when the vector width became arbitrary). Each entry
records the `[min, max]` that feature took across the regressor's own training/eval set, plus
`upper_multiplier` / `lower_multiplier`, a `dimension`, and a `gate` flag.

- **`gate`** decides eligibility vs. diagnostics. Only the six features `k` actually scales are
  gated; every dimensionless chen16 feature — including all seven Hu moments — is recorded and
  never enforced. Gating a Hu moment would reject on a shape statistic no one can act on.
- **`upper_multiplier` / `lower_multiplier`** are all `1.0` on `chen16_noheight`. On
  `baseline5` they widened the bounds to tolerate an uncut mask; with the real cutter running
  that justification is gone.
- **`dimension`** (`area` | `linear` | `dimensionless`) is manifest data, not a compiled-in
  table. It is the exponent on `cm_per_px_target_uncertainty` (1.30, clamped to ≥ 1.0 at load
  so a malformed value can only widen): squared for areas, first power for lengths, untouched
  for dimensionless. The gate is never stricter than the calibration it rests on.
- A feature whose manifest `max` is ≤ 0 has no data and is skipped rather than rejecting
  everything.

Every gated feature is checked with bitwise `&`, deliberately not `&&`, so all violations are
recorded instead of short-circuiting after the first. `classify_domain_violation()` reads each
violation's `dimension` — never a feature name — to name the cause:

- **Any dimensionless violation → `mask_shape_out_of_domain`**, even when size features also
  violated. A broken mask drags the size features off as a side effect of being the wrong
  shape; the shape violation is the cause, not a co-symptom to be outvoted. **Currently
  unreachable**: `ML/export/export_xgboost.py`'s meta tables set `gate: false` on every
  dimensionless feature in *both* families, `baseline5`'s `E` included, so no manifest the
  current exporter produces can fire this branch. The classifier keeps it because the
  decision is data-driven — a future manifest that gates a shape feature gets the right
  message without a code change. Degenerate masks are caught upstream instead, by
  `min_mask_diagonal_fraction` and the posture quality gate.
- **Size features only, all low → `subject_smaller_than_trained`.** Smaller than anything in
  the regressor's 87–192 kg eval set.
- **Anything else → `features_out_of_training_domain`.** A high size violation is the one case
  a mis-marked or mis-scaled reference plausibly explains.

`envelope["weight"]["violations"]` carries the machine-readable list (`feature`, `value`,
`allowed_min`, `allowed_max`, `direction`, `dimension`); `detail` carries the readable one.

## Regression

`predict_weight(OnnxRunner*, const std::vector<float>&)` is nothing more than "run that ONNX
graph": input shape `[1, N]` where `N` is the manifest's `feature_order` width, packed in
exactly that order. A width mismatch against the loaded graph is refused, never truncated or
padded. The order is asserted three times — at export against the family table in
`ML/export/common.py`, at manifest load against the compiled-in per-family constant, and again
at packing — and a manifest whose order disagrees fails to load with
`INSTAHAM_ML_ERR_CONTRACT`. A `baseline5` overload survives for the rollback path.

After a successful run each **gated** feature is re-checked against its **unwidened** trained
`[min, max]`. A gradient-boosted regressor cannot extrapolate: a vector past the raw max is
answered from an edge leaf, a real and silent ceiling. Those features are listed in
`extrapolated_features` with `extrapolated: true`, rather than presenting a saturated value
with the same confidence as an interpolated one.

`envelope["weight"]` on success: `estimated_kg`, `protocol_implemented: true`, `extrapolated`,
`extrapolated_features`, a `note` naming the un-field-validated calibration, and
`capture_contract` (`feature_space: fixed_camera_pixels`, `training_camera_height_m: 1.88`,
`camera_height_is_xgboost_feature: false` — camera height is a capture constraint, not a model
input).

## What Dart persists

`run_and_persist_pipeline_use_case.dart` writes the whole `features` block through to Drift as
a family-tagged blob rather than per-feature columns — `weight_results.feature_vector`
(`{"family":…,"values":{…}}`), `feature_family`, plus `cutter_kept_fraction` and
`cutter_status`. See [ADR-007](../adr/007-manifest-declared-feature-family.md) for why the
family is manifest data on both sides of the FFI seam and why the schema does not name
features. `featureRa`…`featureE` remain in the schema, deprecated and unwritten, because they
hold real pre-schemaVersion-4 field measurements.
> Continued in [prediction-2.md](prediction-2.md) — measured sensitivity of the shipped
> regressor: which features move it, why `cm_per_px_target` cannot be fitted, what is verified.
