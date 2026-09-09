# Phase 3 — Round-4 verification on device

Status: done

The device run happened. Round 4's availability goal is met; its accuracy goal is not. This
file is now the record of that verdict. All remaining work moved to
[4-ra-dominance.md](4-ra-dominance.md).

Source of the device numbers: `docs/logs/ref_log.md`, "Weight Mismatch" section — an APK
built from the round-4 tree (`c198456`) and run on the user's own phone against the same
three `.pig_pictures/` photos.

## Result

| Photo | True | Device | Error | Harness, same manifest | Device − harness |
|---|---|---|---|---|---|
| `96kg_pig_porac_stick` | 96 kg | 116.0 kg | +20.8% | 110.3 kg (+14.9%) | +5.7 kg |
| `92kg_pig_meter_stick` | 92 kg | 108.3 kg | +17.7% | 90.0 kg (−2.1%) | +18.3 kg |
| `118kg_pig_porac_stick` | 118 kg | 128.8 kg | +9.2% | 107.7 kg (−8.7%) | +21.1 kg |

The `cm_per_px` the device derived from the marked reference (0.0634 / 0.0648 / 0.0652)
matches the values the harness assumes to within 0.2%, and the reference-object pixel lengths
(2065 / 1543 / 2008) match the harness's working resolution. The divergence is not in the
reference measurement and not in the capture resolution.

## Against round 4's acceptance criteria

- **All three photos produce a weight.** Pass. This is the round's real win: F18's
  scale-aware canvas, F19's ladder and F23's diagonal threshold together removed every
  "weight branch unavailable" rejection. The user reports no unavailable pigs since.
- **Predictions within ±20% on all three, and within ±10% on at least two.** Fail on both
  clauses — +20.8% breaches the outer bound, and only one photo (+9.2%) is inside ±10%.
- **Mask bbox diagonal ≥ 0.55 on all three.** Not evaluated: the persisted `segmentation`
  event was not read off the device. The harness measures 0.72 / 0.62 / 0.72.
- **`candidates_kept`, `ladder_rung`, `content_scale` present in the persisted event.** Not
  evaluated, same reason. F20 shipped the write; nobody has read it back yet.
- **Non-acceptance — the 96 kg control must not regress.** Pass. It read 139.3 kg (+45.1%)
  before round 4 and 116.0 kg (+20.8%) after. Worse than the target, better than before.

## What this phase established, beyond the pass/fail

Three findings from the harness runs made while judging this result. They are the substance
of round 5 and are written up with their measurements in
[4-ra-dominance.md](4-ra-dominance.md); named here so this file is a complete record.

1. **The harness does not reproduce the device.** Same photos, same manifest, same ladder,
   same rung-selection rule — and the harness lands 5.7 to 21.1 kg below the app on every
   photo, in the same direction each time. Every number in phase 1 and every constant fitted
   in phase 2 came from this harness. Until the gap is explained, the harness is a tool for
   understanding the model, not for calibrating the app.
2. **`cm_per_px_target` cannot be fitted.** Sweeping it from 0.28 to 0.52 at each photo's
   selected rung produces a jagged, non-monotone response — the 118 kg photo reads 103.6 kg
   at 0.32, 107.7 at 0.35, 82.6 at 0.38 and 112.0 at 0.41. F21's move from 0.26 to 0.35 was
   fitted on this surface and did not survive contact with the device.
3. **The regressor is very nearly a function of `RA` alone.** Holding the other four features
   at the midpoint of their trained ranges and sweeping each in turn across its full range:
   `RA` moves the prediction 72.6 → 171.2 kg, while `LC` moves it 5.6 kg, `BW` 4.2 kg, `E`
   11.9 kg, and `BL` −21.8 kg. `RA` carries the entire output range and the shape features
   carry almost nothing.

## F24 — closed

The round-4 `RA` discrepancy (harness 0.00728 against the app's 0.00086 on the 118 kg photo)
is closed by inspection of `pipeline.cpp:542` and `feature_calculation.cpp:35`: `RA`'s
denominator is `manifest.weight.training_frame_px` when `scale_ok` and the mask's own
dimensions otherwise, exactly as suspected. The 0.00086 was recorded on a build where the
scale branch had failed, so the denominator was the full captured frame rather than 720×720.
With `scale_ok` true on every scan in this run, both sides now use the same denominator, and
the device and harness `RA` values are within the same few percent as the other features.

This closes F24 as a reporting artefact, not a defect. Note that it does **not** explain the
device-vs-harness weight gap in the table above — see finding 1.

## F25, F26 — still open, carried forward

Both need the persisted telemetry that this run wrote and nobody read. They move to phase 4
unchanged: F25 is orientation sensitivity, F26 is whether the ladder papers over segmenter
brittleness.
