# Phase 4 — RA dominance and the squared calibration error

Status: in progress

Round 5. New items number from **F27**; F1–F26 are taken and source comments cite them.

Round 4 made the weight branch *available*. This phase is about why the numbers it produces
are wrong by +9% to +21%. Measurements come from
`ML/tools/replicate_native_weight_branch.py` and scratch drivers built on it against the
current manifest; device numbers from `docs/logs/ref_log.md`, "Weight Mismatch".

> **Read [phase 7](7-cutter-quantified.md) first.** The `RA`-dominance and `k²` findings below
> stand, but F31's conclusion here is retracted and the root-cause section is superseded.

## The regressor is a one-feature model

Hold four features at the midpoint of their trained ranges and sweep the fifth across its
full trained range:

| Feature | Trained range | Prediction at min → max | Span |
|---|---|---|---|
| `RA` | 0.0760 → 0.2042 | 72.6 → 171.2 kg | **98.6 kg** |
| `BL` | 312.41 → 638.02 | 168.9 → 147.1 kg | −21.8 kg |
| `E` | 0.8888 → 0.9773 | 152.5 → 164.4 kg | 11.9 kg |
| `LC` | 811.56 → 1540.29 | 155.2 → 160.8 kg | 5.6 kg |
| `BW` | 118.45 → 207.92 | 160.2 → 164.4 kg | 4.2 kg |

The model's whole output range is 95.4 kg (all min) to 175.1 kg (all max); `RA` alone spans
98.6 kg of it. The four shape features are, in practice, decoration. Local elasticity at the
three field vectors — percent weight change per percent `RA` change — is 1.40, 1.43 and 1.99.

## RA is a squared function of the calibration constant

`RA = area_pixels / (training_frame_w × training_frame_h)`
(`feature_calculation.cpp:35`, with the 720×720 denominator selected at `pipeline.cpp:542`
whenever `scale_ok`), and `area_pixels` is the captured mask resampled by
`k = cm_per_px_actual / cm_per_px_target` (`pipeline.cpp:398`, `construction.cpp:129`). Area
scales with `k²`, so

> `RA` is proportional to `(cm_per_px_actual / cm_per_px_target)²`

Combine that with the elasticities above: **a 1% error in either `cm_per_px_actual` or
`cm_per_px_target` moves the predicted weight by 2.8% to 4.0%.** A 5% calibration error is a
14–20% weight error, which is the entire size of the error we are chasing. Nothing else in
the pipeline has anything like this gain.

`cm_per_px_target` is therefore the dominant term of the model, and
`cm_per_px_target_uncertainty = 1.30` admits `RA` over a 1.69× band — most of the trained
range. (Its *value* is fine; see F38. Its gain is what matters here.)

## Why fitting cm_per_px_target cannot work

Sweeping it at each photo's selected ladder rung, holding everything else fixed:

| `cm_per_px_target` | 0.30 | 0.32 | 0.35 | 0.38 | 0.41 | 0.44 |
|---|---|---|---|---|---|---|
| 92 kg photo | 131.8 | 117.5 | 90.0 | 87.5 | 85.4 | 74.3 |
| 118 kg photo | 135.8 | 103.6 | 107.7 | 82.6 | 112.0 | 85.6 |
| 96 kg photo | 136.8 | 104.5 | 110.3 | 83.8 | 87.4 | 88.8 |

The 118 kg row goes 103.6 → 107.7 → 82.6 → 112.0 over four adjacent steps. That is not a
calibration curve; it is a gradient-boosted ensemble's leaf structure being sampled at
arbitrary points. Any value chosen from three photos on this surface is fitting noise, which
is what F21 did, and it is why F21's 0.35 read as ±15% in the harness and +9% to +21% on the
phone.

The "direction check" this section originally leaned on — that the three photos need `RA`
multipliers disagreeing in sign — was computed on **uncut** masks and is explained by
[F37/F38 in phase 7](7-cutter-quantified.md): the head and neck inflate `RA` by a
photo-specific amount. Post-cut, the constant lands within ~3% of what the training data
implies. The non-monotone surface above still stands as a reason not to fit it on three
points; the claim that it is badly wrong does not.

## The ladder injects a per-photo bias of its own

Same photo, same reference, same `cm_per_px_target`; only the segmenter's input scale differs
across F19's four rungs:

| Photo | rung 0 (T=1.100) | rung 1 (T=1.452) | rung 2 (T=1.848) | rung 3 (T=0.847) | spread |
|---|---|---|---|---|---|
| 92 kg | 90.0 | 99.0 | 88.9 | 100.7 | 13.2% |
| 118 kg | no detection | 107.7 | 110.6 | no detection | 2.7% |
| 96 kg | 110.3 | 113.6 | 114.4 | 97.9 | 16.9% |

F19 selects the *first* rung whose mask clears `min_mask_diagonal_fraction`, which is a
detection criterion, not a measurement criterion. On this evidence the rung a photo happens
to land on is worth up to 17% of the answer.

## Root cause, round 5

The weight branch is a calibration measurement wearing a regressor's clothes. `RA` carries the
prediction, `RA` is the square of the scale calibration, and that calibration rests on one
manifest constant plus whatever mask area the segmenter returns at whatever rung the ladder
stopped on. F30 confirms the regressor is not at fault, so every error is upstream of it.

The original hypothesis here — that the missing cutter alone explains the device's uniform
positive bias — **turned out to be correct**. It was F31's flawed test that appeared to refute
it, and phase 6 then built on that refutation. See [phase 7](7-cutter-quantified.md), F36 and
F37, for what actually holds. The `RA`-dominance and `k²` measurements above are unaffected and
still stand; what is superseded is the conclusion drawn from them about where the bias comes
from.

## Steps

- [x] **F30 — establish that the extractor/regressor pair is correct at all.** Closed. Fed all
      2014 rows of `ML/weight_prediction/fixed_test_predictions_POSTHOC.csv` — real
      training-protocol masks, real cut, real measured weight — the manifest's `xgboost.onnx`
      reproduces that file's own `prediction` column to within 0.00019 kg and scores −1.0%
      mean bias / 4.9% RMS against true weight. That is the model's own accuracy, not a
      pipeline defect. **The extractor and regressor are not the bug**; every error in this fix
      is upstream of them.
- [x] **F31 — quantify the cutter's contribution before building anything.** **RETRACTED —
      superseded by [F37 in phase 7](7-cutter-quantified.md).** It concluded the cutter could
      not explain the device bias. That was an artifact of method: it approximated the cutter
      by scaling `RA` with the training set's flat median area-removal fraction (10.8%) rather
      than running `ML/pipeline/cutter.py`, and applied it to harness masks. The real cutter
      removes a photo-specific fraction (2.7–14.2% on these three masks) and reverses the
      conclusion — it accounts for +16.6% of bias against +15.9% observed. Phase 7 carries the
      correct numbers; the original ones are deliberately not repeated here.

- [x] **F27 — read the persisted telemetry off the device.** Done via
      [fix-phase/5-telemetry-retrieval.md](5-telemetry-retrieval.md) (debug build + `adb
      run-as`, `instaham.sqlite` pulled 2026-09-05).
- [x] **F28 — explain the device-vs-harness gap.** Closed in
      [phase 6](6-device-telemetry-findings.md): there was no single shared-cause gap. Harness
      and device agree on features within 2% (F33); phase 3 had measured release-build capture
      noise of up to 11% (F34) plus a harness detection quirk (F35).
- [ ] **F29 — revert `cm_per_px_target` to a derived value, not a fitted one.** Lower priority
      after [F38](7-cutter-quantified.md): measured against post-cut masks the current 0.35 is
      within ~3% of what the training data implies. Still not *derivable* from this repo — no
      camera intrinsics exist in `ML/weight_runtime.py`, `ML/export/export_xgboost.py` or any
      ADR, and `export_xgboost.py:154` says as much. The 1.88 m calibration capture remains the
      only way to retire `cm_per_px_target_uncertainty`.
- [ ] **F32 — make F19's rung selection a measurement criterion, or report its spread.** The
      table above is a 13–17% ambiguity the user never sees. Not attempted: phase 2 rejected
      "largest mask across rungs" for lacking evidence, and all three device scans landed on
      rung 0 (F35), so there is still no evidence to design against.

## Carried forward unchanged

- **F25 — orientation sensitivity.** Still open. F27's telemetry doesn't answer it — F20
  never persisted EXIF orientation, so there is no field to read.
- **F26 — is the ladder papering over segmenter brittleness?** Leaning "not confirmed": all
  three real device scans landed on `ladder_rung: 0`, including the 118 kg photo, which the
  harness's own reimplementation fails to detect at that rung (F35). Three points from one
  sitting is not enough to close this either way.
- The segmenter re-export and the 1.88 m calibration capture, both from phase 2's
  out-of-scope list, are unchanged and both now look more load-bearing than they did.
