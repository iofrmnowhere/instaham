# Weight Prediction

Stages 3–5 of the `dorsal_valid` route: cutter (`src/stages/cutter.cpp`), feature calculation
(`src/stages/feature_calculation.cpp`), weight prediction (`src/stages/weight_prediction.cpp`),
with the scale and gating logic in `src/pipeline.cpp`.

Everything here is downstream of a constructed mask — see [segmentation.md](segmentation.md).
This branch is independent of health: it may fail at any of the six checks below without
affecting `envelope["health"]`.

## Order of checks

Each check either passes or writes `envelope["weight"]` and stops. None is skippable.

1. **Mask plausibility.** `mask_diagonal_fraction` — mask bbox diagonal over image diagonal —
   must reach `weight.min_mask_diagonal_fraction` (0.35). Measured on the raw captured mask
   before normalization, since resampling changes absolute size, not a mask's proportion of
   its own frame. Runs *before* the cutter so a sliver mask never reaches the feature stages.
   Eccentricity alone cannot catch it: a thin sliver scores **high** on E, not low.
   Failure → `reason: mask_implausibly_small`.
2. **Weight capability available.** Manifest `weight.available` plus a loaded regressor.
   Failure → `weight_capability_unavailable`.
3. **Reference confirmed.** `cm_per_px` present, finite, positive. There is no implicit
   `k = 1.0`. Failure → `reference_object_not_confirmed`.
4. **Camera height in range** (below). Failure → `scale_out_of_range`.
5. **Resample succeeded.** Failure → `scale_resample_failed`.
6. **Feature domain** (below). Failure → `mask_shape_out_of_domain`,
   `subject_smaller_than_trained`, or `features_out_of_training_domain`.

Every rejection carries its own `reason` plus a `user_message_key`, and
`envelope["scale"]["reason"]` and `envelope["weight"]["reason"]` read the same variable, so
they cannot disagree. Collapsing these into one generic message once told a user with a
correctly-marked reference to go mark a reference object.

## Scale normalization

`k = cm_per_px_actual / weight.cm_per_px_target` (target 0.35 cm/px). The mask is resampled by
`k` with `scale_mask_to_training_space()` into the pixel space the regressor's features were
measured in, so the cutter's thresholds and RA's denominator both operate in the training
space. Nearest-neighbour, matching construction's own unletterbox resize — the mask stays
binary. A non-finite or non-positive `k` returns an empty mask, never an unscaled copy.

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
`implied_camera_height_m`, `training_frame_px`, and `source: user_confirmed_reference`.

## Cutter — a permanent identity stub

`cut_body_mask()` returns the mask unchanged, with `head_removal_applied = false` and
`status = "identity_stub"`. Settled, not pending: see
[../adr/001-cutter-identity-stub.md](../adr/001-cutter-identity-stub.md).

The consequence propagates. A weight computed from an uncut mask includes the head and neck
and is therefore **not** a valid estimate under the research protocol. `envelope["cutter"]`
always reports `protocol_implemented: false` alongside the protocol version, and any
`estimated_kg` downstream carries an explicit `note` saying it overestimates.

## Feature calculation — baseline5

`extract_five_features()` cleans the mask (`largest_component_fill` when the cutter already
cleaned it, else `clean_binary_mask`), takes the largest external contour, and returns
`std::nullopt` when that contour has fewer than 5 points — `fitEllipse` needs 5, and the
Python reference returns `None` at the same boundary.

| Feature | Definition | Scale behaviour |
|---|---|---|
| `RA` | `area_pixels / (frame_w * frame_h)` | Ratio; invariant to a uniform resize of mask **and** frame together, so it does not correct for camera height on its own |
| `LC` | contour arc length × `linear_scale` | Length |
| `BL` | longer side of `minAreaRect` × `linear_scale` | Length |
| `BW` | shorter side of `minAreaRect` × `linear_scale` | Length |
| `E` | `sqrt(1 - (minor/major)^2)` of `fitEllipse` | Scale-invariant shape |

With a scale established the mask is already in training pixels, so `linear_scale` stays 1.0
and RA's denominator is the manifest's 720×720 training frame. Without a scale the denominator
falls back to the mask's own dimensions, reproducing the pre-normalization provisional values.
`envelope["features"]["measured_on"]` says which (`training_normalized_mask` or
`uncut_mask_unnormalized`), and the block is labelled `status: provisional` either way.

Only `baseline5` is implemented. `chen16` stays reference-only in Python — it needs
`skimage.morphology.skeletonize`, which this build does not carry.

## Domain gate

The real question a sanity check should ask is whether the trained regressor has ever seen a
vector like this one. `weight.feature_domain` records the `[min, max]` each feature actually
took across the regressor's own 2014-row training/eval set, plus per-feature
`upper_multiplier` / `lower_multiplier` that widen the bounds enough to admit an uncut mask.

Bounds widen further by `cm_per_px_target_uncertainty` (1.30, clamped to ≥ 1.0 at load so a
malformed value can only widen), raised to each feature's dimensionality: squared for the area
ratio RA, first power for the lengths LC/BL/BW, untouched for the scale-invariant E. The gate
is never stricter than the calibration it rests on. A feature whose manifest `max` is ≤ 0 has
no data and is skipped rather than rejecting everything.

All five are checked with bitwise `&`, deliberately not `&&`, so every violation is recorded
instead of short-circuiting after the first. `classify_domain_violation()` names the cause:

- **Any `E` violation → `mask_shape_out_of_domain`**, even when size features also violated.
  A broken mask drags the size features off as a side effect of being the wrong shape; the
  shape violation is the cause, not a co-symptom to be outvoted.
- **Size features only, all low → `subject_smaller_than_trained`.** Smaller than anything in
  the regressor's 87–192 kg eval set.
- **Anything else → `features_out_of_training_domain`.** A high size violation is the one case
  a mis-marked or mis-scaled reference plausibly explains.

`envelope["weight"]["violations"]` carries the machine-readable list (`feature`, `value`,
`allowed_min`, `allowed_max`, `direction`); `detail` carries the readable one.

## Regression

`predict_weight()` is nothing more than "run that ONNX graph": input shape `[1,5]`, features in
exactly `RA, LC, BL, BW, E`. That order is asserted three times — at export against
`BASELINE5`, at manifest load against `feature_order.json`, and here in the packing — and a
manifest whose order disagrees fails to load with `INSTAHAM_ML_ERR_CONTRACT`.

After a successful run each size feature is re-checked against its **unwidened** trained
`[min, max]`. The widened bounds exist to admit an uncut mask, but a gradient-boosted
regressor cannot extrapolate: a vector past the raw max is answered from an edge leaf, a real
and silent ceiling. Those features are listed in `extrapolated_features` with
`extrapolated: true`, rather than presenting a saturated value with the same confidence as an
interpolated one.

`envelope["weight"]` on success: `estimated_kg`, `protocol_implemented: false`, `extrapolated`,
`extrapolated_features`, the uncut-mask `note`, and `capture_contract` (`feature_space:
fixed_camera_pixels`, `training_camera_height_m: 1.88`,
`camera_height_is_xgboost_feature: false` — camera height is a capture constraint, not a model
input).
