> **SUPERSEDED — read `docs/handoff-2.md` first.** This file is round 8's record, kept for
> history. Round 9 answered the decision this file was waiting on (`cm_per_px_target` reverts
> to 0.35) and corrected three statements below: a host build of the stage sources now exists,
> the cutter is the real V176/V144 chain rather than an identity stub, and `ML/pipeline/cutter.py`
> is not a valid oracle for it.

# Session handoff — round 8 ran phase 2's 0.3289 half; the specification's constant lost

**Active work: `docs/fix-2.md`, phase 2 — measured, awaiting one decision.** Both constants are
now swept on all three photos. Read `docs/fix-phase-2/2-scale-target-conflict.md` ("What the
0.3289 sweep shows") before doing anything else.

Three documents remain live: `docs/fix-2.md` + `docs/fix-phase-2/` (round 6; phases 1 and 1.1
closed, 2 measured, 2.1's fix still open, 3 not started); `docs/fix.md` + `docs/fix-phase/`
(round 5, open at phase 7, untouched for a third session); `docs/plan.md` phase 5 (unstarted).

**F-numbering continues at F54.** No new F opened — this session completed F46's owed half.

## What happened

`cm_per_px_target` was changed 0.35 → **0.3289**, re-exported, and the user re-ran the same
18-scan device sweep (same three photos, same six-mark bands, same per-mark logcat cycle). Raw
data is round 3 in `docs/logs/recorded.md`; the comparison is in phase 2's file.

**0.3289 is the worse constant.** It raised every prediction as F46 predicted, and every
0.35-vs-0.3289 separation exceeds its photo's jitter band — so this is a resolved measurement,
not noise — but it turns three undershoots into three overshoots and is further from true weight
on two of the three photos (118 kg goes from −9.6% to +15.8%, the worst error in either sweep).
Neither constant is right; this strengthens rather than settles `prediction-2.md`'s thesis that
the constant must not be fitted at all.

The 96 kg photo hit the same cutter `kept_fraction` discontinuity 2.1 found at 0.35 (0.8061 here
against 0.8063 there, on a different mark). It survives the constant change untouched, which is
consistent with F53's finding that the cutter, not the scale, is the dominant amplifier.

## Decisions made

- **No ADR.** No decision has been taken — the revert is explicitly deferred (see Open
  questions). ADR-005's replacement is still owed from round 5 and should now fold in F46's
  result alongside 2.1's; that is `pipeline-docs`' call when a fix is chosen.
- **`spec.md` records 0.3289 as current state, not as a settled contract**, with the expected
  revert stated. Same treatment in `pipeline/prediction.md`. This is deliberate: the manifest
  really does ship 0.3289 right now and a reader must not think otherwise.
- **The parse script was not committed** — scratch work, as last round. Its output is in
  `docs/logs/recorded.md`.

## Export procedure — corrections to the last handoff, this cost the session time

1. **The constant lives in `ML/export/export_xgboost.py` (~line 289), not
   `build_manifest.py`.** Last handoff said to change it "through `build_manifest.py`";
   `build_manifest.py` only assembles fragments and runs F51's key-loss guard.
2. **`--enable-for-testing` must be passed on every weight re-export.** Without it the fragment
   silently writes `weight.available: false` + `unavailable_reason`, disabling the branch. The
   flag is what produces the `available: true` + `note` pair the shipped manifest carries.
3. **`build/ml_export/segmentation/manifest_fragment.json` was stale** — missing the
   `input_scale` block (F50/F51). F51's guard caught it. Fixed at the fragment, which is the
   real source; do not work around it with `--allow-key-removal`.
4. **`--allow-key-removal` *is* required against the committed manifest.** HEAD is baseline5-era,
   so a rebuild legitimately drops 28 `RA/LC/BL/BW/E` and `view.model.fusion_max_abs_diff` keys.
   That specific list is the expected baseline5→chen16 migration; any *other* missing key is not.
5. **`build_manifest.py` stages asset files before the guard runs**, so a rejected build has
   still copied ONNX/JSON into `assets/ml/`. Check `git status` after a failed build.
6. `assets/ml/manifest.json` was reverted to HEAD mid-session and **reconstructed** from the
   fragments. It was verified field-by-field against `build/unit_test_assets/assets/ml/
   manifest.json` and differs only in the intended fields plus the re-export's
   non-deterministic `xgboost.onnx` sha256. Working command is in this session's transcript;
   the four `--view/--health/--weight/--segmentation` dirs under `build/ml_export/` are current.

## Open questions

- **Revert `cm_per_px_target` to 0.35?** The user deferred this deliberately at end of session —
  it is the first thing to ask. The measurement argues for reverting (0.35 is closer on two of
  three photos); the counter-argument is that both values are wrong and the next change may
  overwrite this constant anyway, in which case a revert is churn. Nothing else is blocked on
  it, but **every scan the app produces until it is answered runs at 0.3289**, so any new
  device data collected in the meantime is on the losing constant unless that is intended.
- The live-camera path is **still entirely unmeasured** — all 21 device scans across both rounds
  are the gallery-import path at 2250 × 3000. Unchanged from last session.
- Whether F38 is now retracted. Its post-cut `RA` table implied targets near 0.35 (0.347, 0.361)
  and F53's low readings were called "the first evidence against it"; F46 now cuts the other way
  and supports F38. Phase 2's file states this but does not resolve it.

## Next steps

1. **Ask about the revert** (above). If yes: change `export_xgboost.py`, re-export with
   `--enable-for-testing`, rebuild the manifest, restore the `_source` tag to
   `three_sample_field_estimate_pending_phase5_post_cut_rederivation`, then re-run `spec-drift`
   and update `prediction.md` / `prediction-2.md` / `spec.md`'s "currently 0.3289" wording.
2. **Then phase 2.1's fix**, which the measurement now points at more sharply than before: the
   cutter's discontinuity and the boundary features' instability are the dominant terms, and
   neither is addressed by any constant. The area-weighted resample replacing `INTER_NEAREST`
   remains the leading single change; phase 3 (F49) subsumes it at higher cost.
3. **Remove the temporary `INSTAHAM_ENVELOPE` dump** once no further sweeps are planned. Marked
   TEMPORARY at the call site and `_dumpEnvelopeToLog` in
   `lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`.
4. **Then `docs/fix-phase-2/3-normalization-order.md`** (F49).
5. Only after round 6 testing, reconcile `docs/fix.md`.

`docs/changelog.md` still has no round 6 entry — `planner`'s write-step when the round closes.

## Changed this session

- `ML/export/export_xgboost.py` — `cm_per_px_target` 0.35 → 0.3289 and its `_source` tag.
- `assets/ml/manifest.json`, `assets/ml/weight/{feature_order,xgboost.meta}.json` — re-exported.
  `assets/ml/weight/xgboost.onnx` also regenerated (gitignored).
- `build/ml_export/segmentation/manifest_fragment.json` — restored the `input_scale` block.
- `docs/logs/recorded.md` — round 3 added (18 scans at 0.3289, medians and bands).
- `docs/fix-phase-2/2-scale-target-conflict.md` — status, the comparison, two F46 steps closed.
- `docs/spec.md` (`spec-drift`) — the constant's current value and its experimental status.
- `docs/pipeline/prediction-2.md` (F46 section; split at the 150-line rule),
  `docs/pipeline/prediction-4.md` (**new** — the calibration guidance moved out of -2),
  `docs/pipeline/prediction.md`, `docs/pipeline/cutter-2.md` (its `weight.available: false`
  claim contradicted the shipped manifest), `docs/pipeline/README.md` (`pipeline-docs`).

Carried forward untouched: `capabilities.weight.note`'s false first clause
(`ML/export/export_xgboost.py:237` writes it unconditionally — reproduced again by this
session's re-export); Dart's `cutterDeclineStatuses` lacks `jiduan_threw`;
`mask_shape_out_of_domain` unreachable; F45's ~5 s main-isolate analysis (user-accepted);
`instaham_ml_predict_weight_json` still reports `identity_stub`; the `Hu_3`–`Hu_7` instability
with no fix candidate targeting it; `ML/tools/replicate_native_weight_branch.py` stale.

## Validation state

**Nothing was compiled, analyzed or tested this session** — no Dart or C++ changed. The Python
exporter and the manifest changed, and both were verified by re-export and by structural diff,
not by a test run. Last known-good remains 93 passed / 21 pre-existing skips. The user's
sideloaded release APK is built at **0.3289**, not 0.35.

## Build / environment state

Unchanged and still accurate: Flutter 3.44.8, Dart 3.12.2; export venv at `C:\ml_export_venv`
(has `xgboost` 3.4.1 + `onnxruntime` 1.29.0, no `ultralytics`/`torch`, so segmentation cannot be
re-exported); exporters run as modules from the repo root; host C++ tests need `vcvars64.bat` and
the `cmake`/`ninja` under `C:\Android_Studio_Loc`; no host target compiles `pipeline.cpp`; a
`flutter pub get` landing inside a build window breaks the release build (F52). The repo's own
Python (3.13.1) has `onnxruntime`, `opencv`, `pillow-heif`, `scipy`, `skimage` but **not**
`xgboost`. Logcat dumps come back UTF-16LE with CRLF — parse with `encoding="utf-16"`.

Nothing is committed — every change above is in the working tree.
