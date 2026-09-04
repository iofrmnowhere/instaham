# Phase 3 — Open verification and tweaking

Status: in progress

Everything still outstanding. New items in this phase number from **F25** upward; F1–F24 are
taken, and source comments cite them.

## Steps

- [ ] **Run the harness first.** `python ML/tools/replicate_native_weight_branch.py . T`
      against the three `.pig_pictures/` photos, on the current manifest values. Seconds, not
      an APK cycle. Do this before touching any C++ — it is the loop that produced every
      number in phase 1.
- [ ] `ctest` over `test_segmentation_canvas.cpp`, `test_mask_selection.cpp` and
      `test_feature_domain.cpp` — F18's composition and clamp, F19's ladder advance/stop,
      F21's manifest values parsing, F22's unwidened comparison.
- [ ] `dart format` on changed Dart files, then `flutter analyze`.
- [ ] `flutter test test/features/inference_pipeline/` — F20's persisted blocks and F22's
      `extrapolated` rendering.
- [ ] Rebuild native, sideload, re-run all three `.pig_pictures/` scans on the phone.
- [ ] Read the persisted `segmentation` and `construction` events from that run and settle
      F24, F25 and F26 below from the log rather than by inspection.
- [ ] Regenerate `assets/ml/manifest.json` via `python ML/export/export_xgboost.py` and
      re-diff. The round-4 manifest edits were made by hand; the toolchain question is now
      only `xgboost` + `onnxmltools`, so there is no reason to keep hand-editing it.

No Drift schema change is involved in any of this: no `schemaVersion` bump, no migration, no
`build_runner`.

## Acceptance

Carried forward from `ref_fix.md` §4, unchanged:

- All three photos produce a weight.
- Mask bbox diagonal ≥ 0.55 of the frame diagonal on all three (harness measured 0.62 /
  0.71 / 0.72).
- Predictions within ±20% of true on all three, and within ±10% on at least two (harness
  measured at target 0.35: −2.1%, −8.7%, +14.9%).
- `candidates_kept`, `ladder_rung` and `content_scale` present in the persisted
  `segmentation` event for every scan.

**Non-acceptance.** Do not accept a build where the two previously-failing photos predict but
the 96 kg photo regresses. That photo is the only one with a known-good history and it is the
control.

## F24 — the `RA` discrepancy (open, carried from round 4)

The harness reports `RA` = 0.00728 on the 118 kg photo against the app's 0.00086 — a factor
of 8.5 on a mask whose `BL`, `BW`, `LC` and `E` all agree within 5%. A 5% difference in
outline cannot produce that.

Two candidate explanations, and no guessing between them: either it is nothing (the masks are
not bit-identical, and `RA` is the only feature depending on filled area rather than outline
geometry), or it is a real defect in how the native side counts area or chooses the `RA`
denominator. `RA`'s denominator is the one input that changes with `scale_ok` — the
manifest's 720×720 training frame when a scale was applied, the mask's own dimensions
otherwise — which is the first thing to check in the persisted `features` event.

F20 has made this a log read. Do it on the first device run after round 4.

## F25 — orientation sensitivity

`ref_fix.md` §1.5: the 96 kg photo is the only one the pre-round-4 pipeline could ever
segment, and only rotated 90° clockwise, where the model returns a 523×206 box at conf 0.30
against a 72×55 snout upright. That is consistent with it being the one scan that ever
produced a number, and with the app having handled its HEIC `irot` differently from the other
two — but it is *not* a settled reconstruction: replaying the rotated path end to end predicts
172.6 kg where the app reported 139.3 kg.

Treat it as the best available explanation of the anomaly, not as fact. F20's telemetry
should now show whether orientation sensitivity is still biting after F18. If it is, the fix
is the same as the segmenter retraining in phase 2's out-of-scope list, not another
workaround here.

## F26 — is the ladder papering over brittleness?

`input_cm_per_px = 1.10` and the ladder were both fitted to three photos of one animal type,
by one photographer, on one phone. The 118 kg row in phase 1's sweep already shows the
segmenter detecting at 1.30, 1.60, 1.80 and 2.40 but not at 0.90–1.20, 1.40 or 2.00 — which
is model brittleness the ladder papers over rather than removes.

Watch `ladder_rung` across real scans as they accumulate. A distribution concentrated on rung
0 means the constant is right; a spread across rungs, or frequent falls through to the
`retry_conf_threshold` pass, is evidence for re-exporting the segmenter rather than widening
the ladder further.

## Standing follow-up, not blocking this phase

`cm_per_px_target` must be retuned **downward** the moment the real cutter lands. F21
knowingly conflates the scale error with the missing cutter's inflation because three samples
cannot separate them, so a cutter landing against a target fitted to uncut masks would
silently make accuracy worse, not better. This belongs in the manifest's own notes as well as
here.
