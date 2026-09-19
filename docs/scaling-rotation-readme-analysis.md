# Analysis — `INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md`

Date: 2026-09-18. Branch: `initial_health`. Head commit at time of analysis: `06d2ecd`.

This document reviews the handoff README at the repository root
(`INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md`) against the shipped
implementation. It is an analysis only: no code, manifest, or pipeline behaviour was changed
while producing it.

## Summary

The README is partly redundant with what is already shipped, partly a proposed answer to an
architectural question the project has recorded but never decided, and contains one invariant
that provably fails on capture data already present in this repository.

## 1. Requirements the implementation already satisfies

| README section | Requirement | Where it is already met |
|---|---|---|
| §1 | `cm_per_px_target = 0.34` | `assets/ml/manifest.json` → `capabilities.weight.capture_contract.cm_per_px_target = 0.34`, `cm_per_px_target_source = host_scale_sweep_round28_f59_measured_mae_minimum_scale_constant_sweep_results_2_md`. Landed in commit `06d2ecd`. |
| §12 | XGBoost features must come from the final mask at 0.34 cm/px, never from canvas or tensor coordinates | `pipeline.cpp:675` builds the cutter/feature mask with `stages::transform_mask_to_training_space(seg_output, k)`, where `k = cm_per_px_actual / cm_per_px_target` (`pipeline.cpp:500`). The cutter and the 16-feature extractor both run on that mask. |
| §10 | Quality gates run before Ji-Duan, on the whole mask | `pipeline.cpp:600-660` runs the truncation and posture gates on the whole mask in original capture coordinates, before the training-space transform and before the cutter. |
| §7, §5 | `imgsz = 640`, `conf = 0.25`, neutral pad `114` | `assets/ml/manifest.json` → `capabilities.segmentation.model.input.size = [640, 640]`, `postprocess.conf = 0.25`, `model.letterbox.color = [114, 114, 114]`. |

One qualification on §10: both gates currently ship disabled
(`capabilities.weight.quality_gates.posture = false`, `.truncation = false`), so the ordering
requirement is satisfied in code but inert at runtime.

## 2. The core divergence

README §15 forbids the pattern "run YOLO first, resize the mask afterward". The shipped
pipeline does a variant of exactly that:

- `stages/segmentation.cpp` composes the decoded image into the 640x640 model canvas at
  `content_scale = cm_per_px_actual / input_cm_per_px`, using
  `capabilities.segmentation.input_scale.cm_per_px = 1.1` and the retry ladder
  `[1.0, 1.32, 1.68, 0.77]` (`stages/canvas_scale.h`, `pipeline.cpp:329-360`).
- The selected mask is then transformed into 0.34 cm/px training space by a single composed
  transform (fix-3 round 7, F55), replacing the earlier double rasterization.

So the app does normalize the segmenter's input by physical scale — but to 1.1 cm/px, not to
0.34, and it reaches 0.34 by transforming the mask rather than the photograph.

This exact conflict is already recorded in
[`docs/fix-phase-2/3-normalization-order.md`](fix-phase-2/3-normalization-order.md) as F48/F49.
That document states three defensible outcomes (adopt the specification and reorder; keep the
current order and document why; or supersede the specification) and was marked superseded and
never started. The README is one of those three answers, argued by assertion rather than
measurement. It should be treated as a decision proposal requiring an ADR, not as a defect
report.

## 3. Claims in the README that do not hold

### 3.1 The 960x540 fit invariant fails on existing field data

README §6 and §17 require `rotatedWidth <= 960` and `rotatedHeight <= 540` after normalization,
and instruct the implementer to stop and investigate rather than provide a fallback.

The on-device log at [`docs/logs/adb_log.md`](logs/adb_log.md) records
`content_scale = 0.05857691168785095` at `input_cm_per_px_used = 1.1`, which implies
`cm_per_px_actual ≈ 0.0644` for that capture. Normalizing a 4032x3024 photograph to 0.34 cm/px
gives a resize factor of `0.0644 / 0.34 ≈ 0.1895`, and therefore:

```text
4032 * 0.1895 ≈ 764
3024 * 0.1895 ≈ 573
```

573 exceeds the 540 limit, and the image is landscape, so the portrait rotation rule does not
change the outcome. A capture of this shape violates the invariant on the first try. The README
offers no behaviour for that case other than halting.

### 3.2 The stated rationale for the canvas is not the actual mechanism

README §3 argues that feeding a roughly 400x533 normalized image to YOLO at `imgsz = 640`
enlarges the long side by about 1.20x, and that the 960x540 canvas avoids this. But YOLO
scales a 960-wide canvas down to 640, a factor of about 0.667. The pig therefore ends up roughly
1.8x *smaller* in network space than on the direct path — an effective presentation scale of
about `0.34 / 0.667 ≈ 0.51` cm/px. The canvas does not preserve the pig's apparent size; it
shrinks it. The change may still be beneficial, but the README's explanation of why does not
match its own arithmetic.

### 3.3 The implied presentation scale is outside the current ladder

The app presents the pig at 1.1 cm/px, with ladder multipliers spanning 0.77 to 1.68, i.e. an
effective range of 0.847 to 1.848 cm/px. The README's canvas implies about 0.51 cm/px, roughly
2.2x larger than the app's default rung and unreachable at any rung. Adopting the README
replaces the round-4 F18/F19 scale tuning, which
[`docs/fix-phase-2/3-normalization-order.md`](fix-phase-2/3-normalization-order.md) identifies
as the tuning that makes on-device detection work at all. Any adoption plan must re-verify
detection on the field photographs before any weight number from the new order is trusted.

### 3.4 `training_frame_px` disagrees with 960x540

The weight capture contract declares `training_frame_px = [720, 720]`
(`assets/ml/manifest.json`), consumed by the mask-diagonal plausibility check at
`pipeline.cpp:508` together with `min_mask_diagonal_fraction = 0.35`. The README introduces
960x540 as the training-like frame without reconciling it with the 720x720 constant. Adopting
the README leaves two disagreeing "training frame" values in the system.

### 3.5 The 304 px/m rejection needs an explicit supersede

README §1 and §15 instruct the reader not to switch to 304 px/m.
[`docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`](INSTAHAM_CAMERA_SCALE_NORMALIZATION.md) is the
standing authority for the 304 px/m (0.3289 cm/px) PIGRGB floor-plane baseline. The measured
sweep in [`docs/scale-constant-sweep-results-2.md`](scale-constant-sweep-results-2.md) does
support the 0.34 band, so the value the README asks for is defensible; what is missing is an
explicit record that the 304 px/m baseline document is superseded on this point, rather than a
single unsourced sentence in a root-level README.

## 4. What the README is right about but does not say

960x540 is not an arbitrary canvas size. The released PIGRGB frames are 960x540
(`docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md:29`) at 0.3289 cm/px, and the sweep corpus
`Instaham/PIGRGB-Weight/sub_1.88/` consists of 960x540 PNGs. Placing a 0.34 cm/px image on a
960x540 canvas therefore reproduces PIGRGB frame geometry almost exactly. That is a stronger
and more testable argument than "training-style framing", and it is the version of the claim
worth measuring.

## 5. Remaining gaps and risks

- **Rotation is an unverified capture assumption.** The native layer performs no rotation by
  design; EXIF orientation is normalized once on the Dart side
  (`packages/instaham_ml_ffi/src/include/instaham_ml.h:98-101`,
  `packages/instaham_ml_ffi/src/util/image_io.h:17-18`). The README's rule "portrait capture
  implies the pig's head is at the top" is enforced nowhere, and §4 explicitly forbids
  inferring head direction. Physical scale itself is rotation-invariant because it is a scalar,
  so the only exposure is YOLO seeing the pig head-right versus head-left. That risk is probably
  small, but it is uncharacterized.
- **The retry ladder disappears.** README §13 describes a single segmentation pass. The ladder
  and the `clamped_to_letterbox` fallback exist because detection failed without them; the
  README does not address what replaces them.
- **Expectation management.** The README asserts the problem is not the XGBoost model. The
  `k = 1.0` arm of the sweep — where the resample step is a verified no-op — still shows MAE
  5.42% with one image at +14.29% and a one-sided bias
  ([`docs/scale-constant-sweep-results-2.md`](scale-constant-sweep-results-2.md)). No change to
  segmentation framing can push error below that floor. The regressor also cannot predict below
  roughly 73-74 kg, so results computed from lighter samples remain out of domain regardless.

## 6. Recommended next steps

1. Decide F49 and record it as an ADR: adopt the README's order, keep the current order with a
   stated reason, or supersede the README. This is the blocking decision; everything else
   depends on it.
2. Before adopting, measure the canvas path host-side in `ML/host_scale_test/` against
   `.pig_pictures/` and `PIGRGB-Weight/sub_1.88/`. This needs no device and no APK build.
3. Resolve the invariant failure in section 3.1 — either define a fallback for captures that
   exceed 960x540 after normalization, or restate the invariant in terms the field data
   satisfies.
4. Reconcile `training_frame_px = [720, 720]` with the proposed 960x540 frame.
5. If the order is changed, re-verify segmentation detection on all field photographs before
   trusting any weight number produced by the new order.

## 7. Validation

No code was changed, so no build, analyzer, formatter, or test run applies to this document.
Every claim above is sourced from files in this repository at commit `06d2ecd`; the file and
line references are the evidence.
