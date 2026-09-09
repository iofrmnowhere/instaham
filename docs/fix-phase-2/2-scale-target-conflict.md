# Phase 2 — The scale target: 0.35 cm/px against the specification's 304 px/m

Status: **closed 2026-09-09 — 0.35 kept, applied and shipped.** Three device photos were swept
at both constants (rounds 2 and 3, `docs/logs/recorded.md`) and did not resolve it: neither
constant was uniformly right. The host harness then settled it against ground truth — five
PIGRGB images, shipped models, real V176/V144 cutter, eight constants from 0.28 to 0.50 — where
0.35 won on MAE (11.5% vs 0.3289's 19.0%) and on every image individually
(`docs/scale-constant-sweep-results.md`). `cm_per_px_target` is back to 0.35 in
`ML/export/export_xgboost.py`, re-exported into `assets/ml/manifest.json`, and running in the
user's rebuilt APK. The specification's 304 px/m is retracted as a shipped value.

The same sweep found the error term that outranks this phase's question: the regressor cannot
predict below roughly 73 kg because light pigs fall outside its trained feature domain
(`docs/adr/010-regressor-training-domain-floor.md`). That is a retraining problem and is not
tracked here.

**Read `docs/fix-phase-2/2.1-reference-length-sensitivity.md` before starting.** F53 swept the
reference marking on all three photos and measured jitter bands of **5.18%, 12.04% and 12.55%**
of predicted weight, from nothing but where the user places the endpoints. Two of those bands
are as large as the ~13% in predicted weight that separates the two constants this phase is
choosing between. Single predictions are therefore not measurements here, and the single
87.36 kg previously recorded for the 92 kg photo is one draw from a 83.54–88.03 kg
distribution.

## Symptom

Two documented values for the same constant disagree by 6.4%, and because the regressor is
area-dominated, a 6.4% linear disagreement is roughly 13% of predicted weight.

- `assets/ml/manifest.json` sets `capture_contract.cm_per_px_target: 0.35` cm/px, which is
  **285.7 pixels per meter**, tagged
  `three_sample_field_estimate_pending_phase5_post_cut_rederivation`.
- `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` section 1 sets `PIGRGB_TARGET_PPM = 304.0`
  pixels per meter, which is **0.3289 cm/px**.

## Root cause

### F46 — the two constants were derived by different methods, and neither measured PIGRGB

**304 px/m is computed from the reported acquisition geometry**: the PIGRGB `RGB_9579` capture
at approximately 1.88 m above the floor, released at 960 × 540, with the camera's field of
view. Section 24 of the specification is explicit that this is "a theoretical PIGRGB
floor-plane baseline derived from the reported PIGRGB acquisition geometry and RGB camera
field of view", to be replaced if an empirical calibration from the released images is ever
obtained.

**0.35 cm/px was fitted from field photographs.** `docs/fix.md` round 4's F21 moved it from
0.26 to 0.35 to stop correct masks landing above the regressor's trained maximum. That fit was
performed on uncut masks, with the pig's head and neck still attached, which round 5's F36
later showed is worth +16.6% of mean bias on its own.

### The obvious reading of that history is contradicted by F38, and the contradiction is the finding

It is tempting to conclude that 0.35 is simply stale compensation for the head — that F21 blamed
the scale for a cutter defect, and that now the cutter is real the constant should return to the
specification's 0.3289. Round 5 already tested that reading and it did not hold.

`docs/fix-phase/7-cutter-quantified.md` F38 placed the **post-cut** field masks against the
training data, where `RA` correlates with weight at r = 0.980:

| Photo | field `RA` (cut) | training median at that weight | implied `cm_per_px_target` |
|---|---|---|---|
| 92 kg | 0.08237 | 0.08087 | 0.35 × 0.991 = 0.347 |
| 96 kg | 0.08102 | 0.08589 | 0.35 × 1.030 = 0.361 |

Both land within about 3% of 0.35, and both are **above** the specification's 0.3289 rather
than bracketing it. F38's conclusion was that the four rounds of believing this constant badly
miscalibrated were an artifact of measuring it with uncut masks.

So the conflict is genuine and unresolved: a theoretical value derived from documented camera
geometry against an empirical value derived, post-cut, from two field photographs. It is not a
case of one side having already been shown wrong.

### F47 — the formula itself agrees; only the constant and the units differ

Worth recording so this is not re-investigated. The specification works in pixels per meter and
the code in centimetres per pixel, but the algebra is identical:

```text
spec (section 3):  scale_factor = 304.0 / observed_ppm
code:              k = cm_per_px / 0.35  =  285.7 / observed_ppm
```

`ComputeScaleUseCase`, reached from `reference_marking_screen.dart:342`, divides the reference
object's physical length by its pixel length measured in **original image coordinates**
(`_originalPixelLength`), which satisfies both the specification's section 8 and AGENTS.md
rule 9. A related consistency check also passes: the manifest's `training_frame_px: [720, 720]`
looks arbitrary but `sqrt(960 × 540) = 720` exactly, so the code's `training_scale` is the
geometric mean of the specification's released PIGRGB frame.

The camera's field of view does not enter the runtime calculation at all, and should not — the
specification's section 11 requires scale to come from the visible reference object rather than
from any camera property. Field of view matters only on the training side, as an input to
deriving 304.

## What phase 2.1 already contributes

2.1's sweep ran all three photos at the current `cm_per_px_target` of 0.35, six marks each, so
half of this phase's comparison is already collected. Full per-scan data in
`docs/logs/recorded.md`.

| photo | true kg | band at 0.35 | median | median error |
|---|---|---|---|---|
| 92 kg meter stick | 92 | 83.54 – 88.03 | 87.07 | −5.4% |
| 96 kg porac stick | 96 | 78.53 – 88.84 | 86.66 | −9.7% |
| 118 kg porac stick | 118 | 104.80 – 118.49 | 106.72 | −9.6% |

**All three read low, by 5–10% at the median.** F46's first step below predicted exactly this
test — "if the three field photos read low after phase 1 restores the branch, that supports the
specification's value" — and the answer came back low on all three. Since `k = cm_per_px /
target`, moving 0.35 down to 0.3289 raises `k`, the resampled mask, and the prediction, which
is the direction the error asks for.

That is a real signal in 0.3289's favour, and it is new: F38's post-cut `RA` table pointed the
other way, both photos implying a target within 3% of 0.35 and both above 0.3289. One of the
two has to give, and this phase is where that is settled.

**It is not yet a result, and it must not be extrapolated.** Multiplying these predictions by
the ~13% the constant change implies is invalid — 2.1 measured the regressor moving 5.84 kg on
a 0.04% change in mask area, so it is a step function, not a gain. The 0.3289 half of the
comparison has to actually be run.

## What the 0.3289 sweep shows

Same three photos, same six-mark bands 2.1 used (`ref_px` reproduces round 2's within noise;
each file's first scan reproduces round 2's `segArea` exactly). Full per-scan data is round 3
in `docs/logs/recorded.md`.

| photo | true kg | 0.35 median (error) | 0.3289 median (error) | separation vs bands |
|---|---|---|---|---|
| 92 kg meter stick | 92 | 87.07 (−5.4%) | 97.93 (+6.45%) | 10.86 kg, exceeds both bands |
| 96 kg porac stick | 96 | 86.66 (−9.7%) | 100.07 (+4.24%) | 13.41 kg, exceeds both bands |
| 118 kg porac stick | 118 | 106.72 (−9.6%) | 136.65 (+15.83%) | 29.93 kg, exceeds both bands |

**F46's predicted direction held on all three** — 0.3289 raised every prediction, as the
`k = cm_per_px / target` relationship said it must. On all three photos the separation between
the two constants is well above their jitter bands, so this is a resolved measurement, not
noise: changing the constant genuinely moves the answer, and by more than marking jitter can
explain.

**But 0.3289 is not the better constant.** It only improves the 96 kg photo (−9.7% → +4.24%,
though that photo's own median is inflated by a recurring cutter discontinuity — see round 3's
note). On 92 kg it swaps a −5.4% error for a worse +6.45%, and on 118 kg it turns a −9.6% error
into the sweep's largest error at +15.83%. 0.35 stays closer to true weight on two of three
photos, including the one furthest off. This does not vindicate 0.35 either — it means neither
constant is uniformly right, consistent with F38's per-photo implied targets (0.347, 0.361)
landing near 0.35 rather than bracketing 0.3289.

## What the host sweep shows

The three-photo device comparison above could not separate the constants on merit — it only
established that changing the constant moves the answer by more than marking jitter. The
deciding measurement was made off-device instead, because ground truth was available there and
is not available for the field photos.

`ML/host_scale_test/` compiles the app's own stage sources — segmentation, construction, the
`k`-resample, the vendor V176/V144 cutter, Chen16 features, XGBoost-via-ONNX — against the
shipped `assets/ml/` models, and was run over five PIGRGB images with known true weights.
`cutter_status` was `cut_applied` on every run, `kept_fraction` 0.80–0.93.

| target | 60.27 | 66.24 | 100.90 | 125.38 | 133.42 | MAE |
|---|---|---|---|---|---|---|
| 0.3289 *(spec)* | +26.1 | +23.4 | +5.2 | +23.0 | +17.2 | 19.0 |
| **0.3500** | +25.7 | +20.1 | −4.1 | +1.1 | +6.6 | **11.5** |

0.35 wins on MAE and on all five images individually. Full sweep of eight constants, and the
reasoning for why this supersedes rounds 2–3 rather than merely outvoting them, in
`docs/scale-constant-sweep-results.md`.

**0.35 is an empirical fit, not a derivation, and the manifest says so.** Its F21 provenance is
contaminated — it was fitted while the cutter was an identity stub — and the sweep's three
criteria give three different optima (MAE at 0.35, |bias| at 0.38, spread at 0.30), which is
what a non-dominant error term looks like. It ships because it measured best, not because it is
correct.

## Change made

`ML/export/export_xgboost.py` — `cm_per_px_target` 0.3289 → **0.35**, with
`cm_per_px_target_source` now `host_scale_sweep_round6_f49_empirical_fit_not_derived` and the
surrounding comment rewritten to cite this sweep and the §24 retraction rather than the pending
comparison. Re-exported with `--enable-for-testing`; `assets/ml/manifest.json` rebuilt from all
four capability fragments, which also retired 28 stale `baseline5` `RA/LC/BL/BW/E`
`feature_domain` keys that HEAD still carried. The user rebuilt and sideloaded the APK and
confirmed it ships correctly.

## Steps

- [ ] **F46 — predict the direction before measuring, then check it.** `k = cm_per_px /
      target`, so a *smaller* target gives a larger `k`, a larger resampled mask, and a higher
      weight. Moving 0.35 to 0.3289 therefore raises `RA` by about 13% and raises predictions.
      If the three field photos read low after phase 1 restores the branch, that supports the
      specification's value; if they read close to true weight at 0.35, F38 stands and the
      specification's 304 is the number in question.
- [x] **F46 — predict the direction, then check it: done for the 0.35 half.** All three
      photos read low at 0.35 (medians −5.4%, −9.7%, −9.6%), which is the direction that
      supports the specification's 0.3289. See "What phase 2.1 already contributes" above.
      The 0.3289 half is still owed.
- [x] **F46 — re-run the three `.pig_pictures/` photos at 0.3289, as a sweep, not a point:
      done.** Same six-mark bands 2.1 used, same capture cycle. Round 3 in
      `docs/logs/recorded.md`; comparison in "What the 0.3289 sweep shows" above.
- [x] **F46 — state the comparison's power before believing it: done.** All three photos'
      0.35-vs-0.3289 separations exceed their jitter bands (10.86 / 13.41 / 29.93 kg against
      bands of a few kg to ~9 kg), so this is resolved, not noise-limited. The resolution is
      that 0.3289 is not the better constant on two of three photos, not that either constant
      is correct — see above.
- [ ] Note that `docs/fix.md` F39 leaves the 118 kg photo's mask unexplained, so treat that
      photo as an observation rather than as evidence until F39 closes. F53 adds a second
      reason for caution on it specifically: it is the photo whose predicted weight moves most
      while its mask moves least, so it is the one most exposed to the regressor's step
      behaviour rather than to the constant under test.
- [x] **F46 — measure the constant directly from the released PIGRGB images if they can be
      obtained: done.** §24 asked for exactly this and it is what closed the phase. The images
      were already in the repository under `Instaham/PIGRGB-Weight/`; the missing piece was a
      host build of the real stages, now `ML/host_scale_test/`. Note this measured the constant
      *by sweep against known weights*, which is not the same as
      `docs/plan-phase/5-parity-validation.md`'s re-derivation from post-cut field masks —
      that work is still owed and is not discharged by this.
- [x] **F46 — whichever value wins, record its derivation in the manifest: done.**
      `cm_per_px_target_source` reads `host_scale_sweep_round6_f49_empirical_fit_not_derived`,
      which names both the evidence and its limit. 304 was not adopted, so the theoretical-tag
      branch of this step does not apply.
- [x] **F49 — the specification's standing, decided.** `INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`
      §24 states 304 px/m is theoretical rig geometry and directs that it be replaced if
      empirical calibration is obtained. That calibration now exists and 304 lost, so it is
      retracted as a shipped value. The document stays authoritative for the PIGRGB baseline
      itself, which is what the harness uses to derive `cm_per_px_actual`.
- [x] **F38 — resolved, not retracted.** Its post-cut `RA` table implied per-photo targets of
      0.347 and 0.361, both near 0.35 and above 0.3289. The host sweep agrees with its
      direction, so it stands. Rounds 2–3's low readings at 0.35, which were the evidence
      against it, are now attributed to the low-end floor rather than to the constant.
- [x] Flag whether an ADR is warranted: **yes, written.**
      `docs/adr/010-regressor-training-domain-floor.md` records the floor as the dominant error
      and supersedes ADR-005, which discharges the ADR-005 replacement owed since round 5.
      Written by `pipeline-docs`, as this skill does not own `adr/`.

## Verification

- The three field photos are re-measured at both constants against known weights, **each as a
  six-mark sweep reported as band plus median**, with the result recorded even if it is
  inconclusive.
- The comparison's power is stated: if the medians separate by less than the jitter band, the
  recorded outcome is "not resolved at this noise level", not a winner.
- The chosen value's derivation is stated in the manifest, not just its number.
- F38's table is either confirmed against post-cut masks from the shipped native cutter, or
  explicitly retracted the way F31 was. F53's low readings at 0.35 are the first evidence
  against it and should be weighed here.

**Verification outcome (2026-09-09).** All four met. The band-plus-median requirement was met by
rounds 2 and 3 on device; the power statement was made and the honest answer there was "not
resolved on merit," which is why the host sweep was run. The derivation is in the manifest's
`_source` tag. F38 is confirmed, not retracted.

What is **not** verified, and must not be read into this closure: the host run is five images
from the regressor's own training distribution, so its in-domain agreement is partly
memorization and does not predict field accuracy. The 1.78 m capture height comes from the
dataset folder's description rather than a repository document, and every scale figure moves
with it. Host ONNX Runtime is 1.29.0 against the device's Android `.so` — same graphs, not
bit-identical. And the live-camera path remains entirely unmeasured across all six rounds; every
device measurement cited here is the gallery-import path.
