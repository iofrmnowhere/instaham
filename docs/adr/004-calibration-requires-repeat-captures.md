# ADR-004: Calibration constants come from repeat captures, never from single-scan fits

Status: Accepted — decision stands; premise superseded by
[ADR-005](005-identity-cutter-is-the-dominant-error.md), which shows `cm_per_px_target` is
within ~3% of correct once masks are properly cut, and attributes the field bias to the
identity cutter instead. The repeat-capture rule below is unaffected.

Context: `weight.cm_per_px_target` has been fitted twice against the same three field
reference photos — 0.26, then 0.35 — each time by reading the regressor's output on one scan
per photo and choosing the constant that put all three closest to their known weights. Both
values were reported as accurate to roughly ±15% at the time they were chosen, and neither
held. Three measurements taken since explain why. First, the regressor is effectively
univariate in `RA`, and `RA` carries the scale calibration squared, so a 1% error in
`cm_per_px_target` moves the predicted weight by 2.8–4.0% (see
[../pipeline/prediction-2.md](../pipeline/prediction-2.md)). Second, the regressor's response
to that constant is piecewise-constant and non-monotone — one photo reads 103.6, 107.7, 82.6
and 112.0 kg at targets 0.32, 0.35, 0.38 and 0.41 — so a minimum found on three points is a
leaf boundary, not an optimum. Third, and decisively, re-photographing the same three pigs
with the same phone, the same sticks and the same operator produced predicted weights
differing from the first session by −10.7%, −6.5% and +0.3%, while the derived `cm_per_px`
agreed to within 0.7% across both sessions. The variation is in the segmentation mask, not in
the reference marking, and it is larger than the accuracy the fitting was trying to achieve.

Decision: A calibration constant for the weight branch is derived from a deliberate capture
protocol with repeat captures and a stated spread, never fitted against single scans of
opportunistic field photos. Concretely, `cm_per_px_target` stays labelled
`three_sample_field_estimate_pending_1p88m_calibration_capture` — an honest description of an
uncalibrated value — until several captures at a measured 1.88 m produce a median `cm_per_px`
directly, and `cm_per_px_target_uncertainty` stays above 1.0 until then. Any future change to
a constant that feeds the weight branch must state how many captures it rests on and the
spread across them; a change justified by a single scan per subject is not accepted, however
good the resulting numbers look.

Consequences: Improving weight accuracy now requires physical capture work rather than
manifest edits, which is slower and cannot be done from the repository. In exchange, the
project stops paying for tuning rounds that appear to succeed offline and regress on a
device — the specific failure that produced both prior values. Field results quoted anywhere
in `docs/` must name the session they came from, because a single scan is no longer treated
as reproducible evidence; the two sessions' numbers for the same three photos are recorded in
`docs/logs/ref_log.md`. The `ML/tools/replicate_native_weight_branch.py` harness stays useful
for understanding the model's response surface, which is what produced the measurements in
this ADR's context, but a number it produces is not by itself grounds for changing a constant.
This does not supersede [001](001-cutter-identity-stub.md): when the real cutter lands,
`cm_per_px_target` must be re-derived under this same protocol rather than adjusted, since the
current value partly absorbs the uncut mask's head and neck area.
