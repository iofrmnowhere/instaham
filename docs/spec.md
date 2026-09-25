# Model I/O Spec

Re-checked on 2026-09-25 after `docs/plan-4.md` (round 4, two-stage health cascade) phases
1-3. **These are legitimate, intended changes, not drift.** The health section was stale in
two ways, and both are now described in place under the Health classifier section:

- It still called `segmentation_crop` and `segmentation_masked` stubs. `docs/plan-3.md`
  implemented both.
- It did not describe the cascade. The manifest gained a `health.cascade` block, and
  `envelope["health"]` gained a `cascade` object.

The health model file, its sha256, `classes.json`, the input tensor, the preprocessing
constants, and the first-pass `protocol` (`full_frame`) are unchanged. The manifest diff
against `HEAD` also drops the segmenter's `input_scale` block, which the 2026-09-19 entry
below already records. The other three graphs, `feature_order`, `cm_per_px_target` (0.34) and
both quality-gate switches were not touched by this round.

Re-checked on 2026-09-22 after `docs/fix-4.md` round 8 phase 5 (phase 6 added no model I/O —
see below). **Legitimate, intended additions — README §16/§17 debug scalars and shipped
invariants, not drift.** `envelope["segmentation"]` gained `resize_factor`, `normalized_w`/`h`
(now set on every run, not only the §6 halt), `x_offset`/`y_offset`, `rotated_width`/`height`,
and (on the halt path) `cm_per_px_actual` alongside the halt dimensions.
`envelope["construction"]` gained `base_mask_w`/`h`. `envelope["cutter"]` gained
`base_mask_w`/`h`, `final_mask_w`/`h`, `final_mask_added_px`, `final_mask_removed_px`, and a
new declared-failure reason, `final_mask_not_subset_of_base` — README §17's "FINAL_MASK
foreground ⊆ BASE_MASK foreground" check, shipped **tolerance-gated** rather than literal:
the vendor cutter's Ji/Duan gap-fill legitimately adds a small number of foreground pixels
beyond the base mask (measured 0.037% of base-mask area on one corpus A photo), so the reason
fires only above `kMaxTolerableAddedMaskPxFraction` (0.01, `pipeline.cpp:72`), not on any
added pixel — see `docs/adr/016-final-mask-subset-check-tolerance-gated.md`. These fields are
documented in place in the Segmenter Output and Envelope sections below. Phase 6 (capture
orientation / head-direction attestation) added no model input, output, or envelope field —
those two values live on the Dart-side `ScanRecords` row only, never crossing into the native
envelope — so it is out of scope for this file. Everything else re-checked and unchanged from
the 2026-09-19 entry below: the four graphs' shapes, `feature_order`, `cm_per_px_target`
(0.34), `training_frame_px`, `min_mask_diagonal_fraction`, both quality-gate switches, and the
normalize-first composition itself.

Re-checked on 2026-09-19 after `docs/fix-4.md` round 8 phase 4. **Two legitimate changes,
both intended (the round's own designated specification, not drift).** The segmenter's canvas
composition changed from the round-4 scale-aware-or-plain-letterbox choice with a
`[1.0, 1.32, 1.68, 0.77]` retry ladder to the README's single normalize-first pass at
`cm_per_px_target`, with a halt (not a fallback) when the normalized content overflows the
960×540 canvas; the manifest's `segmentation.input_scale` block, which fed that ladder, is
removed rather than superseded. The weight regressor's `k` is now fixed at `1.0` rather than
computed from `cm_per_px_actual / cm_per_px_target`, because the photograph is already
resampled to `cm_per_px_target` before the segmenter runs. Both are described in place below;
see `docs/fix-phase-4/4-app-wiring.md`'s Result section for the verification (a real
`instaham_ml_run_pipeline_request_json()` run matched `weight_branch_cli.exe` bit-for-bit on
the same corpus A image). Everything else — the four graphs' shapes, the view/health
contracts, `feature_order`, `cm_per_px_target` itself (0.34), `training_frame_px`,
`min_mask_diagonal_fraction`, both quality-gate switches — verified unchanged.

Derived from the code and from `assets/ml/manifest.json` as they stand now. The view, health,
and segmenter contracts below were re-checked on 2026-09-07 and are unchanged; the **weight
regressor section was rewritten** — the shipped family moved from 5-feature `baseline5` to
16-feature `chen16_noheight` (plan phases 1–3), and that was legitimate, intended change, not
unintended drift.

Re-checked again the same day after `docs/fix-2.md` phase 1 and 1.1 closed. Three legitimate
changes were folded in — `weight.available` is now `true` under the `--enable-for-testing`
override (F42), the unscaled cutter fallback is capped (F43), and `jiduan_threw` joins the
cutter statuses (F44) — plus one genuine mismatch, flagged rather than absorbed at the time and
since fixed in the exporter; see the bottom of this file. The segmenter's `input_scale` block briefly went missing from the manifest
during phase 1 and was restored (F50); the values below match the manifest again and never
needed changing here.

Re-checked on 2026-09-14. **One legitimate change, no open mismatches.**
`capture_contract.cm_per_px_target` moved **0.3289473684210526 → 0.34**, with
`cm_per_px_target_source` now
`host_scale_sweep_round28_f59_measured_mae_minimum_scale_constant_sweep_results_2_md`. This is
the first time the constant has shipped with an accuracy measurement on the current post-F55
path behind it: round 28's host sweep re-ran the question the 2026-09-13 entry below left open,
and both corpora minimize MAE independently at 0.34 (corpus B 2.1%, corpus A 4.0%) against
4.1%/7.4% at the fitted 0.35 and 5.4%/7.7% at the derived value that was shipping
(`docs/scale-constant-sweep-results-2.md`, `docs/adr/012-measured-scale-target.md`, which
supersedes ADR-011's constant choice). `capabilities.weight.note` was updated in the same pass
to name ADR-012 and to state the residual error rather than the superseded ADR-011 rationale.

Manifest and exporter moved **together this time** — `ML/export/export_xgboost.py:304` writes
0.34 and the new note, `assets/ml/manifest.json` was produced by re-running that exporter and
`ML.export.build_manifest` rather than hand-edited, and the fragment's `capture_contract` and
`note` were verified byte-equal to the shipped manifest's. A re-export today changes nothing.
`weight.regressor`'s sha256 changed with the re-export (same model, re-serialised) and the
manifest records the new digest; `build_manifest --check` passes and all six declared digests
match the files on disk. Everything else verified unchanged: 16-name `feature_order`,
`chen16_noheight`, `n_estimators` 600 / base score 121.669 / `reg:squarederror`,
`training_frame_px` [720, 720], `training_camera_height_m` 1.88, `feature_space`
`fixed_camera_pixels`, `cm_per_px_target_uncertainty` 1.30, `min_mask_diagonal_fraction` 0.35,
both quality gates `false`, the segmenter's `input_scale` (1.10, ladder `[1.0, 1.32, 1.68,
0.77]`, retry 0.10) and `postprocess` (conf 0.25, iou 0.70), and the view/health contracts.

Re-checked on 2026-09-13. One legitimate change to the contract and **two open mismatches**.
The change: `capture_contract.cm_per_px_target` moved **0.35 → 0.3289473684210526**, with
`cm_per_px_target_source` now
`pigrgb_floor_plane_304ppm_theoretical_geometry_INSTAHAM_CAMERA_SCALE_NORMALIZATION_md`. The
constant is again the derived `100 / 304` PIGRGB floor-plane value, which reverses what the
2026-09-09 entry below settled; the reasoning is in
`docs/adr/011-derived-scale-target.md`, and no accuracy measurement supports the new value yet
— the host sweep that favoured 0.35 was run before round 7's composed transform and therefore
measured a code path the weight branch no longer runs. Everything else verified unchanged: all
six declared sha256 digests still match the files on disk, every model asset is still dated
2026-09-09, `feature_order.json`'s 16 names equal the manifest's `feature_order`,
`feature_order_sha256` and `meta_sha256` both match, `n_estimators` 600 / base score
121.669174 / `reg:squarederror` / `chen16_noheight` unchanged, the segmenter's `input_scale`
(1.10, ladder `[1.0, 1.32, 1.68, 0.77]`, retry 0.10) and `postprocess` (conf 0.25, iou 0.70)
unchanged, both quality gates still `false`, `min_mask_diagonal_fraction` still 0.35, and the
view/health input and output contracts unchanged.

**Mismatch 1 — resolved 2026-09-13.** `capabilities.weight.note` used to read
*"cm_per_px_target is an empirical fit awaiting phase 5's field re-derivation,"* which described
0.35, not the derived value that ships — the same defect class as the mismatch resolved
2026-09-09 at the bottom of this file, a wrong justification attached to a warning whose second
clause (the ~73 kg floor) is still true. It now names the derived PIGRGB floor-plane value and
ADR-011, and states that the value is unmeasured on the current pipeline. Fixed in both places:
`ML/export/export_xgboost.py:241` writes the new text, and `assets/ml/manifest.json` was
hand-edited to match so the shipped asset did not have to wait for a re-export. Descriptive
text only — nothing in `manifest.cpp` or Dart reads it — and no model digest changed.

**Mismatch 2 — resolved 2026-09-13.** The exporter previously hardcoded `"cm_per_px_target":
0.35` with the `host_scale_sweep_round6_f49_empirical_fit_not_derived` source tag
(`ML/export/export_xgboost.py:302-306`), which would have silently reverted the constant on
the next re-export. It now writes `0.3289473684210526` with the
`pigrgb_floor_plane_304ppm_theoretical_geometry_INSTAHAM_CAMERA_SCALE_NORMALIZATION_md` source
tag, matching the hand-edited manifest. Generator and shipped asset agree on this field; a
re-export today would not change `cm_per_px_target`.

Re-checked again on 2026-09-09 after `docs/fix-2.md` phase 2 was decided and applied. One
legitimate change: `capture_contract.cm_per_px_target` moved back **0.3289 → 0.35** by
re-export, with its `_source` tag now
`host_scale_sweep_round6_f49_empirical_fit_not_derived`. This closes the round the 2026-09-08
entry below left open — the host sweep in `ML/host_scale_test/` measured both constants against
the shipped models and the real V176/V144 cutter over five PIGRGB images and 0.35 won on MAE
(11.5% vs 19.0%) and on every image individually
(`docs/scale-constant-sweep-results.md`). It is still an **empirical fit, not a derived
constant** — see the weight Output section. The regressor's `xgboost.onnx` sha256 changed
again, which is only the re-export's non-determinism over the same `model.json`, not a new
model; `feature_order.json` and `xgboost.meta.json` were regenerated with identical content.
The manifest rebuild dropped 28 `baseline5` `RA/LC/BL/BW/E` `feature_domain` keys that HEAD
still carried, which is the intended retirement of that family from the shipped manifest, not
a loss. Nothing else moved: the segmenter's `input_scale` (1.10, ladder
`[1.0, 1.32, 1.68, 0.77]`), the 16-feature order and its `feature_domain`, the quality-gate
switches, and the view/health contracts all verified unchanged.

The 2026-09-08 entry that follows is retained for provenance; its "revert is expected but not
taken" state is now superseded by the paragraph above.

Re-checked on 2026-09-08 after `docs/fix-2.md` phase 2's sweep. One legitimate change:
`capture_contract.cm_per_px_target` moved 0.35 → **0.3289** (and its `_source` tag with it) by
re-export, to run the 0.3289 half of phase 2's comparison. It was recorded as the current
manifest state, **not** as a settled contract — the sweep argued for reverting it, and that
decision was open at the time.

Four ONNX graphs. `OnnxRunner` consumes outputs **positionally, in declaration order** —
output names are never looked up, so a re-export that reorders outputs breaks the pipeline
silently. Input names are recorded in the manifest for reference only; the runner passes a
single input tensor.

Every model receives an **already-EXIF-normalised** image. Correction happens once, Dart-side
at capture (`ImageService.processRawBytes` → `bakeOrientation`); the native layer never
rotates.

## View classifier — `assets/ml/view/model.onnx`

MobileNetV4-Conv-Small, opset 17, `protocol_version: view_v2` (replaced GhostNetV3-100
`view_v1`; docs/adr/006-view-classifier-swapped-to-mobilenetv4.md). Input shape,
preprocessing, output mapping, and gating contract below are unchanged by the swap.

### Input
- Shape: `1x3x224x224`, NCHW, RGB, float32. Input name `input`.
- Preprocessing: decode → resize shorter side to 255 (bilinear) → centre crop 224 →
  `(v * 1/255 − mean) / std`, mean `[0.485, 0.456, 0.406]`, std `[0.229, 0.224, 0.225]`.
  Runs on the raw photo, before segmentation; it has no input-protocol switch.

### Output
- Format: `[1, 3]` logits, positionally mapped to `view/classes.json`:
  `dorsal_valid` 0, `health_only` 1, `reject` 2. Class count is checked against
  `classes.json` at runtime; a mismatch is `INSTAHAM_ML_ERR_CONTRACT`, never a guess.
- Postprocessing: softmax → argmax label + confidence + full per-class probability map.
- Contract: the label **gates the whole graph**. `reject` stops the pipeline;
  `health_only` skips segmentation; `dorsal_valid` runs everything. Any other value, or an
  unavailable capability, fails closed with every downstream stage `skipped`.
- User route override (round 9 [ADR-017](adr/017-user-consent-view-gate-override.md), widened
  in round 10 by [ADR-020](adr/020-view-route-override-either-route.md)): the request-shaped
  entrypoint's `view_route_override` (`"dorsal_valid"` / `"health_only"`) changes the route,
  never the label. `stages::resolve_view_route()` (`src/stages/view_route.h`) decides it:
  `dorsal_valid` is never changed, `health_only` can be raised to `dorsal_valid`, and `reject`
  can take either route instead of stopping. The legacy boolean `view_gate_override: true`
  means `"dorsal_valid"` and is read only when `view_route_override` is absent or not a string.
  When the resolved route differs from the un-overridden one (`pipeline.cpp:296-306`), the
  envelope's `view` block gains `"override": true` and `"override_route": "<route>"`; a no-op
  override leaves the block unchanged. *Added 2026-09-25: the spec had not recorded round 9's
  boolean override at all; both rounds are captured here.*

## Health classifier — `assets/ml/health/model.onnx`

GhostNetV3-100, opset 17, `protocol_version: health_v1`.

### Input
- Shape: `1x3x224x224`, NCHW, RGB, float32. Input name `input`.
- Preprocessing: identical to the view classifier — same resize/crop/normalization
  constants, shared code path (`resize_shorter_then_crop` in `health_input.cpp`).
- Input protocol: the manifest's `health.input.protocol` is `full_frame`, and that is the
  **first pass**. `segmentation_crop` and `segmentation_masked` are implemented
  (`docs/plan-3.md`), ported from `ML/parity/reference_health_input.py`: the pig region's box
  is padded by `bbox_padding_ratio` (0.06) and cropped, and `segmentation_masked` also fills
  every pixel outside the pig mask with `background_fill` (`imagenet_mean`, the ImageNet mean
  as uint8 RGB) before the same resize-shorter-255 / centre-crop-224 preprocessing.
  `abnormality_crop` is still a stub that falls back to full frame. A region protocol with no
  valid region, or with an all-zero mask, falls back to full frame
  (`on_segmentation_failure: full_frame`). The envelope always reports
  `input_protocol_requested`, `input_protocol_applied`, `input_degraded` and `region_source`
  (`none` / `bbox` / `mask`), so a scan can never claim a crop that did not happen.
- Region: `pipeline.cpp` builds the region only from the construction stage's pig mask
  (`pig_region_from_base_mask()`, BASE_MASK coordinates divided by
  `SegmentationOutput::content_scale` back into the original photo). The `health_only` route
  and any run without a mask pass no region.
- **Two-stage cascade** (`docs/plan-4.md`, manifest `health.cascade`: `enabled: true`,
  `healthy_label: "Healthy"`, `second_stage_protocol: "segmentation_masked"`). The first
  pass runs on the whole photo. If its label is `healthy_label`, that result is final. If
  not, and a region **with a mask** exists, the model runs a second time with
  `second_stage_protocol`, and that second result becomes the final envelope. A bbox with no
  mask counts as no region, because the masked pass would then repeat the first. If the second
  pass fails or falls back to full frame, the first result stays final. A manifest `cascade`
  block with an unknown `second_stage_protocol`, or a `healthy_label` not in `classes.json`,
  disables the cascade rather than failing the load. The reason is held in
  `ClassifierCapability::health_cascade_disabled_reason`, but it is **not** written to the
  envelope.

### Output
- Format: `[1, 10]` logits over `health/classes.json`: `Healthy` 0, then nine
  `Infected_*` classes (bacterial erysipelas, greasy pig disease, environmental dermatitis,
  sunburn, fungal pityriasis rosea, ringworm, parasitic mange, viral FMD, swinepox).
- Postprocessing: softmax → argmax label + confidence + probability map.
- Cascade envelope: when the cascade is enabled, `envelope["health"]` is the final pass's
  classifier output plus a `cascade` object: `version` (`cascade_v1`), `enabled` (`true`),
  `second_stage`, `final_stage` (the `input_protocol_applied` of the pass that is final), and
  `first` (`label`, `confidence`, `probabilities` of the whole-photo pass). `second_stage` is
  one of `not_needed_healthy`, `ran`, `no_region`, `second_stage_failed` or
  `second_stage_degraded`. `disabled` exists in the code but cannot appear in practice: with the
  cascade off, the envelope is exactly the single-pass `run_classifier()` output, with **no**
  `cascade` key.
- `instaham_ml_classify_health_json` stays **single-stage**. It has no segmentation output to
  draw a region from, so it never runs the cascade. The app uses the full pipeline entrypoint,
  not this one.
- Dart persistence: `run_and_persist_pipeline_use_case.dart` stores `cascade.final_stage` in
  the existing `HealthResults.preprocessingVersion` column as `cascade_v1:<final_stage>`, or
  null when there is no `cascade` key. This needed no schema change. The results screen shows
  its re-check wording only for `cascade_v1:segmentation_masked`, and never presents that
  result as a confirmed diagnosis.
- Contract: independent of the weight branch. A failed weight branch must never suppress
  this result, and health runs on both the `dorsal_valid` and `health_only` routes. Only the
  `dorsal_valid` route can reach a second pass, because only it builds a region.

## Segmenter — `assets/ml/segmentation/yolo.onnx`

YOLO11s-seg with LDConv + ACmix, opset 17,
`protocol_version: yolo11s_ldconv_acmix_fixed_seed42`.

### Input
- Shape: `1x3x640x640`, NCHW, RGB, float32 in `[0,1]` (plain `v/255`, **no** ImageNet
  normalization — unlike the two classifiers). Input name `images`.
- Canvas composition (`docs/fix-4.md` round 8, README-specified): a required
  user-confirmed `cm_per_px` (`cm_per_px_actual`) and `capabilities.weight.cm_per_px_target`
  are resized to exactly `cm_per_px_target` (`resize_factor = cm_per_px_actual /
  cm_per_px_target`), rotated 90° clockwise if that leaves the content portrait, then centred
  unresized on a fixed 960×540 canvas (letterbox fill 114). A missing/invalid reference or an
  unavailable weight capability is a declared segmentation failure — there is no
  plain-whole-frame fallback and no retry ladder; this is the pipeline's only composition.
  If the normalized, rotated content does not fit 960×540, this halts (`oversize`, README
  §6) rather than enlarging the canvas or shrinking the content — surfaced through the whole
  envelope (`segmentation`/`scale`/`cutter`/`features`/`weight`, each carrying
  `normalized_w`/`normalized_h` and the 960×540 bound). The manifest's old
  `input_scale` block (a legacy per-canvas cm/px base, a multiplier ladder, and a lowered
  retry confidence threshold) is removed; it fed the retry ladder this round deletes.

### Output
- `outputs[0]`: `[1, 4 + nc + 32, num_anchors]` — `cx, cy, w, h`, then `nc` class scores,
  then 32 mask coefficients. **`nc` is derived** as `channels − 4 − num_coeffs`, never
  assumed to be 1.
- `outputs[1]`: `[1, 32, proto_h, proto_w]` — prototype plane, 160×160 at mask ratio 4.
- Postprocessing: threshold at `conf` 0.25 → single-class NMS at `iou` 0.70 → select the
  candidate with the largest sigmoid-thresholded mask area **cropped to its own detection
  box** (`mask_geometry.h`, shared with construction so the two cannot diverge) → decode
  coefficients × prototype → crop → bilinear upsample to 640 → threshold 0.5 → unletterbox
  with the carried pad/scale → nearest-neighbour resize to original dimensions.
- Mask protocol: `original_coordinate_polygon_v1`. Letterbox parameters are carried through
  on `SegmentationOutput` verbatim and never recomputed downstream.
- No detection above threshold is **not** an error; an instance is never fabricated.
- Debug/assertion scalars (`docs/fix-phase-4/5-debug-and-assertions.md`, README §16/§17), in
  `envelope["segmentation"]` on every run: `resize_factor`, `normalized_w`/`h`, `x_offset`/
  `y_offset`, `rotated_width`/`height`. `envelope["construction"]` gains `base_mask_w`/`h`.
  These are cheap and shipped so a coordinate bug is visible from a saved envelope without a
  code read; see the Envelope and ABI section for the cutter-side counterparts.

## Weight regressor — `assets/ml/weight/xgboost.onnx`

XGBoost, **600 estimators**, `reg:squarederror`, base score 121.669174, target `weight_kg`,
feature family **`chen16_noheight`** (replaced `baseline5`; docs/plan.md phases 1–3). Export
self-check `onnx_max_abs_diff` 2.9e-4 kg, reproduced test MAE 4.564 kg.

The feature contract is **manifest data, not compiled-in**
(docs/adr/007-manifest-declared-feature-family.md): `capabilities.weight.feature_family`,
`feature_order`, and a `feature_domain` map keyed by feature name. Nothing in the native
layer or the Dart layer names a feature.

### Input
- Shape: `[None, 16]` float32, graph input name `input` (opset domain `ai.onnx.ml`).
  Native packing is `[1, N]` where `N` is the manifest's `feature_order` width; a width the
  loaded graph disagrees with is refused, never truncated or padded.
- Order is fixed and non-negotiable: **`mask_area, convex_hull_area, difference, dif_mask,
  body_curve, perimeter, outline_curve, longest, shortest, Hu_1 … Hu_7`**. Asserted three
  times — at export against `CHEN16_NOHEIGHT` in `ML/export/common.py`, at manifest load
  against `weight/feature_order.json` and the compiled-in per-family constant, and in the
  packing itself. A manifest whose order disagrees fails to load with
  `INSTAHAM_ML_ERR_CONTRACT`. (AGENTS.md rule 2's `RA, LC, BL, BW, E` now describes the
  retained `baseline5` rollback family only, not the shipped one.)
- Features are measured on the **final V176/V144 cut mask** — the head/neck-removed mask the
  model was trained on — after the mask is resampled into the regressor's training pixel
  space by `k` (**target currently 0.34 cm/px**, round 28's measured MAE minimum on both host
  sweep corpora — see the calibration note below; 720×720 training frame). As of
  `docs/fix-4.md` round 8 phase 4, `k` is fixed at **`1.0`**, not computed from
  `cm_per_px_actual / cm_per_px_target`: the segmenter (see the segmenter's Input section
  above) already resampled the photograph to `cm_per_px_target` before it ran, so the mask
  handed to `transform_mask_to_training_space()` is already in the training pixel space, and
  computing `k` again from `cm_per_px_actual` would double-apply the scale. `cm_per_px` still
  comes **only** from the user-confirmed reference object, gating whether this path runs at
  all — there is no implicit fallback if it is missing. `chen16_noheight` values are raw
  pixel counts and lengths on that mask — there is no `RA`-style frame denominator and no
  additional linear scaling.
- When no scale is available (no reference marked, or a rejected one), the cutter still runs
  for telemetry on an **unscaled** mask, but that mask is now capped: `pipeline.cpp`'s
  `kUnscaledCutterMaxDimPx` (2880, the bound the scaled path already guarantees at
  `training_scale` 720 × `kMaxValidHeightRatio` 4.0) resamples it down before
  `cut_body_mask` sees it (`docs/fix-phase-2/1-cutter-freeze.md` F43). Features measured on
  that path are labelled `measured_on: uncut_mask_unnormalized` and are never weight input —
  the cap changes only the pixel budget handed to the cutter, not `scale_ok` or anything
  gated on it.
- Per-feature metadata in `feature_domain` (from `ML/export/export_xgboost.py`'s family meta
  tables): `dimension` ∈ {`area`, `linear`, `dimensionless`} and a boolean `gate`.

| `gate` | `dimension` | Features |
|---|---|---|
| `true` | `area` | `mask_area`, `convex_hull_area`, `difference` |
| `true` | `linear` | `perimeter`, `longest`, `shortest` |
| `false` | `dimensionless` | `dif_mask`, `body_curve`, `outline_curve`, `Hu_1`–`Hu_7` |

### Output
- Format: `[None, 1]` float32, graph output name `variable`; `outputs[0].data[0]` is
  kilograms.
- Postprocessing: no transform. Two gates surround it, and **both act on gated features
  only** — a **pre**-gate against the widened `feature_domain` bounds (per-feature
  multipliers, all `1.0` on this family, times `cm_per_px_target_uncertainty` 1.30 raised to
  the feature's `dimension` exponent: squared for areas, first power for lengths, untouched
  for dimensionless), and a **post**-check against the *unwidened* trained `[min, max]` that
  sets `extrapolated` + `extrapolated_features` when the ensemble can only answer from an
  edge leaf.
- Because no dimensionless feature is gated in either family's current export meta,
  `classify_domain_violation()`'s `mask_shape_out_of_domain` branch is **unreachable** with a
  manifest produced by the current exporter. A degenerate mask is caught upstream instead, by
  `min_mask_diagonal_fraction` (0.35) and the posture quality gate.
- Standing caveat: **`capabilities.weight.available` is now `true`**, set deliberately by
  re-exporting with `--enable-for-testing` for on-device verification
  (`docs/fix-phase-2/1-cutter-freeze.md` F42). Estimates therefore ship, and every one of them
  is real inference carrying the envelope's explicit provisional-calibration `note`, never a
  fabricated value. The calibration is a host measurement, not a field calibration.
  `cm_per_px_target` now reads **0.34** with `cm_per_px_target_source:
  host_scale_sweep_round28_f59_measured_mae_minimum_scale_constant_sweep_results_2_md`, applied
  2026-09-14 by re-running the exporter and `ML.export.build_manifest`, not by hand-editing
  (`docs/adr/012-measured-scale-target.md`).
- **The shipped constant is measured on the current path, within a plateau.** Round 28's sweep
  (`docs/scale-constant-sweep-results-2.md`, 2026-09-14) re-ran the comparison on the post-F55
  composed `transform_mask_to_training_space()` over two corpora reported separately —
  `PIGRGB-Weight/sub_1.88/` (4 informative rows) and `.pig_pictures/` (3) — and both minimize
  MAE at **0.34**: 2.1% with +0.2% bias, and 4.0%. The response through 0.32–0.36 is a shallow
  bowl, so the *band* is the durable finding and the exact minimum is not, at seven rows.
  **Quote these only as host figures, corpora separate, never as device numbers**; corpus B is
  the regressor's own training distribution, so its agreement is partly memorisation. The
  earlier `docs/scale-constant-sweep-results.md` (0.35 beating 0.3289 on MAE 11.5% vs 19.0%)
  measured the pre-F55 double-rasterisation path over the retired `sub_1.78/` corpus and must
  not be cited. `cm_per_px_target_uncertainty` stays 1.30 — a seven-row host sweep is not a
  field calibration, and the 1.88 m calibration capture is still owed.
- **Scaling is not the dominant error term, and this is now measured.** A `k = 1.0` arm — the
  target set to corpus B's own `cm_per_px_actual`, making the resample a proven no-op with
  `mask_area_px` unchanged rather than merely close — still leaves 5.42% MAE, +5.35% bias and
  one image at +14.29%. That residual belongs to segmentation, the cutter, feature extraction,
  the regressor or the 304 px/m geometry, and bounds what any value of this constant can
  achieve. It is not an I/O contract term; it is named here and owned elsewhere.
- **A second error term sits below the constant.** The 2026-09-09 sweep found the regressor cannot
  emit a prediction below roughly 73 kg: both light test pigs fell under the trained minimum on
  every gated size feature, so the ensemble answers from its floor leaf and no value of
  `cm_per_px_target` moves those rows. The two in-domain pigs predicted within ±5% at 0.35 then, so
  the geometry chain is sound and the gap is the regressor's training coverage at the low end.
  This is a model-coverage limit, not an I/O contract term, so it is named here and owned
  elsewhere. A returned number is provisional, and for a pig under about 85 kg it is
  systematically high.
- Consequence of that flag, worth stating because it changes which reasons are reachable:
  `weight_pending_field_validation` lives only in `pipeline.cpp`'s `weight_unavailable_json`,
  which every branch assigns on the `weight_override == false` side of its ternary. With the
  override active that reason **cannot fire**, and neither can the Dart message keyed to it
  (`run_and_persist_pipeline_use_case.dart:411`, the cutter-decline sentence). Rejections now
  surface their real cause instead — `mask_implausibly_small`, a domain-gate reason, a quality
  gate, or `cutter_failed`.
- The standalone `instaham_ml_predict_weight_json` entrypoint was **not** migrated: it still
  emits a `baseline5` feature block, `qc.cutter: "identity_stub"` and
  `cutter_protocol_implemented: false`. It is a debug-only path; `instaham_ml_run_pipeline_*`
  is the shipped contract and the one this section describes.

## Quality gates (pre-cutter)

`capabilities.weight.quality_gates` declares `truncation` and `posture` (with
`posture_max_bend_deg` 40.0). Both are **`false`** in the shipped manifest. When switched on
they run on the whole mask in original capture coordinates, before Ji/Duan and before scale
normalization, and report under `envelope["quality_gates"]` whether or not they reject
(`truncation_gate_rejected` / `posture_gate_rejected`). They are a manifest switch, not a
rebuild.

## Envelope and ABI

Payloads cross `dart:ffi` as UTF-8 JSON strings, never C structs, so envelope fields are
additive and `INSTAHAM_ML_ABI_VERSION` stays 1. Callers branch on the `InstahamMlStatus`
return code, never on JSON shape. Manifest `schema_version` is 1; every referenced model and
class-map file's sha256 is verified before any ORT session is created.

`envelope["view"]` is the classifier's output (`status`, `label`, `confidence`,
`probabilities`, `class_map_sha256`, `protocol_version`, `classifier.cpp:103-110`),
plus `override` / `override_route` only on a run whose route a user override changed — see the
view classifier's contract above.

`envelope["features"]` carries `status`, `family`, `order`, `gated` (the enforced subset),
`values` (keyed by feature name) and `measured_on`. `envelope["cutter"]` carries `status`,
`head_removal_applied`, the real `protocol_version`, `protocol_implemented: true`, and
`kept_fraction` / `removed_fraction` — telemetry only, computed in this app's adapter because
the vendor V144 cutter deliberately does not return it, and never a gate.

`envelope["cutter"]["status"]` values from `cut_body_mask`: `cut_applied`, `invalid_input`,
`jiduan_failed`, **`jiduan_threw`**, `no_terminal_balls`, `break1_unfit`, `shoulder_undecided`,
`cut_not_required`, `circle_cut_failed`. `jiduan_threw` is new
(`docs/fix-phase-2/1-cutter-freeze.md` F44) and distinguishes `applyJiDuan` raising from its
existing `ji.fallback` decline. Note that Dart's `cutterDeclineStatuses` set
(`run_and_persist_pipeline_use_case.dart:401`) has **not** been extended with it; that set is
unreachable while the weight override is on, so this is a latent gap rather than a live one,
and it needs closing before `weight.available` returns to `false`.

`envelope["cutter"]` also carries, on every run (`docs/fix-phase-4/5-debug-and-assertions.md`,
README §16/§17): `base_mask_w`/`h`, `final_mask_w`/`h`, `final_mask_added_px`,
`final_mask_removed_px` — the last two measuring the final (cut) mask's foreground against the
base (pre-cut) mask's, always recorded regardless of outcome. A separate declared-failure
reason, `final_mask_not_subset_of_base`, fires when `final_mask_added_px` exceeds 1% of the
base mask's area (`kMaxTolerableAddedMaskPxFraction`, `pipeline.cpp:72`) — tolerance-gated
rather than literal, because the vendor cutter's Ji/Duan gap-fill legitimately adds a small,
scattered number of foreground pixels as denoising, not a coordinate bug; see
`docs/adr/016-final-mask-subset-check-tolerance-gated.md` and
`docs/pipeline/cutter.md`'s status table.

## Previously flagged mismatch — resolved 2026-09-09

`capabilities.weight.note` used to read *"TEST OVERRIDE: real V176/V144 cutter not yet ported;
estimated_kg is not trustworthy."* The first clause was **false** — the cutter was ported by
`docs/plan.md` phases 1–4 — while the second was accurate for an unrelated reason, making it a
wrong justification for a correct warning. It was written unconditionally by
`ML/export/export_xgboost.py`, so every `--enable-for-testing` export reproduced it.

Fixed in the exporter and re-exported, so the shipped asset now states the two reasons that are
actually true: `cm_per_px_target` is an empirical fit awaiting phase 5's field re-derivation,
and the regressor cannot predict below about 73 kg, so a pig under roughly 85 kg reads high.
The `else` branch's `unavailable_reason` was stale in the same way — it said
`cutter_identity_stub`, a reason `pipeline.cpp` stopped emitting when the cutter shipped — and
now reads `weight_pending_field_validation`, matching what the native side actually reports.
Nothing in `manifest.cpp` or Dart reads either field, so this was descriptive text only, with
no behaviour change.

## Last verified against code: 2026-09-25
