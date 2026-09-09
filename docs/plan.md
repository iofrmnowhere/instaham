# Plan: replace the weight regressor with the Chen16 XGBoost model

## Goal

Swap the shipped weight regressor from the `baseline5` model (`RA, LC, BL, BW, E`, 5
features) to the new XGBoost model in
`model_and_cutter/weight prediction/weight prediction/model.json`, which is a
`chen16_noheight` model taking 16 features. As with every other model in this app, the
booster JSON is converted to ONNX first (`ML/export/export_xgboost.py`) and the app runs the
ONNX graph through `OnnxRunner`; the vendored `XGBoostJsonPredictor.cpp` is a fallback only,
never the primary path.

The new model reports `MAE 4.56 kg`, `RMSE 6.01`, `R² 0.966`, `MAPE 3.72%` over 1821
held-out rows across 14 source groups (`fixed_test_metrics.json`).

## Why this is not a drop-in swap

The model change forces a feature-pipeline change, and that forces a cutter change:

1. **Feature vector**: 5 features to 16 (`mask_area, convex_hull_area, difference, dif_mask,
   body_curve, perimeter, outline_curve, longest, shortest, Hu_1..Hu_7`). This invalidates
   AGENTS.md critical rule 2 as written, `stages/feature_calculation.{h,cpp}`,
   `stages/weight_prediction.cpp`, `manifest.h`'s `WeightCapability`, the five per-feature
   `feature_domain` gates in `pipeline.cpp`, and the five `feature_*` database columns.
2. **Cutter**: every row of `fixed_test_predictions.csv` carries
   `cut_protocol_version = v176_strict_nonprimary_break1_region_meet_v144_fixed_center_bilateral_circle_v1`
   and `cut_required = True` — the model was trained **only** on head/neck-removed masks.
   The identity stub ([ADR-001](adr/001-cutter-identity-stub.md)) cannot feed it. That is
   the same defect `docs/fix.md` round 5 is open on, quantified at **+16.6% bias** in
   `docs/fix-phase/7-cutter-quantified.md` (F36).
3. **Supply**: `model_and_cutter/instaham_cpp_weight_runtime_v176_chen16/` ships C++ sources
   for exactly that cutter (V176 selector plus V144 circle cut), exactly those 16 features,
   and the two pre-Ji/Duan quality gates the training protocol ran. It needs only OpenCV,
   ONNX Runtime, and nlohmann/json — all three already vendored under
   `packages/instaham_ml_ffi/src/third_party/`. No new dependency. But per its own
   `VALIDATION.md` the package **has never been compiled**: the artifact environment lacked
   OpenCV and ONNX Runtime, so the only build check performed was a CMake configure, and
   every other contract claim was verified by reading. Treat "it builds" as real work.

So the swap is: convert the model, port the vendor cutter and Chen16 stack, rewire the
manifest, pipeline, and database around a 16-wide vector, and prove parity against the
Python reference that produced the training features.

## Design/Approach

- **The training contract is recoverable and unchanged.** `mask_area / RA == 518400` on all
  1821 rows, so the training frame is still **720x720** and `capture_contract` keeps
  `training_frame_px [720, 720]`, `training_camera_height_m 1.88`, and
  `camera_height_is_xgboost_feature false`. The scale-normalization block in `pipeline.cpp`
  (`k = cm_per_px_actual / cm_per_px_target`, then `scale_mask_to_training_space`) is reused
  as is; only what is measured on the scaled mask changes.
- **Python is the parity oracle for the features, but NOT for the cutter.** The CSV's
  `extended_feature_protocol_version` is `chen16_noheight_centerchord_v2`, which is exactly
  `ML/pipeline/feature_calculation.py::extract_chen16_features`, already in this repo. Every
  ported C++ *feature* is validated against that function rather than against the vendor
  package's own claims.

  The cutter has no such oracle. `ML/pipeline/cutter.py` declares
  `PROTOCOL_VERSION = "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26"` and contains no
  V176, V144, ShrinkingBall, SelleFilter, or Break1 machinery — it is the earlier two-tangent
  headfit lineage, a *different algorithm* from the `v176_…_v144_…_v1` protocol every CSV row
  was cut with. Diffing the ported C++ against it would compare two protocols, not measure a
  port. The vendor C++ is therefore the only implementation of the shipped cut protocol, and
  the cutter is validated against the CSV's own per-row cutter telemetry instead (see below).
- **The identity-stub widening multipliers go away.** `feature_domain`'s `upper_multiplier`
  and `lower_multiplier` exist only to tolerate an uncut mask. With the real cutter running
  they all return to `1.0`, and `cm_per_px_target` is re-derived rather than inherited — the
  current `0.35` absorbs cutter inflation (ref_fix F21, F38).
- **The CSV is the cutter oracle, and it is better than the final masks would have been.**
  All fifteen cutter-telemetry columns are populated on all 1821 rows: `final_mask_area_px`,
  `kept_fraction`, `removed_fraction`, `shoulder_station_fraction`, `break1_fraction`,
  `shoulder_selected_x`, `break1_x`, `circle_center_x`, `circle_center_y`,
  `final_circle_radius_px`, plus the categorical `peak_route_type` (6 distinct values) and
  `selection_reason` (7). And `final_mask_area_px == mask_area` on every row, so the CSV
  already carries the post-cut mask's exact pixel count. That means the ported V176 selector
  and V144 circle cut can be checked decision-by-decision and area-exactly per row, without
  the final-mask PNGs ever existing. A cached PNG would have given pixels; this gives the
  routing branch, the geometry, and the resulting area.

- **Order of work is deliberately regressor-last.** Phases 2 and 3 can be verified against
  the existing `baseline5` model, because the CSV carries both `RA..E` and the 16 Chen16
  columns computed from the same cut masks. The cutter port is therefore provable before the
  model swap, and a failure in one is never mistaken for a failure in the other.

## Inputs on disk

The PIGRGB-Weight source dataset is now present at `Instaham/PIGRGB-Weight/` (gitignored,
~9.6 GB, 16 366 files). Three subtrees:

| Subtree | Contents | What it unlocks |
|---|---|---|
| `RGB_9579/fold{1..5}/<group>/` | the raw captures the CSV's `image_path` column points at | **all 1821 test rows resolve on disk** (fold1 226, fold2 319, fold3 241, fold4 625, fold5 410) — end-to-end parity over the full eval set, not three field photos |
| `MASK_3394/<group>/` | binary 0/255 ground-truth segmentation masks, 960×540 | clean whole-pig masks to drive the feature port and the quality gates without depending on the app's own YOLO |
| `RGB_3394/<group>/` | the RGB images those masks pair with, 1:1 by filename | lets open question 3 (does the app's segmentation match the vendor's selection contract?) finally be measured against ground truth |

Path mapping: the CSV's `/Instaham/data/raw/PIGRGB-Weight/…` becomes `Instaham/PIGRGB-Weight/…`
— the `data/raw/` segment is dropped, everything after it matches exactly.

**Still absent, and now known to be unobtainable locally:** the
`weight_features_final_v144_circlecut_v1/final_mask_cache/` PNGs (1821 unique paths). They
cannot be regenerated in Python either, because `ML/pipeline/cutter.py` implements a
different cut protocol (see the Design note above). This no longer blocks anything — the
CSV's cutter telemetry replaces them — but no phase should be written as if they might turn up.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | ONNX export of the Chen16 booster | done | docs/plan-phase/1-onnx-export.md |
| 2 | Port the V176/V144 cutter, Chen16 features, and the two quality gates | done | docs/plan-phase/2-native-cutter-chen16.md |
| 3 | Manifest contract and native weight branch rewiring | done | docs/plan-phase/3-manifest-pipeline.md |
| 4 | Dart, persistence, and UI surface | done | docs/plan-phase/4-dart-persistence-ui.md |
| 5 | Parity, validation, and docs | not started | docs/plan-phase/5-parity-validation.md |

## Relationship to the open `docs/fix.md`

`docs/fix.md` (round 5, "the weight branch overestimates because the mask it measures still
has the head on it") remains the active fix document and stays open. Its root cause is
resolved *by* phase 2 of this plan rather than by a separate patch. Close `docs/fix.md` only
after phase 5 re-measures the three field photos in `.pig_pictures/` and confirms the bias is
gone. If phase 5 finds a residual bias with a different cause, that is a new fix round, not
this plan's scope.

## Open questions

1. **`cm_per_px_target`.** The shipped `0.35` was fitted with the identity cutter in the loop
   and knowingly absorbs its inflation. Phase 5 re-derives it from the post-cut field masks.
   F38 already puts the correction at x0.99 to x1.03 on two of three photos, implying `0.35`
   is close to right even post-cut — but that was measured through `RA`, and the Chen16
   vector is dominated by `mask_area`, which is the same quantity un-normalized. Decide from
   measurement, not inheritance.
2. **Domain bounds are test-split only.** `fixed_test_predictions.csv` is 1821 held-out rows;
   the full training range is wider. Either widen the derived bounds by a stated margin or
   accept a gate slightly stricter than the model's true competence. Recommendation: derive
   from the test split, then widen each bound by that split's own 5th/95th-percentile-to-
   min/max spread rather than by a guessed multiplier.
3. **Does the app's segmentation output satisfy the vendor's selection contract?** The vendor
   package specifies `cleaned_target_instance_v1` mask selection; the app implements its own
   scoring in `stages/segmentation.cpp` plus the F19 retry ladder. Phase 2 feeds the app's
   mask to the cutter unchanged, and phase 5 must confirm the cutter behaves on it. If it
   does not, that is a segmentation-selection change and needs its own ADR.
   **Now measurable:** `MASK_3394` + `RGB_3394` give 3394 ground-truth mask/image pairs, so
   the app's segmentation can be scored against truth directly (IoU per image) instead of
   inferred from downstream weight error. Phase 5 level 0 does this.
4. **~~`quality_gates/` out of scope~~ — resolved, they are in scope.** An earlier revision of
   this plan deferred the truncation and posture gates. That was wrong: `VALIDATION.md` lists
   "whole-mask truncation and body-curve/posture gates occur before Ji/Duan" as a package
   contract check, and `tests/README.md` makes them steps 2 and 3 of the seven-step parity
   ladder — ahead of the cutter. The training data was produced with both gates active, so
   skipping them means the app accepts photos the protocol rejected and phase 5 cannot claim
   parity. Phase 2 now ports both detectors; phase 3 gates their activation on a manifest
   switch so they can ship dark until phase 5 measures their real rejection rate.
5. **~~Which masks drive the feature-parity test?~~ — resolved, `MASK_3394`.** The plan
   originally assumed it needed the vendor's `final_mask_cache` PNGs. It does not. The
   feature port needs *a* mask, not *the* final mask: `extract_chen16_features` is a pure
   function of whatever binary mask it is handed, so running it and the C++ port over the
   same input is a complete test of the port regardless of whether that input was ever cut.
   Ground-truth masks are in fact the better input, because they take the app's own YOLO out
   of the loop and isolate the feature arithmetic completely.

## Plan rating: 7/10

**Pros.** Every input now exists on disk: the model, the C++ cutter sources, the Python
feature oracle, an eval CSV that pins the training contract exactly (720x720 recovered to the
pixel) *and* carries fully-populated per-row cutter telemetry, and — new — the PIGRGB-Weight
dataset itself, so all 1821 eval rows can be replayed from the original captures and 3394
ground-truth masks are available to isolate the feature port. The phase order lets the cutter
be proven against the *old* model before the new one lands, so the two changes never mask
each other. No new third-party dependency is introduced. It also closes the single largest
known error source in the product (+16.6%, F36).

**Cons.** The scope is genuinely large for one plan: it touches the export toolchain, roughly
31 new native source files, the manifest schema, the pipeline gate, a Drift migration, and
the rejection UI. `cm_per_px_target` remains an unresolved calibration, so a good phase-5
number could still sit on a wrong scale. And the cutter port has no reference implementation
to diff against at all — `ML/pipeline/cutter.py` is a different protocol (v26 two-tangent
headfit, not V176/V144), so a cutter bug surfaces only as a numeric disagreement with the
CSV, never as a side-by-side stage dump.

~~The riskiest algorithmic step — matching `body_curve`'s skeleton thinning between Python
and C++ — is exactly the one the vendor flags twice as most likely to disagree~~ — resolved
in phase 2: the mismatch was skimage's `method='zhang'` being a compiled 256-entry LUT
rather than the textbook Zhang-Suen algebraic conditions, not the zero-border padding. A
vendor-supplied LUT patch closed the feature-port gate to 0 mismatches on all 20 masks. The
vendor package was also confirmed to compile after only one unrelated syntax fix, so "never
been compiled" is no longer an open risk either — see phase 2's Results.

Raised from 6 to 7 on the dataset drop, then held at 7 rather than raised further because
`cm_per_px_target` and the cutter's lack of a reference implementation are still open. The 6
was set when the plan believed the feature port could only be checked against a
`final_mask_cache` that is not in this repo. Those PNGs are still absent and now known to be
unregenerable locally, but they turned out not to be needed: ground-truth masks test the
feature port more cleanly, and the CSV's cutter telemetry (`final_mask_area_px == mask_area`
on all 1821 rows, plus the V176 routing branch and the V144 circle geometry per row) tests
the cutter port better than a cached mask would have. This would rate 8 with the ADR-004
calibration capture in hand.
