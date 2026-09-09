# Phase 7 — The cutter, measured rather than assumed

Status: in progress

New items number from **F36**; F1–F35 are taken.

This phase exists because F31 (phase 4) reached the wrong conclusion by approximating the
cutter instead of running it. The real cutter was then run, and it reverses that conclusion
and most of what phase 6 inferred from it. Read this phase before acting on anything in
phase 4 or 6.

## The experiment F31 should have been

`ML/pipeline/cutter.py` is the research protocol's head/neck removal — 11,020 lines, and the
one stage [ADR-001](../adr/001-cutter-identity-stub.md) permanently declines to port to C++
because it depends on `scipy.signal.find_peaks`, `scipy.ndimage.gaussian_filter1d` and
`skimage.morphology.skeletonize`. **It runs in this environment** (scipy 1.18.1, skimage
0.26.0). The C++ port is blocked; the Python reference never was. Entry point is
`isolate_body_only_mask(mask, sample_id=...)`, and the body mask comes back under the key
`mask` — not `body_mask`, which is what an earlier attempt looked for and gave up on.

## F36 — the identity cutter accounts for essentially the whole field bias

Measured on the regressor's own eval set (`ML/weight_prediction/fixed_test_predictions_POSTHOC.csv`)
by replacing the post-cut `RA` with the pre-cut one — `whole_mask_area_px / 720²`, which is
exactly what the shipped app computes — and leaving the shape features alone:

| | MAE | mean bias |
|---|---|---|
| properly cut (research protocol) | 4.94 kg | −1.83 kg (−1.0%) |
| identity stub (what ships today) | 19.96 kg | **+17.37 kg (+16.6%)** |

Device-observed bias across the three field photos was +20.8%, +17.7% and +9.2% — mean
**+15.9%**. Predicted from the missing cutter alone: **+16.6%**. The match is close enough
that the cutter is no longer a hypothesis competing with others; it is the explanation.

This also confirms the model itself is healthy: 4.94 kg MAE with a proper cut matches the
~4.3 kg the team quotes for this regressor. Note the eval set is **15 distinct animals**
across 2014 images, so that MAE is per-image, not per-animal — treat it as a floor, not a
guarantee on unseen pigs.

## F37 — F31 is retracted

Phase 4's F31 concluded the cutter could not explain the bias, because applying the training
set's median area-removal fraction (10.8%) to the harness's `RA` overcorrected two of three
photos. That method was wrong in two ways: the real cutter removes a **photo-specific**
fraction, not a constant one (2.7%, 14.0% and 14.2% on these three masks), and the flat
fraction was applied to whichever harness mask happened to exist rather than to the mask the
device actually produced. Running the real cutter on the same masks:

| Photo | true | app today (uncut) | real cut | area removed |
|---|---|---|---|---|
| 92 kg | 92 | 90.0 kg (−2.1%) | **94.5 kg (+2.8%)** | 6.9% |
| 96 kg | 96 | 110.3 kg (+14.9%) | **89.9 kg (−6.3%)** | 14.0% |
| 118 kg | 118 | 107.7 kg (−8.7%) | 81.1 kg (−31.3%) | 14.2% |

Two of three land inside the model's own 4.94 kg MAE band. The 118 kg row is **confounded and
should not be read as a cutter result**: the harness cannot detect that photo at rung 0, so
this used its rung-1 mask, while the device detects at rung 0 and reported `RA = 0.12103`
against the harness's `0.09479`. Those are different masks of the same animal — see F39.

## F38 — `cm_per_px_target = 0.35` is approximately right, and ADR-004's premise is not

`RA` correlates with weight at **r = 0.980** across the eval set, so the training data can say
what `RA` a pig of known weight should produce. Placing the post-cut field masks against it:

| Photo | field `RA` (cut) | training median at that weight | delta | implied `cm_per_px_target` correction |
|---|---|---|---|---|
| 92 kg | 0.08237 | 0.08087 (IQR 0.07843–0.08432) | +1.8% | ×0.991 |
| 96 kg | 0.08102 | 0.08589 (IQR 0.08315–0.08865) | −5.7% | ×1.030 |

Both within ~3% of the current value, and the 92 kg photo sits inside the training IQR. The
four rounds of belief that this constant was badly miscalibrated were an artifact of measuring
it with **uncut** masks, where the head and neck inflate `RA` by a photo-dependent amount that
no single constant can absorb.

[ADR-004](../adr/004-calibration-requires-repeat-captures.md) is therefore half right and half
wrong. Its rule — calibration constants come from repeat captures with a stated spread, never
single-scan fits — still stands, and F34's ±10.7% session-to-session variance is unchanged.
Its stated *premise*, that `cm_per_px_target` is an unmeasured value badly in need of
replacement, does not survive F38. ADRs are immutable and belong to `pipeline-docs`: this
needs a superseding **ADR-005**, not an edit. Flagged here, not written here.

## Steps

- [ ] **F39 — explain the 118 kg mask, now the largest single unknown.** The device reports
      `RA = 0.12103` at ladder rung 0; the harness reports no detection at that rung at all and
      `0.09479` at rung 1. That is a 28% area difference on one animal, which at the measured
      elasticity is worth roughly 40% of predicted weight. F35 already established the
      harness's detection step is unfaithful; this quantifies what that costs. Until it is
      settled, no field number from the 118 kg photo should be used as evidence for anything.
- [ ] **F40 — decide how the cutter reaches the device.** Three options, all real:
      port the 11,020 lines to C++ against ADR-001's stated objection; run the Python cutter
      off-device as a service; or reduce the protocol to a portable subset and accept measured
      error against the full one. The team member finalising the cutter file owns this
      decision — F36 gives it a budget: the stage is worth ~15 kg of mean bias, so almost any
      implementation cost is justified, but a *wrong* port is worth the same amount in the
      other direction.
- [ ] **F41 — re-verify F36 end to end once the cutter is on-device.** The +16.6% figure is
      measured by feature substitution, not by running the app. Confirm against real scans
      before treating the branch as fixed, and expect the residual to be the ±10.7% capture
      noise F34 measured, not zero.
- [ ] **F29 and F32 carry forward from phase 4**, both unchanged and both lower priority than
      they looked before F38.

## What did not change

F30 (the extractor and regressor are correct), F33 (harness and device agree on features
within 2%), F34 (capture-to-capture noise of up to 10.7%) and F35 (the harness's detection
step is unfaithful) all stand as measured. What changed is their weight in the explanation:
F34 is real but secondary, and the systematic bias it was invoked to explain is now accounted
for by F36.
