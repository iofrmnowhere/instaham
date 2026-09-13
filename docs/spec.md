# Model I/O Spec

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

## Health classifier — `assets/ml/health/model.onnx`

GhostNetV3-100, opset 17, `protocol_version: health_v1`.

### Input
- Shape: `1x3x224x224`, NCHW, RGB, float32. Input name `input`.
- Preprocessing: identical to the view classifier — same resize/crop/normalization
  constants, shared code path (`resize_shorter_then_crop` in `health_input.cpp`).
- Input protocol: manifest declares `full_frame`. `segmentation_crop` and
  `segmentation_masked` are declared as *supported* but their implementations are stubs that
  degrade to `full_frame`. When the manifest asks for anything but `full_frame`, the envelope
  reports `input_protocol_requested`, `input_protocol_applied` and `input_degraded: true`, so
  a scan can never claim a crop that did not happen.

### Output
- Format: `[1, 10]` logits over `health/classes.json`: `Healthy` 0, then nine
  `Infected_*` classes (bacterial erysipelas, greasy pig disease, environmental dermatitis,
  sunburn, fungal pityriasis rosea, ringworm, parasitic mange, viral FMD, swinepox).
- Postprocessing: softmax → argmax label + confidence + probability map.
- Contract: independent of the weight branch. A failed weight branch must never suppress
  this result, and health runs on both the `dorsal_valid` and `health_only` routes.

## Segmenter — `assets/ml/segmentation/yolo.onnx`

YOLO11s-seg with LDConv + ACmix, opset 17,
`protocol_version: yolo11s_ldconv_acmix_fixed_seed42`.

### Input
- Shape: `1x3x640x640`, NCHW, RGB, float32 in `[0,1]` (plain `v/255`, **no** ImageNet
  normalization — unlike the two classifiers). Input name `images`.
- Canvas composition: with a user-confirmed `cm_per_px` and a manifest
  `segmentation.input_scale.cm_per_px` (1.10), content is placed at
  `content_scale = cm_per_px_actual / input_cm_per_px`, padded with fill 114. Otherwise, or
  when that scale would overflow the canvas, a plain whole-frame letterbox (fill 114,
  `scaleup: false`, stride 32) with `clamped_to_letterbox` recorded.
- Retry ladder: multipliers `[1.0, 1.32, 1.68, 0.77]`, then the same ladder again at
  `retry_conf_threshold` 0.10.

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
  space by `k = cm_per_px_actual / cm_per_px_target` (**target currently 0.3289473684210526
  cm/px**, the derived `100 / 304` PIGRGB floor-plane value — see the calibration note below;
  720×720 training frame). `cm_per_px` comes **only** from the user-confirmed
  reference object; there is no
  implicit `k = 1.0`. `chen16_noheight` values are raw pixel counts and lengths on that
  mask — there is no `RA`-style frame denominator and no additional linear scaling.
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
  fabricated value. The calibration itself is still unvalidated. `cm_per_px_target` now reads
  **0.3289473684210526** with `cm_per_px_target_source:
  pigrgb_floor_plane_304ppm_theoretical_geometry_INSTAHAM_CAMERA_SCALE_NORMALIZATION_md` —
  the derived `100 / 304` floor-plane value from
  `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` §1, applied 2026-09-13 by hand-editing the
  manifest (`docs/adr/011-derived-scale-target.md`).
- **The shipped constant is derived, and its accuracy is unmeasured.** The one measurement that
  ever compared the two candidates — `docs/scale-constant-sweep-results.md`, five PIGRGB images
  with known true weights through the shipped models and the real V176/V144 cutter, where 0.35
  beat 0.3289 on MAE 11.5% vs 19.0% and on every image individually — was run on 2026-09-09,
  before round 7's composed `transform_mask_to_training_space()` replaced the two-step
  resample. It therefore describes a code path the weight branch no longer runs. **No accuracy
  figure may be quoted against the shipped constant until that sweep is re-run.** The sweep's
  three criteria also disagreed with each other (minimum MAE at 0.35, minimum |bias| at 0.38,
  minimum spread at 0.30), which is what you expect when the constant is not the dominant error
  term, and 0.35's own provenance was contaminated: F21 fitted it while the cutter was an
  identity stub. Plan phase 5 still owes a re-derivation from post-cut field masks, and
  `cm_per_px_target_uncertainty` stays 1.30 because a derivation is not a field calibration.
- **A larger error term sits below the constant.** The same sweep found the regressor cannot
  emit a prediction below roughly 73 kg: both light test pigs fell under the trained minimum on
  every gated size feature, so the ensemble answers from its floor leaf and no value of
  `cm_per_px_target` moves those rows. The two in-domain pigs predicted within ±5% at 0.35, so
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

## Last verified against code: 2026-09-13
