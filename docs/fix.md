# Fix: the weight branch overestimates, because the mask it measures still has the head on it

Active fix document, now in round 5. Numbering continues at **F42** — never reuse F1–F32, or
the source comments citing them start pointing at the wrong thing.

Source material: `docs/logs/ref_log.md` (the device scan log, including the round-4 "Weight
Mismatch" results), and the round-1–4 write-ups that were previously at the repository root.
Rounds 2 (F6–F11), 3 (F12–F17) and 4 (F18–F23) are all applied and in the working tree.

## Symptom

Three field photos with a marked reference object, of pigs whose true weights are known
(92 kg, 118 kg, 96 kg).

**Before round 4:** two were rejected outright and the third predicted 141.1 kg for a 96 kg
animal. The rejection messages named the reference object, which was correctly marked in
every case — `cm_per_px` came out at 0.0633–0.0653 on all three, a spread of under 3%.

**After round 4, measured on device:** every photo now produces a weight and the user reports
no "weight branch unavailable" rejections since. All three overestimate — 96 kg reads
116.0 kg (+20.8%), 92 kg reads 108.3 kg (+17.7%), 118 kg reads 128.8 kg (+9.2%). The
availability goal is met; the ±20%/±10% accuracy goal is not.

Round 5 diagnosed it. The regressor turns out to be very nearly a function of `RA` alone — the
mask's area over a fixed 720×720 frame — and the app measures `RA` on a mask that still has
the pig's head and neck attached, because the shipped cutter is an identity stub. Measured on
the regressor's own eval set, that single omission is worth **+16.6%** of mean bias against
the **+15.9%** observed on the phone.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Diagnosis (rounds 1–4) | done | [fix-phase/1-diagnosis.md](fix-phase/1-diagnosis.md) |
| 2 | Applied changes (F18–F23) | done | [fix-phase/2-applied-changes.md](fix-phase/2-applied-changes.md) |
| 3 | Round-4 verification on device | done | [fix-phase/3-open-verification.md](fix-phase/3-open-verification.md) |
| 4 | RA dominance and the squared calibration error | done (F31 retracted) | [fix-phase/4-ra-dominance.md](fix-phase/4-ra-dominance.md) |
| 5 | F27 telemetry retrieval (debug build + adb run-as) | done | [fix-phase/5-telemetry-retrieval.md](fix-phase/5-telemetry-retrieval.md) |
| 6 | F28: reading the device telemetry | done (partly superseded) | [fix-phase/6-device-telemetry-findings.md](fix-phase/6-device-telemetry-findings.md) |
| 7 | The cutter, measured rather than assumed | in progress | [fix-phase/7-cutter-quantified.md](fix-phase/7-cutter-quantified.md) |

**Start at phase 7** — it carries the current explanation and retracts F31, which phases 4 and
6 had built on. Phase 5 is the completed telemetry runbook. Phases 1–3 are the record of what
was established and shipped.

## Root cause

Rounds 1–4 fixed two stacked defects, each of which hid the other, and both fixes hold:

1. **The segmenter was run at an input scale at which it does not detect a pig.** Fixed by
   F18's scale-aware canvas and F19's retry ladder. Phase 1 has the detection sweep.
2. **`cm_per_px_target` was far enough off that a correct mask still produced a feature
   vector above the regressor's trained maximum.** F21 re-fitted it from 0.26 to 0.35.

Round 5's cause is that fix 2 was the wrong kind of fix, and phase 4 has the measurements:

3. **The regressor is a one-feature model and that feature is a squared calibration term.**
   Sweeping each feature across its full trained range with the others held at midpoint,
   `RA` moves the prediction 98.6 kg while `BL`, `E`, `LC` and `BW` move it 21.8, 11.9, 5.6
   and 4.2 kg. `RA` is mask area over a fixed 720×720 frame, and the mask is resampled by
   `k = cm_per_px_actual / cm_per_px_target`, so `RA` scales with `k²`. At the measured
   elasticity of 1.4–2.0, **a 1% calibration error is a 2.8–4.0% weight error.**
4. **`RA` is therefore the whole model, and it is inflated by the head and neck.** The
   shipped cutter is an identity stub ([ADR-001](adr/001-cutter-identity-stub.md)), so every
   feature vector the app produces is measured on an uncut mask.

5. **The extractor and regressor are not the bug (F30).** Fed all 2014 rows of
   `ML/weight_prediction/fixed_test_predictions_POSTHOC.csv` — real training-protocol masks,
   real cut, real measured weight — the manifest's `xgboost.onnx` reproduces that file's own
   `prediction` column to within 0.00019 kg and scores −1.0% mean bias / 4.94 kg MAE against
   true weight. That matches the ~4.3 kg the team quotes for this model.
6. **The missing cutter accounts for essentially the entire field bias (F36, phase 7).**
   Re-running the same 2014 rows with `RA` taken from `whole_mask_area_px` — exactly what the
   app computes — moves MAE from 4.94 kg to **19.96 kg** and mean bias to **+16.6%**. Observed
   device bias across the three field photos was **+15.9%**. Running the real
   `ML/pipeline/cutter.py` on the field masks brings the 92 kg photo to +2.8% and the 96 kg
   photo to −6.3%, both inside the model's own MAE band.
7. **`cm_per_px_target = 0.35` is approximately right after all (F38).** Measured against
   post-cut masks it sits within ~3% of what the training data implies (`r(RA, weight) =
   0.980`). Four rounds of believing it badly miscalibrated were an artifact of measuring it
   with uncut masks. [ADR-004](adr/004-calibration-requires-repeat-captures.md)'s *rule* still
   holds; its stated premise does not, and needs a superseding ADR-005 from `pipeline-docs`.

## Change made

Nothing new is applied this round. Round 4's F18–F23 remain in the working tree and are not
being reverted — they are what made the branch available, which is real progress and is
confirmed on device. F24 is closed as a reporting artefact (phase 3).

Round 5 deliberately writes no source code. The diagnosis is now complete and points at one
stage — the cutter — whose port is owned by another team member and is being finalised. There
is no constant left worth fitting: F38 shows the one that four rounds chased is already close,
and F36 shows what actually costs the 15 kg.

## Verification

**Closed:** F24 (phase 3), F27 (phase 5), F28, F33–F35 (phase 6), F30, F36, F37, F38
(phases 4 and 7). **F31 is retracted** — it concluded the cutter could not explain the bias by
approximating it with a flat area fraction instead of running `ML/pipeline/cutter.py`. Phase 7
carries the correction and the numbers.

The diagnosis is complete. The remaining work is a port decision and an on-device
re-verification, not further investigation:

- **F39** — the 118 kg photo's mask is still unexplained: the device reports `RA = 0.12103` at
  ladder rung 0 where the harness reports no detection at all and `0.09479` at rung 1. A 28%
  area difference on one animal, worth roughly 40% of predicted weight. Until it is settled, no
  field number from that photo is evidence for anything.
- **F40** — decide how the cutter reaches the device: port the 11,020 lines against ADR-001's
  stated objection, run it off-device, or reduce it to a portable subset with measured error.
  Owned by the team member finalising the cutter. F36 sets the budget: the stage is worth
  ~15 kg of mean bias in either direction.
- **F41** — re-verify F36 end to end once the cutter is on-device. The +16.6% figure comes from
  feature substitution, not from running the app. Expect the residual to be F34's ±10.7%
  capture noise, not zero.
- **F29** (`cm_per_px_target` derivation) and **F32** (ladder rung selection) carry forward,
  both lower priority after F38. **F25** (orientation) stays blocked — F20 never persisted
  orientation, so there is no field to read.
- **ADR-005 is needed** to supersede ADR-004's premise. That is `pipeline-docs`' file, not this
  skill's — flagged, not written.

`docs/changelog.md` gets no entry yet: the contract is one line per **closed-out** fix, and
this fix stays open until the cutter ships and F41 verifies it.
