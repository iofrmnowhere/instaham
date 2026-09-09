# Phase 3 — Driver and the two-arm sweep

Status: done

## Goal

Run the phase 2 CLI over five images × two constants = ten invocations, with the two arms
differing in exactly one manifest field, and collect the results into one CSV plus ten
envelope JSON files under `ML/host_scale_test/out/`.

## How the constant is varied — do not re-export

Rounds 2 and 3 changed `cm_per_px_target` by editing
`ML/export/export_xgboost.py` and re-running the whole export. Do **not** do that here. That
route regenerates `assets/ml/weight/xgboost.onnx` with a fresh non-deterministic sha256,
rewrites the `_source` tag, and requires `--enable-for-testing` and `--allow-key-removal`
flags whose omission silently disables the weight branch — every one of which is a way for
the two arms to differ by more than the constant under test.

Instead, the driver writes two patched **copies of the manifest** and passes each to the CLI:

```
assets/ml/manifest.test_0350.json
assets/ml/manifest.test_03289.json
```

Each is `assets/ml/manifest.json` parsed, with
`capabilities.weight.capture_contract.cm_per_px_target` set to the arm's value, and nothing
else touched. They must live in `assets/ml/` rather than in the test folder because
`load_manifest` resolves `regressor.path` and `segmentation.model.path` relative to the
manifest's own directory; a copy placed elsewhere would fail to find the models.

Delete both after the run, and add `assets/ml/manifest.test_*.json` to `.gitignore` before
the first run so a stray copy cannot be committed. `assets/ml/manifest.json` itself must be
**bit-identical before and after this phase** — verify with `git status` and `git diff`.

Note that the manifest as committed currently carries `0.3289`, so the `0.3289` arm should
produce results identical to running the unpatched manifest. Assert that once, as a check
that the patching path introduces nothing.

## Precheck

Before the sweep, confirm the on-disk models match what the manifest declares. `load_manifest`
verifies `regressor.sha256` and `segmentation.model.sha256`, so a mismatch will surface as a
load failure rather than a wrong number — but check it explicitly so the failure is
diagnosed in one step rather than three:

- [x] sha256 of `assets/ml/weight/xgboost.onnx` equals
      `4210e54c6b6b8cc3a35c354557a79ec0c6c3c802966a6aca10ac798ceb3a1618`.
- [x] sha256 of `assets/ml/segmentation/yolo.onnx` equals
      `a6467c75de32cddbfeedcb941659f0aa31d71d9d7b75ddf33ae01723fc0e508a`.

If either differs, stop. The working tree's models are not the ones the manifest describes,
and any result would be untraceable. `xgboost.onnx` is gitignored, so it can legitimately be
a stale local artifact from a previous session's export.

## The driver

`ML/host_scale_test/run_sweep.py`, plain stdlib plus nothing — it must run under the
repository's own Python 3.13.1 without the export venv, since it needs neither `xgboost` nor
`onnxruntime` (the CLI owns all inference).

Responsibilities:

1. Parse the true weight from each filename: the leading number before `kg`. `60.27kg_35.png`
   is 60.27 kg, not 35.
2. Compute `cm_per_px_actual` once, from the geometry, and pass the identical value to every
   invocation:
   ```
   PIGRGB_TARGET_PPM_AT_188 = 304.0
   CAPTURE_HEIGHT_M         = 1.78
   BASELINE_HEIGHT_M        = 1.88
   ppm  = PIGRGB_TARGET_PPM_AT_188 * BASELINE_HEIGHT_M / CAPTURE_HEIGHT_M   # 321.0787
   cm_per_px_actual = 100.0 / ppm                                           # 0.3114504
   ```
   Write these four lines as constants at the top of the file with the derivation in a
   comment. `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` is the authority for the 304
   figure — not `assets/ml/manifest.json`, which carries a fitted value.
3. Write the two patched manifests.
4. Invoke the CLI ten times, capturing stdout to
   `out/envelope_<image>_<target>.json` and appending a row to `out/results.csv`.
5. Assert cross-arm invariance on the fields that must not move: `canvas_mode`,
   `ladder_rung`, `seg_conf`, `candidates_kept`, `mask_w`, `mask_h`, `mask_area_px`. All of
   these are computed before `cm_per_px_target` is read, so any difference between arms means
   the harness is leaking the constant upstream of the resample and the run is void. Fail
   loudly.
6. Delete the patched manifests.

## Steps

- [x] Add `assets/ml/manifest.test_*.json` to `.gitignore`.
- [x] Run the precheck above.
- [x] Write `run_sweep.py`.
- [x] Run it. Ten envelopes, one CSV.
- [x] Confirm the cross-arm invariance assertions all passed.
- [x] Confirm `git status` shows `assets/ml/manifest.json` unmodified (by this phase --
      it carries an unrelated pre-existing modification from before this session, verified
      by mtime and matching the handoff's recorded round-3 export).
- [x] Append the raw rows to `docs/logs/recorded.md` as **round 4**, matching the format
      rounds 1–3 use there. Note in the round header that this is a host run on PIGRGB
      images, not a device sweep on field photos — the two are not directly comparable and a
      future reader must not average them together.

## CSV columns

`image, true_kg, cm_per_px_actual, cm_per_px_target, k, canvas_mode, ladder_rung, seg_conf,
mask_w, mask_h, mask_area_px, mask_diagonal_fraction, height_ratio, implied_camera_height_m,
scaled_w, scaled_h, cutter_status, kept_fraction, mask_area, convex_hull_area, difference,
dif_mask, body_curve, perimeter, outline_curve, longest, shortest, Hu_1, Hu_2, Hu_3, Hu_4,
Hu_5, Hu_6, Hu_7, domain_violations, gates_would_have_withheld, predicted_kg, error_pct`

`error_pct = (predicted_kg - true_kg) / true_kg * 100`, signed, so overshoot and undershoot
stay distinguishable — rounds 2 and 3 turned on exactly that sign.

## Verification

- [x] Ten rows in `results.csv`, none with an empty `predicted_kg` unless the matching
      `cutter_status` explains it.
- [x] The five `0.3289` rows match a run against the unpatched committed manifest exactly.
- [x] Every invariance assertion in step 5 passed.
- [x] A second full run reproduces `results.csv` byte for byte.

## Open questions

- ~~If the cutter declines on some images but not others...~~ **Resolved: it didn't.**
  `cutter_status: cut_applied` on all ten runs (5 images x 2 constants). The constant
  changed the predicted kilograms, never whether a cutter or gate would have fired.

## Actual results

10/10 runs succeeded, both cross-arm invariance checks passed, the 0.3289 arm matched the
unpatched committed manifest exactly on all five images, and a full second run reproduced
`results.csv` byte for byte. Full numbers are in `docs/logs/recorded.md`'s round 4 and
`ML/host_scale_test/out/results.csv`; summary: **0.35 was closer to true weight than 0.3289
on all five images** (four by a wide margin, one a near-tie), mean absolute error 11.5% vs
19.0%. Phase 4 does the full analysis and decides what this means for the manifest.
