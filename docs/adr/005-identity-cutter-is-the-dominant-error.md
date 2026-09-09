# ADR-005: The identity cutter, not the scale constant, is the weight branch's dominant error

Status: Superseded by [010](010-regressor-training-domain-floor.md)

Context: [ADR-004](004-calibration-requires-repeat-captures.md) recorded a rule about how
calibration constants may be derived, and rested it on a stated premise: that
`weight.cm_per_px_target` was an unmeasured value, badly wrong, and the leading suspect for the
weight branch's field error. That premise was formed from measurements taken on **uncut**
masks, because [ADR-001](001-cutter-identity-stub.md) leaves `stages/cutter.cpp` an identity
stub and no one had run the research protocol's real cutter against field data. Two experiments
have since been run, both offline against material already in the repository. First, replacing
the post-cut `RA` with the pre-cut one — `whole_mask_area_px / 720²`, exactly what the shipped
app computes — across all 2014 rows of `ML/weight_prediction/fixed_test_predictions_POSTHOC.csv`
moves the regressor's MAE from 4.94 kg to 19.96 kg and its mean bias from −1.0% to **+16.6%**,
against a **+15.9%** mean bias observed on device across the three field photos. Second,
running `ML/pipeline/cutter.py` itself on the field masks — it executes here, scipy and skimage
are both present, and the C++ port being blocked never blocked the Python reference — brings
the 92 kg photo from +14.9% to +2.8% and the 96 kg photo to −6.3%, both inside the model's own
MAE band. Placing those post-cut masks against the training set, where `RA` correlates with
weight at r = 0.980, puts `cm_per_px_target = 0.35` within roughly 3% of what the data implies.

Decision: Attribute the weight branch's systematic field bias to the identity cutter, and
retain `cm_per_px_target` at 0.35 rather than re-fitting it. ADR-004's rule survives unchanged
— calibration constants come from repeat captures with a stated spread, never single-scan fits,
and the ±10.7% session-to-session capture noise it measured is real — but its premise about
this particular constant is withdrawn. Accuracy work on this branch goes to the cutter first;
constants are not to be adjusted to compensate for a missing stage, which is what the round-4
retune attempted and what made the constant look wrong in the first place. Where a question
about the native path cannot be answered because a stage is unported, the Python reference under
`ML/pipeline/` is the authority to consult before declaring the question blocked.

Consequences: `cm_per_px_target_uncertainty` stays above 1.0 and the 1.88 m calibration capture
is still wanted, but neither is now on the critical path for accuracy — the cutter is, and it is
worth roughly 15 kg of mean bias in either direction, which sets the budget for however it is
delivered. ADR-001's reasoning for not porting the cutter stands on its own terms (11,020 lines
depending on `scipy.signal.find_peaks`, `scipy.ndimage.gaussian_filter1d` and
`skimage.morphology.skeletonize`), but this ADR prices that decision: the stage it declines to
port is the single largest error term in the shipped product, so "not ported" cannot remain the
end state without accepting a ~16% bias. Choosing among a C++ port, an off-device service, and a
reduced portable subset is open work, tracked as F40 in `docs/fix-phase/7-cutter-quantified.md`.
Until one ships, `envelope["weight"]` must keep saying `protocol_implemented: false` and
carrying its overestimate note — those are now backed by a measured number, not a caveat.
