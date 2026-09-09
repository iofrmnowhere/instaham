# Phase 2 — The replication CLI

Status: done

## Goal

Write `ML/host_scale_test/weight_branch_cli.cpp`: a binary that takes one image path and one
`cm_per_px_actual` value, runs the shipped weight-branch stages in the shipped order, and
prints a JSON envelope on stdout containing the predicted weight plus every intermediate
value phase 4 needs to interpret a disagreement.

## Interface

```
weight_branch_cli <manifest_path> <image_path> <cm_per_px_actual>
```

Writes one JSON object to stdout, diagnostics to stderr. Exit 0 when the envelope was
produced (including when a stage declined), 2 on argument or load failure.

`ML/host_scale_test/../../packages/instaham_ml_ffi/src/test/chen16_feature_gate_cli.cpp` is
the model to follow for structure — same "decode, call the stage, print machine-readable
output" shape, and it already demonstrates the include paths and the `%.17g` formatting that
keeps doubles round-trippable. Use `%.17g` for every float in the envelope for the same
reason.

## What the CLI must reproduce exactly

This is the weight branch of `packages/instaham_ml_ffi/src/pipeline.cpp`, in order. The
CLI must not include `pipeline.cpp` itself — that file also owns the view and health
branches and the FFI envelope, and pulling it in would require the classifier models and the
whole shared library. Reproducing the ordering by hand is a deliberate narrowing, and it is
the one place this harness is a reimplementation rather than a replication, so it must be
done against the source line by line rather than from memory.

1. **Load the manifest.** `instaham_ml::load_manifest(manifest_path, &manifest, &error,
   &error_code)`. Abort on failure — a manifest that does not load is not a test result.

2. **Load two ONNX sessions** via `instaham_ml::OnnxRunner::load()`: the segmentation graph
   at `manifest.segmentation.model_path` and the regressor at `manifest.weight.model_path`.
   `load_manifest` resolves both to absolute paths.

3. **Segmentation with the retry ladder.** Mirror `pipeline.cpp:317-385`. Build the attempt
   list from `manifest.segmentation.scale_ladder_multipliers` (`[1.0, 1.32, 1.68, 0.77]`),
   each at `input_cm_per_px = manifest.segmentation.input_cm_per_px * multiplier`, then the
   retry pass at `conf_threshold = manifest.segmentation.retry_conf_threshold` (0.1). For
   each attempt call

   ```cpp
   stages::run_segmentation(seg_runner, manifest.segmentation, image_path,
                            cm_per_px_actual, input_cm_per_px,
                            conf_threshold_override, &attempt_seg, &seg_error);
   ```

   then `stages::construct_pig_mask(attempt_seg)` and keep the attempt whose mask bounding
   box diagonal fraction is largest, stopping early once it reaches
   `manifest.weight.min_mask_diagonal_fraction` (0.35). Record the winning rung index, the
   `input_cm_per_px_used`, the `content_scale`, and `clamped_to_letterbox`.

   **If every rung fails to detect**, retry the whole ladder once with `cm_per_px_actual =
   0.0`, which makes `run_segmentation` fall back to the plain whole-frame letterbox — see
   `stages/canvas_scale.h`, which returns `use_scale_aware = false` for a non-positive
   `cm_per_px_actual`. Record `canvas_mode` as `"scale_aware"` or `"letterbox_fallback"` in
   the envelope. This is the plan index's open question 1; whichever mode is used must be
   the same for both constants, and phase 3 asserts that.

4. **Mask diagonal gate.** `pipeline.cpp:585`. Compute the constructed mask's bounding-box
   diagonal as a fraction of the image diagonal and compare against
   `manifest.weight.min_mask_diagonal_fraction`. Record it. Do not abort on failure —
   record `mask_diagonal_gate: false` and keep going, see "Deliberate deviations" below.

5. **The scale step — the one line this whole test exists to measure.**
   `pipeline.cpp:500`:

   ```cpp
   k = cm_per_px_actual / manifest.weight.cm_per_px_target;
   ```

   Then reproduce the height check verbatim:

   ```cpp
   capture_scale  = sqrt(double(pig_mask.width) * double(pig_mask.height));
   training_scale = sqrt(double(manifest.weight.training_frame_w) *
                         double(manifest.weight.training_frame_h));
   height_ratio   = training_scale > 0.0 ? k * capture_scale / training_scale : 0.0;
   implied_camera_height_m = manifest.weight.training_camera_height_m * height_ratio;
   ```

   Gate on `height_ratio` in `[0.25, 4.0]` — these are `kMinValidHeightRatio` and
   `kMaxValidHeightRatio` at `pipeline.cpp:48-49`. Both arms of this test pass the gate
   (0.890 and 0.947), so a rejection here means the harness is wrong, not the constant.
   Record all four values.

6. **Resample.** `stages::scale_mask_to_training_space(pig_mask, k)`. The app caps an
   unscaled fallback at `kUnscaledCutterMaxDimPx = 2880`; that path is unreachable here
   because the scale always succeeds, but reproduce the cap anyway so the CLI stays faithful
   if it is ever pointed at a phone photo.

7. **Quality gates.** `manifest.weight.quality_gates` currently declares `truncation: false`
   and `posture: false`, so both are skipped. Reproduce the conditional rather than deleting
   it, so re-enabling a gate in the manifest changes the harness too.

8. **The cutter.** `stages::cut_body_mask(mask_view)` over the resampled mask. Record
   `status`, `head_removal_applied`, and compute `kept_fraction` the way `pipeline.cpp:707`
   does — `post_cut_area / mask_for_cutter->area_px`, where `post_cut_area` counts pixels
   equal to `1` in `cutter_result.mask`. `kept_fraction` is the value phase 2.1 of
   `docs/fix-2.md` found stepping discontinuously; it is the single most important
   diagnostic in this envelope after the prediction itself.

9. **Features.** `manifest.weight.feature_family` is `chen16_noheight`, so call
   `stages::extract_chen16_features(cutter_result.mask, cutter_result.width,
   cutter_result.height)`. Note that Chen16 takes **no** frame-normalization arguments —
   `mask_area` is a raw pixel count, and the training frame enters only through the
   resample in step 6.

10. **Name the features.** Reproduce `pipeline.cpp`'s `chen16_values`, which maps
    **positionally**: `out[feature_order[i]] = features.values[i]`. It does not look names up
    in the vendor's own ordering. Preserve that, including the bug-compatible behaviour if
    `feature_order` and the vendor array ever disagree, and additionally assert that
    `manifest.weight.feature_order` has exactly 16 entries and matches the canonical list
    (`mask_area, convex_hull_area, difference, dif_mask, body_curve, perimeter,
    outline_curve, longest, shortest, Hu_1..Hu_7`). If it does not, stop — AGENTS.md rule 2
    forbids proceeding on an assumed feature order.

11. **Domain gate.** Reproduce `run_feature_domain_gate`: for each name in `feature_order`
    whose `feature_domain` entry has `gate: true`, widen its bounds by
    `pow(manifest.weight.cm_per_px_target_uncertainty, uncertainty_exponent(dimension))` and
    check membership. Record pass/fail per feature. Do not abort — see below.

12. **Predict.** `ordered_feature_vector(feature_order, values)` then
    `stages::predict_weight(weight_runner, feature_vector)`.

## Deliberate deviations from the app, and why

The app refuses to predict after a failed gate — AGENTS.md rule 8, and correctly so, because
a user must never see a number the pipeline does not stand behind. This harness is a
diagnostic instrument and needs the number even when a gate would have withheld it, because
"0.3289 predicts 140 kg but the domain gate rejects it" and "0.3289 declines" are different
findings and phase 4 has to tell them apart.

So the CLI **always computes and prints the prediction**, and prints every gate's verdict
alongside it. The envelope must therefore carry an explicit
`"gates_would_have_withheld": true|false` field, and phase 4 must report gate status next to
every weight it quotes. This deviation is confined to `ML/host_scale_test/` and must not be
carried into `lib/` or `packages/instaham_ml_ffi/src/`.

## Envelope fields

At minimum: `image`, `true_kg` (parsed from the filename by the driver, not the CLI),
`cm_per_px_actual`, `cm_per_px_target`, `k`, `canvas_mode`, `ladder_rung`,
`input_cm_per_px_used`, `content_scale`, `clamped_to_letterbox`, `seg_conf`,
`candidates_kept`, `mask_w`, `mask_h`, `mask_area_px`, `mask_diagonal_fraction`,
`height_ratio`, `implied_camera_height_m`, `scaled_w`, `scaled_h`, `scaled_area_px`,
`cutter_status`, `head_removal_applied`, `pre_cut_area`, `post_cut_area`, `kept_fraction`,
all 16 named feature values, `domain_violations` (array of names), `gates_would_have_withheld`,
`predicted_kg`.

## Steps

- [x] Write `weight_branch_cli.cpp` following the twelve steps above, reading
      `pipeline.cpp` alongside rather than working from this summary alone.
- [x] Add it to `ML/host_scale_test/CMakeLists.txt` as the real target, alongside phase 1's
      trivial `main()`.
- [x] Build.
- [x] Run against `Instaham/PIGRGB-Weight/sub_1.78/100.9kg_3.png` with
      `cm_per_px_actual = 0.3114504` and the manifest as committed.
- [x] Confirm the first-run sanity values from `docs/test-plan.md`: at the manifest's current
      `cm_per_px_target = 0.3289`, `k` should print `0.946946`, `height_ratio` the same, and
      `scaled_w`/`scaled_h` should be `909 x 511`. If `height_ratio` differs from `k`, the
      `capture_scale` term is wrong — for a 960x540 mask it is exactly 720, which cancels
      against the 720x720 training frame.
- [x] Confirm `cutter_status` is `cut_applied` on at least one image. If it declines on all
      five, stop and report that instead of proceeding to phase 3 — a universally declining
      cutter makes the constant comparison meaningless and is itself the finding.

## Verification

- [x] The CLI produces a complete envelope for all five images at the committed manifest.
- [x] `kept_fraction` is in `(0, 1]` and `post_cut_area <= pre_cut_area` on every image.
- [x] The 16 printed feature names match `manifest.weight.feature_order` exactly, in order.
- [x] Re-running the same image twice produces a byte-identical envelope. If it does not,
      something in the chain is nondeterministic and phase 3's comparison is unsound.

## Open questions

- ~~Whether the segmentation ladder reaches `min_mask_diagonal_fraction = 0.35` under
  scale-aware composition on 960x540 input.~~ **Resolved: yes, on all five images, on rung
  0 of the ladder.** The letterbox fallback added in step 3 was never exercised. See
  "Actual results" below.

## Actual results (this run)

All five images at the committed manifest (`cm_per_px_target = 0.3289`,
`cm_per_px_actual = 0.3114504`):

| image | true kg | predicted kg | cutter | kept_fraction | mask_diag_frac | seg_conf | canvas_mode |
|---|---|---|---|---|---|---|---|
| 60.27kg_35.png | 60.27 | 76.01 | cut_applied | 0.9097 | 0.361 | 0.920 | scale_aware |
| 66.24kg_11.png | 66.24 | 81.73 | cut_applied | 0.9237 | 0.411 | 0.927 | scale_aware |
| 100.9kg_3.png | 100.90 | 106.19 | cut_applied | 0.9014 | 0.476 | 0.926 | scale_aware |
| 125.38kg_4.png | 125.38 | 154.21 | cut_applied | 0.9328 | 0.603 | 0.931 | scale_aware |
| 133.42kg_5.png | 133.42 | 156.43 | cut_applied | 0.8029 | 0.625 | 0.926 | scale_aware |

`gates_would_have_withheld` is `false` on every image — the app would have shown a number
on all five at this constant. These are raw phase 2 sanity numbers, not phase 4's analysis;
phase 4 computes the two-arm comparison against 0.35 and interprets them.

`100.9kg_3.png`'s envelope matched the plan's precomputed sanity values exactly:
`k = 0.9469455761629675`, `height_ratio` identical, `scaled_w x scaled_h = 909 x 511`.
Re-running the same invocation twice produced a byte-identical envelope.

One deviation from the plan, recorded rather than silently absorbed: step 7's quality-gate
reproduction was written as a hard `return 2` if the manifest ever turns
`quality_gate_truncation` or `quality_gate_posture` on, rather than a full port of
`stages/quality_gates.h`. The committed manifest ships both false, so this path never ran
here. If a future manifest enables either gate, `weight_branch_cli.cpp` must be extended
before its results can be trusted — it will refuse to run silently-wrong rather than skip
the gate quietly.
