# Weight Prediction — Practical Calibration Guidance

Continuation of [prediction-2.md](prediction-2.md), which carries the measurements these rules
are drawn from. Read that file first; this one is only the standing conclusions.

## Practical guidance

- Do not tune `cm_per_px_target` against a small set of field photos. It has been done
  four times — 0.26, then 0.35 (both fitted), then the specification's theoretical 0.3289
  (F46, measured on device against all three photos), now 0.34. None of the first three survived
  contact with a device, and the constant was not the problem any of those times. What makes
  0.34 different is *agreement between two corpora*, one of which the regressor never trained on,
  against a ported cutter — not a better fit on one set of photos.
- **The constant ships measured, and the plateau matters more than the minimum.** The manifest
  carries **0.34**, the MAE minimum of round 28's host sweep on both corpora independently —
  corpus B (`PIGRGB-Weight/sub_1.88/`, 4 informative rows) 2.1% with +0.2% bias, corpus A
  (`.pig_pictures/`, 3 rows) 4.0% — against 4.1%/7.4% at the fitted 0.35 and 5.4%/7.7% at the
  derived 0.3289473684210526 ([ADR-012](../adr/012-measured-scale-target.md),
  [../scale-constant-sweep-results-2.md](../scale-constant-sweep-results-2.md)). The response
  through 0.32–0.36 is a shallow bowl: staying inside that band is worth tens of points of MAE,
  choosing a point within it a few. **Quote these as host figures over seven rows, corpora
  reported separately — never as device numbers**, and note that corpus B is the regressor's own
  training distribution, so its agreement is partly memorisation.
- **A `k = 1.0` arm bounds what this constant can ever fix.** Setting the target to corpus B's
  own `cm_per_px_actual` makes the resample step a proven no-op (`mask_area_px` unchanged, not
  merely close) and still leaves 5.42% MAE, +5.35% bias, one image at +14.29%. That error is
  segmentation, the cutter, feature extraction, the regressor or the 304 px/m geometry — not
  scale. Read any constant comparison against this floor, not against zero, and do not spend
  another round on the constant expecting to clear it.
- The superseded [../scale-constant-sweep-results.md](../scale-constant-sweep-results.md) (MAE
  11.5% vs 19.0%) measured the pre-F55 double-rasterisation path over the retired `sub_1.78/`
  corpus, and its three disagreeing optima (MAE at 0.35, |bias| at 0.38, spread at 0.30) remain
  the signature of a constant that is not the dominant error term. Do not cite its numbers.
- **Below roughly 85 kg, no calibration change will help.** The regressor cannot emit a value
  under about 73 kg; light pigs fall outside its trained feature domain and answer from a floor
  leaf ([ADR-010](../adr/010-regressor-training-domain-floor.md)). Check `extrapolated_features`
  before attributing a low-end error to scale, the cutter, or marking noise.
- **Use the host harness, not a sideload, for the next constant question.** It runs the app's
  own stage sources against the shipped models and is byte-reproducible, which is what made the
  above measurable at all; `ML/host_scale_test/README.md` carries the commands.
- Judge any calibration change against repeat captures with a stated spread, never a single scan
  per photo ([ADR-004](../adr/004-calibration-requires-repeat-captures.md), ±10.7% capture noise;
  F53 adds a 5–13% marking band on top, photo-dependent).
- Do not adjust constants to compensate for a pipeline stage. That is what the round-4 retune
  attempted, and it is why the constant appeared miscalibrated for four rounds. F46 is the
  cleanest statement of the limit: both candidate constants are wrong on all three photos in the
  same direction as each other's mirror image, which is what a stage defect looks like from the
  constant's side.
- Per-feature sensitivity has **not** been re-measured for `chen16_noheight`. The old
  "one-feature model" table (`RA` spanning 98.6 kg of a 95–175 kg output range, the other four
  features under 22 kg each) described `baseline5` and does not carry over to 16 features.
