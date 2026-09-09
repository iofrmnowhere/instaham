# Weight Prediction — Practical Calibration Guidance

Continuation of [prediction-2.md](prediction-2.md), which carries the measurements these rules
are drawn from. Read that file first; this one is only the standing conclusions.

## Practical guidance

- Do not tune `cm_per_px_target` against a small set of field photos. It has now been done
  three times — 0.26, then 0.35 (both fitted), then the specification's theoretical 0.3289
  (F46, measured on device against all three photos). None of them survived contact with a
  device, and the constant was not the problem any of those times.
- **The constant is settled at 0.35 on measurement, and is still not derived.** The host
  harness in `ML/host_scale_test/` swept 0.28–0.50 against five PIGRGB images with known true
  weights, using the shipped models and the real cutter
  ([../scale-constant-sweep-results.md](../scale-constant-sweep-results.md)): 0.35 won on MAE
  (11.5% vs 0.3289's 19.0%) and on every image individually, so it ships. Three criteria still
  give three different optima — MAE at 0.35, |bias| at 0.38, spread at 0.30 — which is the
  signature of a constant that is not the dominant error term. Do not read the win as validation.
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
