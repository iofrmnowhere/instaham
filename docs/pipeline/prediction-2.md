# Weight Prediction — Sensitivity and Calibration

Continuation of [prediction.md](prediction.md), which documents the code path. This file covers
the *measured behaviour* of the shipped regressor and the pipeline feeding it: which inputs
actually move the output, and by how much. Read it before changing any manifest constant that
feeds the weight branch.

The shipped family is **`chen16_noheight`** (16 features, [ADR-007](../adr/007-manifest-declared-feature-family.md)).
Its values are raw pixel counts and lengths measured on the cut mask — there is no `RA`-style
frame denominator and no additional linear scaling (`spec.md`, `feature_calculation.h`). Any
claim below phrased in terms of `RA` belongs to the retired `baseline5` family and is marked such.

## The exported model's own accuracy

From `assets/ml/weight/xgboost.meta.json`, the export's recorded self-check:

| | value |
|---|---|
| `reproduced_test_mae` | 4.564 kg |
| `onnx_max_abs_diff` vs. source model | 0.00029 kg |
| `n_estimators` / `base_score` | 600 / 121.669 |

The ONNX conversion is faithful; the model's own error on its eval set is ~4.6 kg. Field error
larger than that is upstream — in the mask, the cut, or the scale applied to them.

## Area scales with the square of the resample

`k = cm_per_px_actual / cm_per_px_target` resamples the mask before features are measured
(`construction.cpp:129`, called from `pipeline.cpp:669`). `mask_area` and `convex_hull_area` are
pixel counts, so they scale with `k²` while `perimeter`, `longest` and `shortest` scale with `k`.
A calibration error therefore enters the area features squared.

> **A 1% error in either `cm_per_px_actual` or `cm_per_px_target` is a ~2% error in
> `mask_area`.**

This is the structural reason `cm_per_px_target` is the highest-gain constant in the pipeline.
It is a statement about *sensitivity*, not *correctness*: F38 put 0.35 within ~3% of what the
training data implies, and F46 below measured both candidates against known weights.

`cm_per_px_target_uncertainty` (1.30) widens the area features' domain bounds by `1.30² = 1.69`.
The domain gate is deliberately never stricter than the calibration it rests on, so at this
uncertainty it is barely a gate on area at all.

## The response is piecewise-constant, so the constant must not be fitted

XGBoost is a sum of 600 trees: its output is a step function of its inputs, not a curve, and it
is not monotone in area. Near a split boundary an arbitrarily small input change produces a
discontinuous jump. Two independent measurements show this directly.

**Sweeping `cm_per_px_target`** against the three field photos (measured on the *retired*
`baseline5` family and on **uncut** masks — kept because the shape of the response is the
point, not the absolute values):

| `cm_per_px_target` | 0.30 | 0.32 | 0.35 | 0.38 | 0.41 | 0.44 |
|---|---|---|---|---|---|---|
| 92 kg photo | 131.8 | 117.5 | 90.0 | 87.5 | 85.4 | 74.3 |
| 118 kg photo | 135.8 | 103.6 | 107.7 | 82.6 | 112.0 | 85.6 |
| 96 kg photo | 136.8 | 104.5 | 110.3 | 83.8 | 87.4 | 88.8 |

The 118 kg row runs 103.6 → 107.7 → 82.6 → 112.0 across four adjacent steps. That is leaf
structure being sampled, not a calibration curve.

**Sweeping the user's reference marking** (F53, measured on the shipped `chen16_noheight`
family — see below) reproduces the same non-monotone stepping from the input side.

**F46 — the two candidate constants, measured properly.** The table above was host-side, uncut
`baseline5`; F46 re-ran it on device with the shipped cutter and family, six marks per photo per
constant, on medians (`../logs/recorded.md` rounds 2 and 3):

| photo | true | at 0.35 | at 0.3289 |
|---|---|---|---|
| 92 kg | 92 | 87.07 (−5.4%) | 97.93 (+6.5%) |
| 96 kg | 96 | 86.66 (−9.7%) | 100.07 (+4.2%) |
| 118 kg | 118 | 106.72 (−9.6%) | 136.65 (+15.8%) |

Every separation exceeds its photo's jitter band, so the constant does move the answer
measurably — but it moves all three photos from undershooting to overshooting without landing on
any of them. Both arms predate round 7's composed transform; round 28 re-ran it on the post-F55
path, neither won, and **0.34** ships now ([ADR-012](../adr/012-measured-scale-target.md)) —
figures and the bounding `k = 1.0` arm in [prediction-4.md](prediction-4.md).

## F53 — the pipeline amplifies reference-marking noise

The reference object's pixel length is not one linear constant. Measured on device with the
release APK, three photos, six marks each across a ~16 px band (0.7–1.0% of each reference
length), the shipped V176/V144 cutter in the loop:

| photo | predicted range | spread | monotone? |
|---|---|---|---|
| 92 kg | 83.54 – 88.03 kg | 5.18% | no |
| 96 kg | 78.53 – 88.84 kg | 12.04% | no |
| 118 kg | 104.80 – 118.49 kg | 12.55% | yes |

Four terms, not three, all measured on the pre-round-7 double-rasterization path — 2 and 4
name a step the weight branch no longer runs ([segmentation-2.md](segmentation-2.md)):

| term | mechanism | measured |
|---|---|---|
| 1 — segmenter input | `content_scale = cm_per_px_actual / input_cm_per_px` (`pipeline.cpp:355-360`) resizes what YOLO sees, so the mask itself changes | 0.39–3.38% mask area — the **smallest** term |
| 2 — resample quantization | `lround(w·k)`, `lround(h·k)` + `INTER_NEAREST`, applied twice (unletterbox, then scale-by-`k`) | not separable on device; it is the mechanism feeding 3 and 4, and the one F55 removed by composing a single transform |
| 3 — cutter on the resampled grid | the cut runs *after* the resample (`pipeline.cpp:667-697`); V176 selection is discrete | **dominant on 2 of 3 photos**; `kept_fraction` moved 0.8063→0.9507 and the answer 10.31 kg with the segmentation mask **bit-identical** |
| 4 — boundary features into a step-function regressor | `INTER_NEAREST` preserves area and destroys boundary statistics; 8 of 16 features are boundary-derived. The weight path now resamples once, `INTER_AREA`/`INTER_LINEAR`, so this term is expected to shrink — unverified on device | **dominant on the 118 kg photo**: mask area moved −0.04%, `outline_curve` +16.22%, `Hu_6` +128.84%, weight **−5.84 kg** |

Item 3 is isolated on pairs of adjacent marks sharing an identical `construction.mask_area_px`,
so segmentation contributed exactly nothing across them: the cutter amplifies upstream jitter
rather than absorbing it. Item 4 is isolated the same way, on a pair where the regressor's own
mask area is unchanged to four significant figures.

`Hu_3` through `Hu_7` are the least stable inputs, swinging hundreds to thousands of percent
between adjacent marks — near-zero quantities, so not alarming alone, but nothing stabilises
them and the ensemble splits on them. `shortest` comes back integer-valued and steps ~0.7% at
a time regardless of marking precision.

An earlier host sweep (no cutter, 92 kg only) put item 1 at 6.10% over a wider ±2% band and
items 1+2 at 11.45%; the device sweep supersedes it — over a realistic band item 1 is the
smallest term, and the term the host could not run is the one that dominates.

Full derivation and per-scan data:
[2.1](../fix-phase-2/2.1-reference-length-sensitivity.md), [logs](../logs/recorded.md).

**Consequence for calibration work:** a single scan per photo is not a measurement; the
0.35-vs-0.3289 comparison was run under this constraint and cleared it (F46 above).

## The cutter now ships, and the bias figures predate it

> **Superseded description.** [ADR-001](../adr/001-cutter-identity-stub.md) declared the C++
> cutter a permanent identity stub. That decision was reversed:
> [ADR-009](../adr/009-cutter-ported-after-all.md) records the port, `stages::cut_body_mask()`
> now runs the real V176/V144 stack ([cutter.md](cutter.md)), and `pipeline.cpp:697` calls it on
> every dorsal scan with `protocol_implemented: true`.

The identity stub's cost was measured before the port and set its budget
([ADR-005](../adr/005-identity-cutter-is-the-dominant-error.md)). Substituting pre-cut area for
post-cut `RA` across the 2014-row eval set, on the retired `baseline5` family:

| | MAE | mean bias |
|---|---|---|
| properly cut (research protocol) | 4.94 kg | −1.0% |
| identity stub (then shipped) | 19.96 kg | **+16.6%** |

Device-observed bias was **+15.9%** across the three field photos. Those numbers describe the
*pre-port* app and are retained only as the justification for porting.

**They have not been re-measured since the port.** The shipped cutter's real effect on field
*bias* is still open work. Its effect on *variance* is now measured and is the opposite of
reassuring: F53 above shows the cutter is the largest single amplifier of reference-marking
noise on two of three photos. A bias re-measurement must therefore report a spread across
repeat markings, never a single scan per photo.

> Continued in [prediction-4.md](prediction-4.md) — practical calibration guidance.
