# Phase 6 — F28: reading the device telemetry

Status: done

> **Superseded in part by [phase 7](7-cutter-quantified.md).** F33, F34 and F35 below stand
> as measured. What changed is their role: this phase treated capture noise (F34) as the main
> story because F31 had wrongly ruled the cutter out. F36 shows the missing cutter accounts
> for the systematic bias, and F34 is the secondary residual. Read phase 7 first.

F27's pull (`instaham.sqlite`, debug build, `2026-09-05`) read directly with `sqlite3` —
`pipeline_events` (11 rows per scan: `capture, capture, view, reference_review, analysis,
scale, health, segmentation, construction, features, weight`) and `weight_results` (the exact
value shown on screen, plus the feature vector that produced it). New items number from
**F33**; F1–F32 are taken.

## What F28 actually found

Not the clean single-cause answer phase 4 was hoping for. Two separate effects were tangled
together in the "5.7–21.1 kg device-vs-harness gap" from phase 3, and pulling real device
features separates them.

### F33 — harness and device agree on features, once both see the same photo

Comparing the harness's rung-0 (`T=1.10`) feature output against this debug run's actual
on-device features, photo by photo:

| Photo | harness `RA` | device `RA` | Δ | harness `LC/BL/BW/E` | device `LC/BL/BW/E` |
|---|---|---|---|---|---|
| 92 kg | 0.0885 | 0.0897 | +1.4% | 1159 / 403 / 151 / 0.948 | 1185 / 412 / 151 / 0.948 |
| 96 kg | 0.0942 | 0.0958 | +1.7% | 1299 / 464 / 148 / 0.960 | 1316 / 470 / 148 / 0.960 |

All four shape features agree within 2% on both photos. This is close, not the double-digit
gap phase 3 reported — because phase 3's "device" number was the **release build's** total
predicted weight, not a feature-level comparison. At the feature level the harness has always
been a reasonable model of the native pipeline; what it cannot be trusted for is described
below.

Also confirmed, as a byproduct: `onnx_offline(device_features) == device_app_weight` to the
last displayed digit on all three photos. The native ONNX runner and the manifest's
`xgboost.onnx` agree exactly — F30's finding (the regressor is not the bug) extends cleanly to
the on-device runtime, not just the Python harness.

### F34 — the debug and release builds disagree with each other, on the same photos, by up to 11%

This is the finding the phase 5 runbook warned about at step 5, and it happened:

| Photo | release build (`ref_log.md`, "Weight Mismatch") | this debug build | Δ |
|---|---|---|---|
| 92 kg | 108.3 kg | 96.7 kg | **−10.7%** |
| 96 kg | 116.0 kg | 108.5 kg | **−6.5%** |
| 118 kg | 128.8 kg | 129.1 kg | +0.3% |

Reference-marking precision is not the explanation — the two sessions' measured `cm_per_px`
agree to within 0.2–0.7% on all three photos (92 kg: 0.0648 vs 0.06466; 96 kg: 0.0634 vs
0.06384; 118 kg: 0.0653 vs 0.06504), which is far smaller than the weight divergence. The
divergence has to be in the segmentation mask itself: a re-photographed scene, even of the
same pig and stick, does not produce a pixel-identical mask, and at the elasticity phase 4
measured (1.4–2.0), a few percent of mask-boundary difference is enough to move the weight
several kilograms — before any build difference is even considered.

**Consequence:** two of the three "Weight Mismatch" numbers this whole round was diagnosing
cannot be reproduced on demand, even by the same phone, the same user, and the same physical
setup. Any fix tuned against the exact release-build numbers (108.3 / 116.0 / 128.8) is
tuning against one noisy sample of a distribution, not a fixed target.

### F35 — the harness's segmenter reproduction is not reliable for detection, only for measurement

The device detected the 118 kg pig at rung 0 (`T = 1.10`, confidence 0.92, `ladder_rung: 0`)
on **both** sessions (release: rung info not logged pre-F20; debug: confirmed above). The
harness's Python reimplementation reports **no detection at all** at the same `T = 1.10` for
the same photo (phase 3, phase 4's ladder table). F33 shows the harness's feature math is
trustworthy once a mask exists; F35 shows its detection behavior is not — likely from the
harness's own preprocessing (`load()` re-encodes through a JPEG round-trip at quality 92 and
caps at 3000 px before feeding the segmenter, which the native decode path does not do).

**Practical effect:** all three real-device scans landed on `ladder_rung: 0` — the ladder's
default rung, no retry needed. F26's worry (the ladder papering over segmenter brittleness)
is not confirmed by this data; if anything it argues the native segmenter is more robust at
`T = 1.10` than the harness suggested. Three scans is still a small sample.

## F28 — closed, with a revised conclusion

The original framing — "explain the 5.7–21.1 kg device-vs-harness gap" — assumed a single
gap with a single cause. There is no such gap once harness and device are compared on the
same photo set (F33: ≤2% on features). What phase 3 actually measured was release-build
noise (F34) layered on top of a harness whose detection step, not its measurement step, is
unreliable (F35). Both are now understood; neither is a coding bug to fix.

## F25 — orientation sensitivity: still open

Nothing in this telemetry pull settles it. F20 does not currently persist EXIF orientation or
the `irot` handling path, so there is no field to read. Left open; would need a manifest/code
addition to log orientation before the next device run, which is out of scope for a read-only
telemetry pull.

## F26 — ladder brittleness: leaning "not confirmed," sample too small

See F35. All three real scans used rung 0. This is evidence toward "the constant is right,"
not against it — but three data points from one photographer, one phone, one sitting is the
same small-sample caveat phase 2 already flagged. Keep watching `ladder_rung` as real scans
accumulate; do not close this on three points.

## What this means for F29, F31, F32

- **F29 (`cm_per_px_target`)** — unaffected by F33/F34/F35, but later revised by
  [F38 in phase 7](7-cutter-quantified.md): measured against post-cut masks the current 0.35
  is within ~3% of what the training data implies, so this is far less urgent than it looked
  here. The 1.88 m capture is still the only way to retire the uncertainty margin.
- **F31's conclusion does NOT hold — see [phase 7](7-cutter-quantified.md), F37.** This
  bullet originally reasoned from F31's refutation of the cutter hypothesis. That refutation
  was wrong. F34's caution about fitting against single scans still applies; the conclusion
  that the cutter is not the explanation does not.
- **F32 (ladder rung selection)** — F35 suggests the current first-past-threshold rule is
  performing fine on this evidence (all three at rung 0), but three points is not enough to
  redesign or to declare it safe. No action taken.

## Recommended next step: repeat capture, not more code

Every constant-fitting round so far (F21, and the F31/F34 findings above) has been limited by
having exactly three photos, each captured once. The single highest-leverage next step is not
a code change: **re-capture each of the three reference photos two or three more times**,
phone in roughly the same position, and log the resulting weights and `RA` values. That
directly measures the capture-to-capture noise floor from F34, which every future calibration
number (F29's 1.88 m capture included) needs to be judged against. This does not require the
cutter to be finished and does not touch code.
