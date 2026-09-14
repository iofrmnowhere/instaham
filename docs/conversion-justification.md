# Justifying `cm_per_px_target`: how 0.35 was fitted, and whether fitting it was valid

**Status:** analysis, 2026-09-13. Written to record the reasoning behind the choice between the
fitted `0.35` and the derived `0.3289473684210526`, and to answer the standing question of
whether a constant obtained by fitting is defensible at all.

This document does not decide which constant ships. That decision belongs to
[ADR-011](adr/011-derived-scale-target.md), which currently records the derived value as
shipped. This document supplies the justification argument and states the limits of the
evidence on both sides.

## 1. What the constant does

The weight branch resamples the segmentation mask into the space the regressor was trained in.
The resample factor is a single ratio, computed in `packages/instaham_ml_ffi/src/pipeline.cpp:500`:

```
k = cm_per_px_actual / cm_per_px_target
```

Both terms are centimetres per pixel. `cm_per_px_actual` describes the photograph in front of
the user; `cm_per_px_target` describes the PIGRGB corpus the XGBoost regressor was trained on.
Dividing one by the other gives the factor that carries a mask from the first space into the
second, so that a pig photographed at any distance presents the same pixel dimensions the
regressor learned from.

Only `cm_per_px_target` is in question. It is a fixed property of the training corpus, declared
once in `assets/ml/manifest.json` under `capture_contract`.

## 2. Why camera height is not needed on the capture side

A recurring objection is that the field photographs in `.pig_pictures/` have no recorded camera
height, and that a constant fitted against them therefore rests on nothing. The objection does
not hold, because the two sides of the ratio are established by different means.

**The capture side is measured.** Each field photograph contains a physical reference object — a
metre stick or a porac stick — whose true length is known and whose pixel length the user marks
in the app. Dividing one by the other yields `cm_per_px_actual` directly. Camera height, field of
view, sensor size and lens focal length are all irrelevant to this computation: the reference
object has already absorbed every one of them. Height is the quantity you need when there is no
reference object in the frame, and these frames have one.

**The training side cannot be measured.** The PIGRGB images contain no reference object. Nothing
in them establishes a physical scale. The only available route is geometric reconstruction from
the reported rig: `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` gives a floor-plane baseline of
304 px/m at a 1.88 m capture height, which inverts to
`100 / 304 = 0.3289473684210526` cm/px. That document's section 24 is explicit that this figure
is theoretical, derived from reported geometry and camera field of view rather than from any
measurement of a released image, and instructs that it be replaced if empirical calibration from
the PIGRGB images is ever obtained.

The asymmetry is the whole point. Scale is *known* on the capture side and *unknown* on the
training side. Fitting therefore uses the side where scale is measurable to back-solve the side
where it is not. The 1.88 m figure never enters that fit and is not required by it.

## 3. How 0.35 was actually arrived at

The fit was performed in `docs/fix.md` round 4 as F21, and is recorded in
`docs/fix-phase/1-diagnosis.md`, section "Calibration evidence for `cm_per_px_target`". The
method was a grid sweep, not a derivation: set the constant, run the three field photographs end
to end through the pipeline, read the signed error, and repeat across a range of candidate
values.

| `cm_per_px_target` | 92 kg | 118 kg | 96 kg |
|---|---|---|---|
| 0.26 (then shipped) | 180.7 (+96%) | 173.8 (+47%) | 181.2 (+89%) |
| 0.32 | 117.5 (+28%) | 103.6 (−12%) | 104.5 (+9%) |
| **0.35** | **90.0 (−2%)** | **107.7 (−9%)** | **110.3 (+15%)** |
| 0.38 | 87.5 (−5%) | 82.6 (−30%) | 83.8 (−13%) |

A second, genuinely independent estimate was computed alongside it: the measured `BW` (minor axis
of the `minAreaRect`, the feature the uncut head perturbs least) was compared against the
regressor's own eval-row medians by weight bin, with the documented uncut-cutter inflation
divided out. That method implied 0.368 from the 92 kg photo and 0.347 from the 96 kg photo.

The two methods agreed on a band of roughly 0.33 to 0.37, and 0.35 was selected from within it.
The manifest recorded the provenance honestly at the time, as
`cm_per_px_target_source = "three_sample_field_estimate_pending_1p88m_calibration_capture"`,
and widened the feature-domain gate by `cm_per_px_target_uncertainty = 1.30` to reflect the
looseness of the estimate.

## 4. Is fitting a constant to match known answers a valid move?

In principle, yes. Solving for an unknown constant by requiring the system to reproduce known
ground truth is calibration, and calibration is ordinary engineering practice. It is how a
thermocouple, a load cell or a camera intrinsic matrix is established. There is nothing
inherently circular about it.

Calibration becomes unsound under three specific conditions. This fit meets two of them.

**Condition 1 — the fitted parameter must be the only unknown in the chain. Not satisfied.**
`cm_per_px_target` is the single free scalar in a chain that also contains cutter behaviour, mask
resampling, boundary-feature extraction and the regressor's own bias. Every one of those
contributes error, and all of them push in the same direction as a scale error. With one knob and
several error sources, the knob absorbs all of them. `docs/fix-phase/1-diagnosis.md` states this
in its own Standing caveat: head and neck inflation and scale error push the same direction, and
three photographs cannot untangle them.

There is direct evidence that this absorption happened. F21 moved the constant from 0.26 to 0.35
at a time when the V176/V144 cutter was still an identity stub, so the head and neck were left in
the mask and inflated every size feature. A constant that represented scale alone should have
moved once the cutter began genuinely cutting. It did not — the later sweep, run with
`cutter_status = cut_applied` and `kept_fraction` 0.80 to 0.93, still favoured 0.35. Whatever
0.35 is compensating for, it was never primarily the head.

**Condition 2 — some data must be held out from the fit. Not satisfied at fit time.**
Three photographs were used and none reserved. With no holdout, a fit cannot be distinguished
from memorisation.

Partial credit is due here, and it was 0.35's strongest argument at the time this section was
written. The 2026-09-09 host sweep in `docs/scale-constant-sweep-results.md` ran a *different*
corpus — five PIGRGB images at a 1.78 m capture height — and 0.35 won on MAE, 11.5% against
19.0%, and beat 0.3289 on all five images individually. That sweep predated F55's single composed
transform, and has since been superseded: `docs/scale-constant-sweep-results-2.md` re-ran the
comparison on the current pipeline against `sub_1.88/` (replacing the retired `sub_1.78/`) and
`.pig_pictures/`. On the re-run, `0.35` still has a lower MAE than `0.3289473684210526` on both
corpora, but the margin is inside corpus A's hand-marking jitter band and smaller than the
residual error a new `k = 1.0` arm shows exists independent of scaling — and neither candidate is
the empirical optimum on either corpus. `0.34` is, on both, independently. See the successor
document for the full reading; the out-of-sample check 0.35 passed in 2026-09-09 no longer
establishes what this section originally used it to establish.

**Condition 3 — the winning value must measurably beat its neighbours. Not satisfied.**
`docs/fix-phase/1-diagnosis.md` states plainly that the per-row differences between 0.34, 0.35
and 0.36 are not signal, and that the whole 0.32 to 0.36 band is equivalent on the available
evidence — three samples passed through a step-function ensemble. 0.35 is not a minimum. It is
one point inside a plateau, and any neighbour would have been selected on the same data.

## 5. What the two candidates actually are

Neither value is a measurement of the quantity it claims to represent.

- **0.35** is an empirical fit of the training-space scale, back-solved from three
  reference-object field captures at 92, 96 and 118 kg. It is not an independent measurement of
  the PIGRGB corpus's cm/px. It is the value that minimises end-to-end error, and it therefore
  carries residual pipeline error alongside true scale.
- **0.3289473684210526** is a geometric estimate of the same quantity, computed from a 304 px/m
  floor-plane baseline that its own source document describes as theoretical and unvalidated.

The honest comparison is not measurement against theory. It is a fit against measured ground
truth, versus a derivation from an unmeasured baseline.

Two points favour the field fit specifically. All three photographs sit at 92 to 118 kg, above
the regressor's approximately 73 kg floor documented in
[ADR-010](adr/010-regressor-training-domain-floor.md), so all three are inside the trained
domain — unlike the PIGRGB sweep, where the 60.27 kg and 66.24 kg rows are out of domain and
barely respond to the constant at all. And they are field photographs rather than PIGRGB, so the
fit is not scoring itself against the regressor's own training distribution.

The point a reviewer will press on is the sample size. Three photographs is thin, and no amount
of framing changes that.

## 6. What follows

**Action 2 is done; its result is recorded in `docs/scale-constant-sweep-results-2.md`.**
`ML/host_scale_test/` was re-run on the current (post-F55) pipeline, against `sub_1.88/`
(replacing the retired `sub_1.78/`, with `extrapolated`/`extrapolated_features` now recorded live)
and `.pig_pictures/`. The re-run confirms this section's own reading better than either candidate
does: the plateau is real, `0.35` beats `0.3289473684210526` by a small margin on both corpora,
and neither is the empirical optimum — `0.34` is, independently, on both. This round's decision
was to ship `0.34`; that contradicts [ADR-011](adr/011-derived-scale-target.md) and is flagged
there and in the successor document for `pipeline-docs` to resolve. It does not change what is
currently shipped — see the successor document's "What follows" for the manifest/exporter
sequencing this still requires.

One action remains outstanding:

1. **A 1.88 m calibration capture.** A reference object photographed at the PIGRGB training
   height converts `cm_per_px_target` from a fitted or derived quantity into a measured one, and
   removes the ambiguity permanently. This is what `cm_per_px_target_source`'s original
   `pending_1p88m_calibration_capture` label was always pointing at, and what
   `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` section 24 asks for. Nothing in the re-run
   changes its value — it is the only route to a *measured* rather than derived or fitted
   constant, and the re-run's own `k = 1.0` arm shows a non-trivial error floor that no choice of
   `cm_per_px_target` can address regardless of this action.

Until the calibration capture exists, whichever constant ships should be described as an estimate
with a stated basis, and no accuracy claim should be attached to it.

## References

- `packages/instaham_ml_ffi/src/pipeline.cpp:500` — the resample ratio.
- `docs/fix-phase/1-diagnosis.md`, section "Calibration evidence for `cm_per_px_target`" — the
  F21 sweep and the independent `BW` estimate.
- `docs/fix-phase/2-applied-changes.md`, section F21 — the manifest change and its recorded
  provenance.
- `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` section 24 — the 304 px/m baseline and its
  theoretical status.
- `docs/scale-constant-sweep-results.md` — the 2026-09-09 host sweep, now describing a superseded
  code path.
- `docs/scale-constant-sweep-results-2.md` — the 2026-09-14 re-run on the current pipeline against
  `sub_1.88/` and `.pig_pictures/`, including the `k = 1.0` result and this round's `0.34`
  decision.
- [ADR-010](adr/010-regressor-training-domain-floor.md) — the approximately 73 kg regressor floor.
- [ADR-011](adr/011-derived-scale-target.md) — the current shipped constant.
