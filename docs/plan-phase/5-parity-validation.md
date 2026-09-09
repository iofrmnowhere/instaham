# Phase 5 — Parity, validation, and docs

Status: not started

## Goal

Prove the ported cutter and Chen16 extractor match the Python reference that produced the
training features, prove the end-to-end native pipeline reproduces the model's own eval
numbers, re-measure the field bias, and only then update the documentation and close
`docs/fix.md`.

Nothing here is optional. The vendor says it directly, and this repo has been burned by the
alternative: `docs/fix-phase/7-cutter-quantified.md` (F37) retracts F31 precisely because a
stage was approximated instead of run.

## The ladder is the vendor's, not mine

`tests/README.md` prescribes a seven-step stage-by-stage comparison against the frozen Python
outputs, to be completed **before** Flutter integration. `VALIDATION.md` adds why it is
non-negotiable: the package was never compiled in the artifact environment, so every contract
claim in it was verified by reading rather than by running. Follow their order; the levels
below map onto it rather than replacing it.

| vendor step | covered by |
|---|---|
| 1. original-coordinate YOLO whole mask | level 0 (new, below) |
| 2. truncation result | level 0 |
| 3. pre-Ji/Duan body_curve and posture result | level 0 |
| 4. Ji/Duan mask | level 2 |
| 5. V176 selected shoulder + V144 final mask | level 2 |
| 6. each Chen16 value | level 1 |
| 7. final XGBoost prediction | level 3 |
| — (beyond the vendor's ladder) | level 3.5 full-eval-set replay, level 4 field photos, level 5 device |

Levels 1 and 2 are ordered feature-first because the Chen16 CLI is a pure function of whatever
mask it is handed and therefore needs nothing from the cutter — the vendor makes the same
point about `chen16_mask_cli`. Everything else runs in their order.

## Design/Approach

### Level 0 — mask, truncation, posture (vendor steps 1–3)

The app's segmentation already claims `original_coordinate_polygon_v1`, which is one of the
three protocol identifiers `VALIDATION.md` records for the vendor's YOLO postprocessing. Step
1 is therefore a check that the app's restored mask matches the Python whole mask, not a
port. Steps 2 and 3 exercise the two quality-gate detectors phase 2 ports: compare the
truncation verdict and the pre-Ji/Duan `body_curve` angle against the Python reference on the
same masks.

This is also where the plan's open question 3 gets answered — whether the app's own mask
selection satisfies the vendor's `cleaned_target_instance_v1` contract. If step 1 disagrees,
stop: every later step is measuring a different mask and the parity numbers are meaningless.

The dataset drop makes this a direct measurement rather than an inference.
`Instaham/PIGRGB-Weight/MASK_3394/` holds 3394 binary ground-truth masks (0/255, 960×540)
paired 1:1 by filename with `RGB_3394/`, so the app's segmentation can be scored against
truth per image (IoU) instead of being judged by how wrong the weight comes out downstream.
Score the app's mask against ground truth first; only then compare it to the Python whole
mask. If the app disagrees with ground truth, open question 3 is answered in the negative and
that is a segmentation-selection ADR, not a cutter problem.

### Level 1 — feature parity on a fixed mask (vendor step 6)

The cheapest and most decisive check. `ML/pipeline/feature_calculation.py::
extract_chen16_features` carries protocol `chen16_noheight_centerchord_v2`, which is exactly
the `extended_feature_protocol_version` recorded on all 1821 rows of
`fixed_test_predictions.csv`. So the Python in this repo is the function that produced the
training features, and the C++ must match it, not merely resemble it.

Build a host CLI (the vendor's `tests/chen16_mask_cli.cpp` is the model for this, but write
the app's own so it links the app's `stages/` seam rather than the vendor's) that takes a
mask PNG and prints 16 doubles. Run it and the Python function over the same masks and diff.

The masks are `Instaham/PIGRGB-Weight/MASK_3394/` — all 3394 of them at this level, having
gated phase 2 on a 20-mask subset. Ground-truth masks are the right input precisely because
`extract_chen16_features` is a pure function of the mask it is handed: nothing about this
level depends on those masks having been cut, so it isolates the feature arithmetic from both
the segmentation and the cutter. This is what the plan originally wanted the vendor's
`final_mask_cache` for; the cache is absent and unobtainable, and this is strictly better.

Tolerances, per phase 2's proposal, to be fixed here against real numbers:

| feature | tolerance |
|---|---|
| `mask_area`, `convex_hull_area`, `difference` | exact (integer pixel counts) |
| `dif_mask` | derived from the above; exact if they are |
| `perimeter`, `longest`, `shortest`, `outline_curve` | relative 1e-3 |
| `body_curve` | relative 1e-3, but any mismatch is a thinning bug to fix, not a tolerance to widen |
| `Hu_1`..`Hu_7` | relative 1e-6 |

`body_curve` is the known-risky one, and the vendor names it as such twice. `tests/README.md`:
"The body-curve C++ implementation uses self-contained Zhang-Suen 2-D thinning to reproduce
the Python/skimage skeleton concept. Treat exact body-curve equality as a parity item before
production; tiny skeleton topology differences are the most likely cross-library source of
disagreement." Note "reproduce the concept", not "match the algorithm" — `skimage`'s 2-D
`skeletonize` is Zhang-Suen by default but its `method='lee'` path and its border handling
differ. Check `body_curve` first, alone, before anything else in this level.

A `body_curve` mismatch is worse than it looks: it is feature 5 of 16 **and** the posture
gate's only input (level 0, step 3), so one thinning discrepancy corrupts a feature and a
rejection decision at once.

### Level 2 — Ji/Duan, shoulder, and final mask (vendor steps 4–5)

**This level was specified wrong and is rewritten.** The original plan said to run
`ML/pipeline/cutter.py::isolate_body_only_mask` and the ported C++ cutter over the same masks
and compare final-mask IoU. That is not a parity test: `cutter.py` declares
`PROTOCOL_VERSION = "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26"` and contains no
V176, V144, ShrinkingBall, SelleFilter, or Break1 code, while every CSV row carries
`cut_protocol_version = v176_strict_nonprimary_break1_region_meet_v144_fixed_center_bilateral_circle_v1`.
The two are different head-removal algorithms. An IoU of 0.99 between them would be a
coincidence and an IoU of 0.90 would prove nothing. There is no reference implementation of
the shipped cut protocol outside the vendor sources being ported.

Use the CSV's own per-row cutter telemetry instead. It is populated on all 1821 rows and
pins every decision the V176 selector and V144 cutter make:

| CSV column | what it checks in the port |
|---|---|
| `final_mask_area_px` | the post-cut pixel count — and it equals `mask_area` on all 1821 rows, so this is the final mask's area exactly, no PNG required |
| `kept_fraction`, `removed_fraction` | how much of the whole mask survived the cut |
| `shoulder_selected_x`, `shoulder_station_fraction`, `shoulder_pos` | where V176 placed the shoulder station |
| `break1_x`, `break1_fraction`, `break1_fallback_used` | the Break1 fit and whether the fallback fired |
| `circle_center_x`, `circle_center_y`, `final_circle_radius_px`, `circle_radius_growth_px`, `circle_radius_enlarged` | the V144 circle geometry |
| `peak_route_type` (6 distinct values) | which V176 routing branch was taken |
| `selection_reason` (7 distinct values) | why that branch was chosen |

Run the ported cutter over the whole-mask input for each row and compare. The categorical
columns are the strongest signal and should be checked first: `peak_route_type` and
`selection_reason` are exact-match, and a port that picks the right branch on 1753/1821
`v176_primary_headward_intersection_cut` rows but disagrees on the 46
`v176_no_primary_left_intersection_cut` rows has told you exactly which code path is wrong.
The geometric columns are then compared numerically — propose exact on
`final_mask_area_px`, relative `1e-3` on the circle geometry and the fractions, and treat
`peak_route_type` disagreement as a blocker rather than a tolerance question.

Attribute failures by stage using the per-stage `status` values added in phase 2.

The input mask matters here. Level 2 needs the *whole* mask the training run fed its cutter,
which is the app's segmentation output on the same photo — so level 2 is only meaningful once
level 0 has shown the app's mask matches. If level 0 fails, fix that first; a cutter fed a
different mask will miss the shoulder station for reasons that have nothing to do with the port.

### Level 3 — regressor reproduction (vendor step 7)

Already specified as check 2 in phase 1: all 1821 rows through the ONNX graph must reproduce
the CSV's `prediction` column within 1e-3 and its MAE within 1e-6 of `4.563722454911072`.
Re-run it here as a regression, since phase 3 changed how the vector reaches the graph.

One numeric detail from `VALIDATION.md` worth asserting rather than assuming: "XGBoost split
comparisons cast extracted doubles to float32 before tree traversal to match XGBoost numeric
input semantics." The ONNX path gets this for free — `FloatTensorType` is float32 — but the
app computes its Chen16 values as `double` and must narrow to float **before** the graph, not
inside it, and must do so identically to how the training CSV's values were produced. The
Hu moments are where this bites: `Hu_4` reaches 9.6e-09 and `Hu_5` 8.8e-08, close enough to
float32's subnormal region that a narrowing performed at a different point in the chain can
change a split decision. Assert level 3 passes with the vector narrowed at the app's own
boundary, not just with the CSV's stored values.

### Level 3.5 — end-to-end replay of the full eval set (new)

The three field photos were, until the dataset drop, the only end-to-end check available.
They no longer are. Every one of the 1821 `image_path` values in
`fixed_test_predictions.csv` resolves on disk under `Instaham/PIGRGB-Weight/RGB_9579/`
(fold1 226, fold2 319, fold3 241, fold4 625, fold5 410; map `/Instaham/data/raw/…` to
`Instaham/…`). So the whole native pipeline — segmentation, gates, cutter, features,
regressor — can be replayed on the exact captures the model was evaluated on, and scored
against per-row ground truth.

Run it and report, over all 1821 rows: MAE, RMSE, MAPE, and mean signed error against
`weight_kg`, versus `fixed_test_metrics.json`'s `4.5637 / 6.0063 / 3.7224% / -1.3579`. Also
report the same numbers per `source_group` against
`fixed_test_source_group_metrics.csv` and per weight band against
`fixed_test_weight_band_metrics.csv`, both of which ship alongside the model.

This is the number that actually says whether the port works. Levels 0–3 localize a fault;
this one says whether there is one. It should run before any device build. Do not treat a
level-3.5 MAE close to 4.56 as licence to skip level 4 — the eval captures are a fixed rig at
1.88 m and the field photos are not, so they test different things: level 3.5 tests the port,
level 4 tests the capture contract and `cm_per_px_target`.

### Level 4 — end-to-end on the three field photos

The three photos in `.pig_pictures/` with known weights (92, 96, 118 kg) are the only real
field data available. F37 already ran the Python cutter on them, giving the target the native
pipeline should approximately reproduce:

| Photo | true | app today (uncut, baseline5) | Python real cut (baseline5) |
|---|---|---|---|
| 92 kg | 92 | 90.0 (−2.1%) | 94.5 (+2.8%) |
| 96 kg | 96 | 110.3 (+14.9%) | 89.9 (−6.3%) |
| 118 kg | 118 | 107.7 (−8.7%) | 81.1 (−31.3%) — confounded, see F39 |

Two caveats carried forward: the 118 kg row is confounded by a segmentation rung mismatch
between harness and device (F39) and must not be read as a cutter result; and these numbers
are `baseline5`, so the Chen16 model will not reproduce them exactly. What must hold is the
direction and magnitude: the +16.6% systematic bias F36 attributes to the identity cutter has
to be gone. A residual bias above roughly ±8% across the two clean photos means something
other than the cutter is still wrong, and that is a new fix round.

Run this as a local Python replication of the native pipeline before building any APK. Only
after it passes is a device build worth the user's time.

### Level 5 — device

Build and sideload, run the three photos plus fresh captures, and read back
`cutterKeptFraction` and the persisted `featureVector` from phase 4's telemetry. Compare
`kept_fraction` against the training distribution (median around 0.95): a device median far
below that means the cutter is over-cutting on real captures in a way the eval masks never
exercised.

### `cm_per_px_target`

Resolve the plan's open question 1 here, with data. F38 measured, through `RA`, that `0.35`
needs only a ×0.99 to ×1.03 correction post-cut on two of three photos. Re-derive the same
way against `mask_area` directly (`mask_area` is `RA × 518400`, so this is the same
measurement without the frame division, and it is the feature carrying 94.5% of the model's
importance per `feature_importance.csv`). If the correction stays inside ±5%, keep `0.35` and
set `cm_per_px_target_uncertainty` down from `1.30` to something the measurement supports.
The 1.30 was justified by a three-sample estimate that also absorbed cutter inflation; with
the cutter real, that justification is gone and leaving it at 1.30 keeps the eligibility gate
looser than the calibration warrants.

This still is not the 1.88 m calibration capture [ADR-004](../adr/004-calibration-requires-repeat-captures.md)
asks for. Say so in the manifest's `cm_per_px_target_source` rather than implying otherwise.

## Steps

- [ ] Write the host Chen16 CLI over the app's `stages/` seam.
- [ ] Level 0 (vendor steps 1–3): whole-mask agreement with the Python reference, then the
      truncation verdict and the pre-Ji/Duan `body_curve`/posture result. Stop the ladder if
      step 1 disagrees.
- [ ] Level 1 (vendor step 6): 16-feature parity against `extract_chen16_features` over all
      3394 `MASK_3394` masks, `body_curve` first and alone. Record the achieved tolerances.
- [ ] Level 2 (vendor steps 4–5): Ji/Duan mask, selected shoulder, and final-mask geometry
      against the CSV's per-row cutter telemetry — `peak_route_type` and `selection_reason`
      exact-match first, then `final_mask_area_px`, the circle geometry, and the fractions.
      **Not** against `ML/pipeline/cutter.py`, which is a different cut protocol.
- [ ] Level 3: re-run the 1821-row ONNX reproduction after phase 3's rewiring.
- [ ] Level 3.5: replay the full native pipeline over all 1821 eval captures under
      `Instaham/PIGRGB-Weight/RGB_9579/`; report MAE/RMSE/MAPE/mean-signed-error overall,
      per source group, and per weight band against the three shipped metrics files.
- [ ] Level 4: local Python replication of the native pipeline over the three field photos.
- [ ] Re-derive `cm_per_px_target` and `cm_per_px_target_uncertainty`; update the export.
- [ ] Level 5: build, sideload, capture, read back the telemetry.
- [ ] Run `flutter analyze` and the full test suite (this change is cross-cutting).
- [ ] Run the `spec-drift` skill — model I/O and `assets/ml/manifest.json` both changed.
- [ ] Run the `pipeline-docs` skill — stage order, tensor shape, and the models loaded all
      changed. Flag two ADRs for it to write: one superseding
      [ADR-001](../adr/001-cutter-identity-stub.md) (the cutter is ported after all, and why
      that reasoning no longer holds), and one for the regressor and feature-family swap
      (baseline5 to chen16_noheight). Do not write them from this skill.
- [ ] Update AGENTS.md critical rule 2: the order is now the manifest's declared
      `feature_order` for the declared family, asserted in `export_xgboost.py` and
      re-asserted in `load_weight()` — not a literal `RA, LC, BL, BW, E`.
- [ ] Append one line to `docs/changelog.md`, clear `docs/plan.md` to the empty template, and
      delete `docs/plan-phase/`.
- [ ] Close `docs/fix.md` and delete `docs/fix-phase/` only if level 4 confirms the bias is
      resolved; otherwise open round 6 on whatever remains.

## Open questions

- **~~Fixtures.~~ — resolved by the dataset drop.** Level 1 uses the 3394 ground-truth masks
  in `Instaham/PIGRGB-Weight/MASK_3394/`; level 2 needs no mask fixtures at all, because the
  CSV's cutter telemetry carries the cut's decisions and its resulting area directly; levels
  3.5 and 4 replay from `RGB_9579/`, where all 1821 `image_path` values resolve. The
  `final_mask_cache` PNGs are still absent and are now known to be unobtainable locally
  (`ML/pipeline/cutter.py` is protocol v26, not V176/V144), but nothing depends on them.
  This was billed as the single largest schedule risk in the plan; it is closed.
- **Sample size for level 2.** Full 1821-row cutter parity is expensive to run. Proposal: 50
  rows stratified across the 14 source groups and the 7 weight bands, and the full set only
  if the 50 show any failure. Stratify on `peak_route_type` as well — the rare branches are
  where a port breaks, and four of the six values occur on fewer than 15 rows each
  (`v176_no_primary_break1_meet_cut` 12, `…_governing_peak_direct_cut` 6,
  `…_actual_peak_override_cut` 3, `…_forced_break1_fallback_cut` 1). A random 50 would very
  likely contain none of them.
- **Does the app's segmentation reproduce the training run's whole mask on `RGB_9579`?**
  `MASK_3394` covers the 3394 subset, which is disjoint from the 1821 eval rows (those are
  all `RGB_9579`). So level 0 can score segmentation against ground truth on `MASK_3394`, and
  levels 2/3.5 need it to hold on `RGB_9579` where there is no ground truth. If level 3.5's
  MAE is poor while levels 0–3 are green, an untested segmentation difference on `RGB_9579`
  is the first place to look.
