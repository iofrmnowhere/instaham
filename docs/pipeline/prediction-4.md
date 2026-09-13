# Weight Prediction — Practical Calibration Guidance

Continuation of [prediction-2.md](prediction-2.md), which carries the measurements these rules
are drawn from. Read that file first; this one is only the standing conclusions.

## Practical guidance

- Do not tune `cm_per_px_target` against a small set of field photos. It has now been done
  three times — 0.26, then 0.35 (both fitted), then the specification's theoretical 0.3289
  (F46, measured on device against all three photos). None of them survived contact with a
  device, and the constant was not the problem any of those times. The value shipping today is
  derived rather than fitted, which is the only reason it is not a fourth instance of this.
- **The constant now ships derived, not fitted, and its accuracy is unmeasured.** The manifest
  carries `0.3289473684210526` = `100 / 304`, from the PIGRGB floor-plane baseline in
  [../INSTAHAM_CAMERA_SCALE_NORMALIZATION.md](../INSTAHAM_CAMERA_SCALE_NORMALIZATION.md)
  ([ADR-011](../adr/011-derived-scale-target.md)). The host sweep that previously justified
  0.35 ([../scale-constant-sweep-results.md](../scale-constant-sweep-results.md): MAE 11.5% vs
  0.3289's 19.0% over five PIGRGB images) was run before round 7's composed transform, so it
  measures a code path the weight branch no longer runs. **Nothing has re-measured either value
  on the current pipeline — do not quote an accuracy figure against the shipped constant until
  that re-run exists.** The sweep's three disagreeing optima (MAE at 0.35, |bias| at 0.38,
  spread at 0.30) remain the signature of a constant that is not the dominant error term.
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
