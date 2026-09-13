# Session handoff — round 10: the constant is applied and shipped; the jitter fix was tried and failed

> **SUPERSEDED 2026-09-10 by `docs/handoff.md` (round 11).** That file is the single live
> handoff; this one is kept only as history and should be deleted once nothing references it.
> Do not start a session from this file.

**Supersedes round 9, which this file replaced in place.** `docs/handoff.md` is round 6 and is
older still; read this one.

**Active work: `fix.md` and `fix-2.md` are both live, and that is a real problem, not an
oversight.** `docs/fix-2.md` (round 6) is the one this session worked — phase 2 closed, phase
2.1 open. `docs/fix.md` (round 5) is still open at phase 7 and has now gone six sessions
untouched, which violates the sequential-phase rule the project otherwise follows. Decide next
session: close phase 7 (ADR-009 arguably already did the work it was tracking) or park it
explicitly.

**F-numbering continues at F55.** No new F opened this round.

## What happened

**1. The 0.35 revert is applied and shipped.** Round 9 decided it; this session executed it end
to end — `ML/export/export_xgboost.py` → re-export → manifest rebuild → the user rebuilt the APK
and confirmed it ships. `_source` is now
`host_scale_sweep_round6_f49_empirical_fit_not_derived`. Details in
`docs/fix-phase-2/2-scale-target-conflict.md`; the constant's three provisionality caveats in
`docs/spec.md`'s weight Output section. **Phase 2 is closed.**

**2. Phase 2.1's leading fix candidate was implemented, measured, and rejected.** The hypothesis
was that `INTER_NEAREST` at `construction.cpp:138` dominated reference-marking jitter. Built
into the host CLI and measured before/after across ten PIGRGB images: worst-case spread went
**11.9% → 14.4%**, mixed elsewhere. Reverted the same session. Table and interpretation in
`docs/fix-phase-2/2.1-reference-length-sensitivity.md` under "Rejected fix". The likely
explanation for the failure arrived at the end of the session — see Open questions.

## Decisions made

- **ADR-010 written** (`docs/adr/010-regressor-training-domain-floor.md`), superseding ADR-005.
  The ~73 kg floor, not the cutter and not the constant, is the dominant error. This also
  discharges the ADR-005 replacement owed since round 5.
- **The `weight.note` false first clause is fixed**, not re-flagged — `spec.md` had carried it
  two sessions. Also `unavailable_reason: cutter_identity_stub` → `weight_pending_field_validation`.
  Nothing in `manifest.cpp` or Dart reads either field. **The manifest changed after the APK
  build, so the sideload carries the old note text — cosmetic only, no rebuild needed.**
- **`construction.cpp:97` is deliberately not a fix target** — faithful port of
  `.old_py_files/yolo_inference.py:182-189`, and its target size comes from `decode_image_rgb()`
  before the scale-aware canvas exists, so it cannot move when the user re-marks. Recorded in 2.1.

## The new instrument — `ML/host_scale_test/jitter_sweep.py`

Measures reference-marking jitter without a sideload — the first tool here that can. Sweeps
`cm_per_px_actual` ±1% per image, reports predicted-weight spread, takes `--images-dir` /
`--height` / `--deltas`. Baselines in `out/jitter_sweep{,_1.88}{,_after}.json`; before-fix worst
cases **11.9%** (1.78 m) and **6.4%** (1.88 m).

Caveat in its docstring: a percentage-delta *proxy* for marking noise, not F53's real-pixel
procedure — these images carry no reference object — and it cannot reproduce item 1 (the
reference re-composing the segmentation canvas), which exists only on-device.

## Open questions

- **`structure.md` (repo root, untracked) proposes the better fix, and it is unevaluated.** It
  matches the shipped pipeline exactly through the 0.5 threshold, then diverges: it wants **one
  single geometric transform** doing unletterbox + undo-YOLO-resize + apply-`k` together. The
  code instead does two, detouring through full photo resolution
  (`640 → orig_w×orig_h → ×k`). On a phone photo that detour is a ~4.7× nearest-neighbour
  upscale followed by a downscale — two grid-snaps where one would do. **This is very likely why
  this session's fix failed**: `INTER_AREA` was applied at the second transform, after the
  detour had already destroyed the boundary. Composing the transforms keeps the ultralytics-
  faithful threshold at 640 (so gate B's IoU ≥ 0.95 parity survives) and touches only app-side
  code. Two caveats: `structure.md` puts the posture/truncation gates after the transform where
  the code runs them in original capture coordinates before it (both gates ship `false`, so
  latent); and the PIGRGB test images are 960×540, so the harness measures a 1.5× detour where
  a real capture is 4.7× — **the harness understates this defect**.
- **What the regressor's training masks actually were.** If they came from this YOLO pipeline,
  matching its quantization is correct. If they were ground-truth masks —
  `Instaham/PIGRGB-Weight/MASK_3394/` exists — then smoothing is *closer* to training, which
  changes the verdict on every candidate above. Not yet checked, and it gates the decision.
- **The ~73 kg floor** remains the largest open item (ADR-010). Needs its own phase; it is a
  retraining problem.
- **The live-camera path is still entirely unmeasured**, unchanged across five rounds.

## Next steps

1. **Check what `MASK_3394` contains and how training features were generated.** Cheap, and it
   decides the question above before any code is written.
2. **Scope the `structure.md` single-transform change** against `docs/fix-phase-2/3-normalization-order.md`
   — it is a cheaper partial of phase 3's F48 and should be evaluated as one, not duplicated.
   Measure with `jitter_sweep.py` against the recorded before-baselines.
3. Consider adding a **larger-resolution test image** to the harness, since 960×540 understates
   the detour defect.
4. **Resolve `docs/fix.md` phase 7** — close or park, per Active work above.
5. `docs/test-plan-phase/4-analysis.md` is written but not executed; much of it now lives in
   `docs/scale-constant-sweep-results.md`. Reconcile rather than redo.

## Document state

| document | state |
|---|---|
| `docs/fix-2.md` + `fix-phase-2/` | phases 1, 1.1, **2 closed**; 2.1 open with one candidate eliminated; 3 not started |
| `docs/fix.md` + `fix-phase/` | round 5, still open at phase 7, sixth session untouched |
| `docs/spec.md` | current as of 2026-09-09; flagged mismatch now resolved |
| `docs/adr/010-*.md` | new; ADR-005 marked superseded |
| `docs/changelog.md` | rounds 5, 6-phase-1, 6-phase-2 entries added |
| `docs/plan.md` | phase 5 unstarted — still owes the post-cut `cm_per_px_target` re-derivation |
| `structure.md` | untracked, repo root; see Open questions |

## Repository state

**The user committed and pushed mid-session** — `4aee92b` "0.35 px basis implemented, added
local sweep test" on `initial_health`. This supersedes round 9's "nothing is committed".

Uncommitted after that commit: `docs/fix-2.md`, `docs/fix-phase-2/2.1-*.md`,
`packages/instaham_ml_ffi/src/stages/construction.cpp` (comment only — the resize logic is
byte-identical to HEAD), plus untracked `ML/host_scale_test/jitter_sweep.py`, its four `out/`
JSONs, and `structure.md`.

`.gitignore` gained `instaham.sqlite` and `crash.txt` this session. **No `.onnx` is tracked** —
a fresh clone cannot run the app and the manifest's sha256 checks point at absent files. That
is pre-existing policy, not a regression, but it means the push is not a complete backup.

## Validation state

**No Flutter/Dart test suite was run this session** — no Dart changed. Last known-good remains
93 passed / 21 pre-existing skips.

Verified by execution: the host CLI rebuilt clean twice (fix applied, then reverted), 4/4
targets each time, zero warnings; `jitter_sweep.py` ran to completion on both image folders in
both build states; the re-export and manifest rebuild both produced the expected values, checked
by reading the manifest back.

**One incident worth knowing.** `build_manifest.py` run with only `--weight` silently deleted
the `health`, `segmentation` and `view` capabilities — the key-removal guard reported 106
dropped keys and proceeded anyway. **Always pass all four
`--view --health --weight --segmentation`**, and treat a large key-drop count as a stop signal,
not a confirmation. A `git checkout --` during recovery also discarded pre-existing uncommitted
state (recoverable from `build/ml_export/`, but the reflex was wrong).

## Build / environment state

Unchanged from round 9; full detail in `ML/host_scale_test/README.md`. The load-bearing points:
`--enable-for-testing` is mandatory on the weight export, `--allow-key-removal` on the manifest
rebuild, and the host binary must run from its own build directory because
`C:\Windows\System32\onnxruntime.dll` is an incompatible v1–10 build. Host rebuild:

```
cmd /c '"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" && cmake --build ML\host_scale_test\build'
```

## Carried forward untouched

`cutterDeclineStatuses` lacks `jiduan_threw`; `mask_shape_out_of_domain` unreachable; F45's
~5 s main-isolate analysis (user-accepted); `Hu_3`–`Hu_7` instability;
`ML/tools/replicate_native_weight_branch.py` stale, superseded by `ML/host_scale_test/`
(consider deleting); the temporary `INSTAHAM_ENVELOPE` dump in
`run_and_persist_pipeline_use_case.dart`, now removable — the harness replaces the sweeps it
existed for.
