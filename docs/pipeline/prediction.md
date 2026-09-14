# Weight Prediction

Stages 4–5 of the `dorsal_valid` route: feature calculation
(`src/stages/feature_calculation.cpp`) and weight prediction
(`src/stages/weight_prediction.cpp`), with the scale and gating logic in `src/pipeline.cpp`.
Stage 3, the cutter, has its own file — [cutter.md](cutter.md). Everything here is downstream
of a constructed mask ([segmentation.md](segmentation.md)) and independent of health: it may
fail at any of the nine checks below without affecting `envelope["health"]`.

Since plan phase 3 the branch is family-generic: the manifest declares
`weight.feature_family` (`baseline5` | `chen16_noheight`) and a `feature_order` of arbitrary
width, and every stage from feature extraction to the domain gate to the ONNX packing walks
that list instead of five hardcoded names. The shipped manifest declares `chen16_noheight`,
16 features wide, measured on the real V176/V144 cut mask ([cutter.md](cutter.md)).

`weight.available` is **now `true`**, set deliberately by re-exporting with
`--enable-for-testing` (`docs/fix-2.md` F42) so the branch can be exercised on a device.
Estimates therefore ship, and each is real inference carrying the envelope's provisional
`note` — but the calibration behind them is a host measurement, not a field calibration.
`cm_per_px_target` reads **0.34**, the MAE minimum measured independently on both host sweep
corpora on the current post-F55 path ([ADR-012](../adr/012-measured-scale-target.md)); it
replaced ADR-011's derived `0.3289473684210526`, which that sweep ranked last of three.
Figures and the residual error the constant cannot fix: [prediction-4.md](prediction-4.md).
Treat a returned number as provisional — and below roughly 85 kg as systematically high, per
[ADR-010](../adr/010-regressor-training-domain-floor.md). ADR-005's +16.6% mean bias is
superseded: it was measured by feature substitution before the cutter was ported.

## Order of checks

Each check either passes or writes `envelope["weight"]` and stops. None is skippable.

1. **Weight capability available.** Manifest `weight.available` plus a loaded regressor.
   Failure → `weight_capability_unavailable`.
2. **Reference confirmed.** `cm_per_px` present, finite, positive. There is no implicit
   `k = 1.0`. Failure → `reference_object_not_confirmed`.
3. **Camera height in range** (below). Failure → `scale_out_of_range`.
4. **Mask plausibility.** `mask_diagonal_fraction` — mask bbox diagonal over image diagonal —
   must reach `weight.min_mask_diagonal_fraction` (0.35). Measured on the raw captured mask
   before normalization, since resampling changes absolute size, not a mask's proportion of
   its own frame. Runs *before* the cutter so a sliver mask never reaches the feature stages.
   A dimensionless shape feature alone cannot catch it: a thin sliver scores **high** on
   eccentricity, not low. Failure → `mask_implausibly_small`.
5. **Quality gates** — truncation, then posture, on the whole mask in capture coordinates.
   Both ship switched off; see [cutter-2.md](cutter-2.md). Failure →
   `truncation_gate_rejected` or `posture_gate_rejected`.
6. **Resample succeeded.** Failure → `scale_resample_failed`.
7. **Cutter succeeded.** Failure → `cutter_failed` (the specific decline is in
   `envelope["cutter"]["status"]`).
8. **Feature extraction succeeded.** Failure → `contour_too_small`.
9. **Feature domain** (below). Failure → `mask_shape_out_of_domain`,
   `subject_smaller_than_trained`, or `features_out_of_training_domain`.

Checks 1–3 run in the scale block, before the weight branch; 4–9 run inside it. Every
rejection carries its own `reason` plus a `user_message_key`, and `envelope["scale"]["reason"]`
and `envelope["weight"]["reason"]` read the same variable, so they cannot disagree. Collapsing
these into one generic message once told a user with a correctly-marked reference to go mark a
reference object.

**With `weight.available` false, checks 4 through 9 still run and still populate
`envelope["cutter"]`, `["quality_gates"]` and `["features"]`, but `envelope["weight"]` reports
`weight_pending_field_validation` regardless of which one declined.** Read the per-stage
blocks, not `weight.reason`, when diagnosing such a build.

That is not the current configuration. With the `--enable-for-testing` override active,
`weight_pending_field_validation` is **unreachable** — it lives only in `pipeline.cpp`'s
`weight_unavailable_json`, which every branch assigns on the `weight_override == false` side
of its ternary — so `weight.reason` names the real decline and can be read directly. Anything
keyed to the pending reason is correspondingly dead while the override is on, including the
cutter-decline message in `run_and_persist_pipeline_use_case.dart:411`.

## Scale normalization

`k = cm_per_px_actual / weight.cm_per_px_target` (target from the manifest, currently
0.34 cm/px — see the calibration note above). The mask reaches training space in
**one** resampling, composed straight from the 640×640 mask by
`transform_mask_to_training_space()`; capture resolution is never visited. Mechanics, and why
the chain it replaced amplified marking jitter (F55): [segmentation-2.md](segmentation-2.md). The
cutter's thresholds and RA's denominator still operate in the training space; a non-finite or
non-positive `k` returns an empty mask, never an unscaled copy.

`k` alone conflates camera height with capture resolution: the training frame is a fixed
720×720 while a live capture is typically 1280 px wide and a gallery import up to 3000. The
range check divides the resolution term back out:

```
height_ratio = k * sqrt(mask_w * mask_h) / sqrt(training_frame_w * training_frame_h)
implied_camera_height_m = training_camera_height_m * height_ratio     # 1.88 m
```

Accepted range is `height_ratio` in `[0.25, 4.0]`. Bounding raw `k` instead once rejected a
perfectly framed 3000 px photo taken at exactly 1.88 m purely for its pixel count.

`envelope["scale"]` reports `cm_per_px_actual`, `cm_per_px_target`, `k`, `height_ratio`,
`implied_camera_height_m`, `training_frame_px`, `source: user_confirmed_reference`; the composed
transform's own numbers land under `envelope["construction"]["composed_transform"]`.

`k` is the highest-gain constant in the pipeline: area scales with `k²` and the regressor is
effectively univariate in its area term (`RA` on baseline5, `mask_area` on chen16 — the same
quantity un-normalized), so a 1% scale error becomes a 2.8–4.0% weight error. The value itself
measures within ~3% of correct — see [prediction-2.md](prediction-2.md) and
[ADR-005](../adr/005-identity-cutter-is-the-dominant-error.md).

## Feature calculation — selected by `feature_family`

`pipeline.cpp` branches on `manifest.weight.feature_family`; each extractor returns a
`map<name, double>` that is then serialized in the manifest's own `feature_order`. Both return
`std::nullopt` (→ `contour_too_small`) when the largest external contour has fewer than 5
points — `fitEllipse` needs 5, and the Python reference returns `None` at the same boundary.

**`chen16_noheight` (shipped).** `extract_chen16_features()` measures the **final cut mask** in
raw pixel counts — there is no RA-style frame denominator and no `linear_scale` factor, because
the mask handed to it is already in training pixel space:

| Group | Features | Gated? |
|---|---|---|
| Area | `mask_area`, `convex_hull_area`, `difference` | yes |
| Linear | `perimeter`, `longest`, `shortest` | yes |
| Dimensionless | `dif_mask`, `body_curve`, `outline_curve`, `Hu_1`–`Hu_7` | no |

Verified against the Python function that produced the training features
(`ML/pipeline/feature_calculation.py`, protocol `chen16_noheight_centerchord_v2`) over 20
`MASK_3394` ground-truth masks by `ML/parity/chen16_feature_port_gate.py`: **20/20 masks, 0
mismatches**. The last holdout was `body_curve`, whose C++ skeletonizer used the textbook
Zhang-Suen algebraic conditions while `skimage.morphology.skeletonize(method='zhang')` is a
compiled 256-entry neighbourhood LUT that does not reduce to them; a vendor LUT patch to
`BodyCurve.cpp` closed it.

**`baseline5` (rollback path).** `extract_five_features()` returns `RA` (`area_pixels /
(frame_w * frame_h)`), `LC` (contour arc length), `BL`/`BW` (longer/shorter side of
`minAreaRect`), `E` (`sqrt(1 - (minor/major)^2)` of `fitEllipse`), the three lengths scaled by
`linear_scale`. With a scale established `linear_scale` is 1.0 and RA's denominator is the
manifest's 720×720 training frame; without one the denominator falls back to the mask's own
dimensions, reproducing the pre-normalization provisional values.

`envelope["features"]` either way:

```json
{"status": "provisional", "family": "chen16_noheight",
 "order": ["mask_area", …], "gated": ["mask_area", "convex_hull_area", "difference",
 "perimeter", "longest", "shortest"], "values": {"mask_area": 61234.0, …},
 "measured_on": "training_normalized_mask"}
```

`gated` names the subset whose domain is an eligibility check rather than a diagnostic bound.
It exists so the Dart rejection renderer shows six labelled measurements instead of sixteen
raw ones, without keeping a second hardcoded feature list of its own.

> Continued in [prediction-3.md](prediction-3.md) — the domain gate, the regression call,
> and what Dart persists; then [prediction-2.md](prediction-2.md) for measured sensitivity
> and the `cm_per_px_target` calibration problem.
