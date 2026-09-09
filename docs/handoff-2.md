# Session handoff — round 9: the constant question is answered, and it turned out not to be the problem

**Supersedes `docs/handoff.md` (round 8).** That file is round 6's record and is retained
deliberately; read this one for current state.

**The revert decision the last two sessions deferred is now MADE: `cm_per_px_target` goes back
to 0.35.** The user decided this at the end of this session. It is **not yet applied** — the
manifest still ships 0.3289 and the sideloaded APK still runs 0.3289. Applying it is step 1 of
Next steps.

**F-numbering continues at F55.** No new F was opened this session — the work ran under
`docs/test-plan.md`, a new document, not under `fix.md`/`fix-2.md`.

## What happened

The 0.35-vs-0.3289 question was moved off the phone and onto this machine. A host harness was
built that compiles and runs **the app's own C++ stages** — segmentation, construction, the
k-resample, the vendor V176/V144 cutter, Chen16 features, XGBoost-via-ONNX — against the
shipped `assets/ml/` models, then swept the constant over five PIGRGB images with known true
weights. Full result: `docs/scale-constant-sweep-results.md`. Raw rows: round 4 of
`docs/logs/recorded.md`.

**0.35 beat 0.3289 on all five images** (MAE 11.5% vs 19.0%). That agrees with rounds 2–3's
field-photo direction and is why the revert was chosen.

**But the sweep also showed the constant is not the live error term**, which matters more:

- Swept 0.28 → 0.50 (eight values). Min MAE at 0.35, min |bias| at 0.38, min spread at 0.30 —
  three criteria, three different optima. No single scalar satisfies them.
- **The 60.27 kg pig barely moves.** Across a 79% change in the constant its error goes
  +25.8% → +23.4%; predictions span only 74.34–80.72 kg while the 125 kg pig swings 104 kg.
- **Every image bottoms out near 73 kg.** The regressor cannot emit a number below that.
- Cause, checked against `feature_domain`'s **raw** trained range: both light pigs sit below
  the trained minimum on every gated size feature (60.27 kg: `mask_area` 25425 < 36647,
  `perimeter` 733 < 861, `longest` 290 < 332, `shortest` 90 < 103). The model has never seen a
  pig that small and answers from its floor leaf — `pipeline.cpp`'s F22 `extrapolated`
  condition. Scaling cannot recover a vector outside the trained domain.
- The two in-domain pigs predict well at 0.35 (−4.1%, +1.1%), so segmentation, cutter, resample
  and features are sound. **The failure is the regressor's training coverage at the low end.**

## Decisions made

- **Revert to 0.35**, labelled as an empirical fit, not a derived constant. Its F21 provenance
  (fitted under the identity-stub cutter) is still contaminated; it wins on measurement, not on
  derivation.
- **Do not adopt the specification's 304 px/m.** `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`
  §24 states it is theoretical rig geometry and says to replace it if empirical calibration is
  obtained. That calibration now exists and 304 lost. This is one of F49's three honest
  outcomes and should be written down as such.
- **Do not reorder the pipeline (F48) yet.** Real divergence, but worth low single digits on
  boundary features, it invalidates round 4's segmentation tuning, and it cannot touch a 25%
  floor. Its own doc says quantify off-device first.
- **No ADR written.** The training-domain floor is likely ADR-worthy; that is `pipeline-docs`'
  call. ADR-005's replacement is still owed from round 5.

## The new instrument — `ML/host_scale_test/`

Reusable; do not treat as scratch. Replaces the 18-scan sideload cycle for any future constant
or cutter question. `README.md` in that folder has every command.

```
weight_branch_cli.cpp   reproduces pipeline.cpp's weight branch over the real stage sources
run_sweep.py            0.35 vs 0.3289, writes out/results.csv + 10 envelopes
sweep_constants.py      N-constant sweep, writes out/constant_sweep.json
CMakeLists.txt          standalone host build + vendor-source drift guard (19 features, 7 cutter)
third_party/            generated onnxruntime.lib + make_ort_lib.py
```

Both drivers patch temporary `assets/ml/manifest.test_*.json` copies (gitignored, deleted after
each run); `assets/ml/manifest.json` is never written. `run_sweep.py` asserts cross-arm
invariance and that the 0.3289 arm matches the unpatched manifest. Both were verified
byte-reproducible across full re-runs.

## Corrections to `docs/handoff.md` — it is wrong on three points now

1. **"No host target compiles `pipeline.cpp`" is now misleading.** `pipeline.cpp` itself still
   has no host target, but every stage it calls does:
   `ML/host_scale_test/CMakeLists.txt` builds `manifest/onnx_runner/image_io/sha256` +
   `stages/{segmentation,construction,cutter,feature_calculation,weight_prediction}` + the
   vendor V176 sources against vcpkg OpenCV 4.12.0 and a generated ORT import library.
2. **`instaham_ml_predict_weight_json` reporting `identity_stub` is a stale *label*, not a
   stale cutter.** `stages/cutter.cpp` runs the real V176/V144 chain; `cutter_status` was
   `cut_applied` on every run this session with `kept_fraction` 0.80–0.93.
   `ML/weight_runtime.py`'s docstring carries the same stale claim.
3. **`ML/pipeline/cutter.py` is not a valid oracle for the shipped cutter.** It implements
   protocol `ji_duan_residual_06q_v9_headfit_exact_twotangent_v26`; the app runs
   `v176_strict_nonprimary_break1_region_meet_v144_fixed_center_bilateral_circle_v1`. Any future
   host replication must build the C++, not call the Python cutter.

## Open questions

- **The ~73 kg regressor floor.** The biggest open item on the project now. If users weigh pigs
  under ~85 kg, every one reads high by 20%+ and no calibration fixes it. Needs its own phase.
- **F49 — the specification's standing.** Decided in substance above; not yet written anywhere
  a future session will find it. `docs/fix-phase-2/3-normalization-order.md` step 1.
- **Whether F38 is retracted.** Its post-cut `RA` table implied targets near 0.35 (0.347,
  0.361); this round supports it. Still not formally resolved.
- **The live-camera path remains entirely unmeasured.** Unchanged across four rounds. All device
  data is the gallery-import path at 2250 × 3000; this round is a host run on 960 × 540 PIGRGB
  images and touches the camera path no more than the previous ones did.
- **`weight_branch_cli.cpp` does not record `extrapolated` / `extrapolated_features`**, the
  fields that name the floor condition and that the app does emit. The excursion table was
  computed after the fact from envelopes. Add before the next sweep.

## Next steps

1. **Apply the revert.** `ML/export/export_xgboost.py` ~line 289, `0.3289` → `0.35`. Update the
   `_source` tag — do not restore the old `three_sample_field_estimate_...` string verbatim; it
   should now name this round's sweep as the evidence.
2. **Re-export** from the venv at `C:\ml_export_venv`. **`--enable-for-testing` is mandatory** —
   without it the fragment silently writes `weight.available: false`.
3. **Rebuild the manifest** with `--allow-key-removal` (HEAD is baseline5-era, so 28
   `RA/LC/BL/BW/E` keys legitimately drop). Check `git status` afterward —
   `build_manifest.py` stages assets before its guard runs.
4. **Verify with the harness before anything else** — `python ML/host_scale_test/run_sweep.py`,
   confirm the 0.35 arm reproduces `+25.7 / +20.1 / −4.1 / +1.1 / +6.6`. Note the re-export
   regenerates `xgboost.onnx` with a fresh sha256, so phase 3's precheck hash changes; that is
   expected, not a failure.
5. **Docs** (the user plans to run these skills next session): `spec-drift` after the re-export;
   `pipeline-docs` for the cutter/stage docs, the owed ADR-005 replacement, and an ADR for the
   training-domain floor if it is judged ADR-worthy; `planner` to close the revert question in
   `docs/fix-phase-2/2-scale-target-conflict.md` and write the round-6 changelog entry that is
   still missing. Fix the "currently 0.3289" wording in `docs/spec.md`,
   `docs/pipeline/prediction.md` and `prediction-2.md`.
6. **Then rebuild the APK.** The current sideload runs 0.3289.
7. **Then phase 2.1's fix**, still open, and `docs/fix-phase-2/3-normalization-order.md` after.
8. `docs/test-plan-phase/4-analysis.md` is written but not executed. Much of what it asks for
   now lives in `docs/scale-constant-sweep-results.md`; reconcile rather than redo.

## Document state

| document | state |
|---|---|
| `docs/test-plan.md` + `test-plan-phase/` | phases 1–3 **done**, phase 4 not started |
| `docs/scale-constant-sweep-results.md` | new, complete |
| `docs/logs/recorded.md` | round 4 added (host run; flagged not comparable to rounds 1–3) |
| `docs/fix-2.md` + `fix-phase-2/` | phases 1, 1.1 closed; 2 measured and now decided; 2.1 open; 3 not started |
| `docs/fix.md` + `fix-phase/` | round 5, open at phase 7, untouched for a fourth session |
| `docs/plan.md` | phase 5 unstarted |
| `docs/changelog.md` | still no round 6 entry |

## Changed this session

- `ML/host_scale_test/` — **new**, the whole harness (untracked).
- `docs/test-plan.md`, `docs/test-plan-phase/{1-host-toolchain,2-host-cli,3-driver-sweep,4-analysis}.md` — **new**.
- `docs/scale-constant-sweep-results.md` — **new**.
- `docs/logs/recorded.md` — round 4 appended.
- `.gitignore` — `ML/host_scale_test/build/`, the generated ORT binaries, `assets/ml/manifest.test_*.json`.
- `docs/handoff-2.md` — this file; a pointer line added at the top of `docs/handoff.md`.

Nothing under `lib/`, `packages/`, `assets/` or `ML/export/` was touched this session.

## Validation state

**No Dart or C++ in the app was changed, so nothing in the app was compiled, analyzed or
tested.** Last known-good remains 93 passed / 21 pre-existing skips.

What *was* verified, by execution: the host harness builds clean (39 translation units, MSVC
19.44); it loads the real manifest and both real ONNX graphs; it produces byte-identical output
across repeated runs and across full re-runs of both drivers; the vendor-source drift guard
fires correctly when given a wrong count; `assets/ml/manifest.json` was confirmed unmodified by
the sweeps.

**The manifest's pre-existing `M` in `git status` predates this session** (mtime 2026-09-08
22:53) — it is round 3's re-export, already recorded as uncommitted in `docs/handoff.md`.

## Build / environment state

Unchanged from `docs/handoff.md` except where corrected above: Flutter 3.44.8, Dart 3.12.2;
export venv `C:\ml_export_venv` (xgboost 3.4.1 + onnxruntime 1.29.0, no ultralytics/torch, so
segmentation cannot be re-exported); exporters run as modules from the repo root; a
`flutter pub get` inside a build window breaks the release build (F52); repo Python 3.13.1 has
onnxruntime/opencv/pillow-heif/scipy/skimage but **not** xgboost; logcat dumps are UTF-16LE with
CRLF.

New this session:

- Host build needs `vcvars64.bat` from `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`.
  It prints a harmless `'vswhere.exe' is not recognized` line and still initializes x64 correctly.
- vcpkg OpenCV 4.12.0 at `C:\vcpkg`; `VCPKG_ROOT` is **not** set, pass
  `-DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake` explicitly.
- No Windows ORT import library ships in-repo; one was generated from the pip DLL
  (`third_party/make_ort_lib.py`). Headers are API v17, runtime is 1.29.0 — a supported
  backward-compatible pairing, verified by real session loads.
- **`C:\Windows\System32\onnxruntime.dll` exists on this machine** (unrelated app) and supports
  only API 1–10. The app directory wins the DLL search order, so a correctly-built binary is
  fine — but if its local copy is missing, the process does **not** fail cleanly; it loads the
  System32 copy and segfaults with `The given version [17] is not supported`. Always run the
  binary from its own build directory.

## Carried forward untouched

`capabilities.weight.note`'s false first clause (`ML/export/export_xgboost.py:237` writes it
unconditionally); Dart's `cutterDeclineStatuses` lacks `jiduan_threw`;
`mask_shape_out_of_domain` unreachable; F45's ~5 s main-isolate analysis (user-accepted); the
`Hu_3`–`Hu_7` instability with no fix candidate targeting it;
`ML/tools/replicate_native_weight_branch.py` stale (baseline5-era, no cutter — superseded in
practice by `ML/host_scale_test/`, consider deleting it); the temporary `INSTAHAM_ENVELOPE` dump
in `lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`,
now more removable than before since the harness replaces the sweeps it existed for.

**Nothing is committed** — every change above is in the working tree.
