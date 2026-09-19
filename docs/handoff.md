# Handoff — 2026-09-19

## Active work

`fix.md` — specifically [`fix-4.md`](fix-4.md) (round 8), **reopened** this session. Phase 1.1
is done; **phase 3 is next**. Read `fix-4.md`'s "Reopening note" before anything else.

## Goal

Implement [`INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md`](../INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md)
as the specification — not as a proposal to evaluate. The user's instruction this session was
to **brute-force it**: implement it, ship it, raise disagreements as one-line flags rather than
as gates. The previous session's REJECT verdict is void.

Added to the round this session, from the user: **capture-orientation constraints** — portrait
captures require the pig's head facing up, landscape captures require the pig's head facing
right. Both land the pig head-right at the segmenter. Written up as phase 6.

## What this session did

1. **Adjusted the plans** via `planner` — the full diff of intent is in `fix-4.md`; do not
   re-derive it here. New files: [`fix-phase-4/1.1-readme-is-the-path.md`](fix-phase-4/1.1-readme-is-the-path.md),
   [`fix-phase-4/6-capture-orientation.md`](fix-phase-4/6-capture-orientation.md). Phases 1-5
   updated, F49 reopened in [`fix-phase-2/3-normalization-order.md`](fix-phase-2/3-normalization-order.md),
   retraction appended to `changelog.md`.
2. **Executed phase 1.1** — see that phase file for what changed and how it was verified.
   Committed.

## Decisions made

- **Phase 2's measurement is not repeated and not re-run.** Its corpus B regression stands on
  the record as an accepted counter-indication. Rationale is in `fix-4.md`; the numbers are in
  [`fix-phase-4-2-results.md`](fix-phase-4-2-results.md).
- **README §6's halt ships literally**, replacing phase 1's canvas-enlargement fallback. The
  user chose brute-force after being shown F61's consequence twice.
- **`pipeline.cpp` was deliberately left un-rewired.** App wiring is phase 4's scope. The
  consequence is below under blockers — it is the one thing in this handoff that is not
  recoverable from a file.

## Blockers / open questions

- **Do not build or sideload an APK before phase 4 lands.** Phase 1.1 collapsed
  `stages/segmentation.cpp` to the single normalize-first composition, but `pipeline.cpp` still
  calls it with the old round-4 ladder multipliers standing in for `cm_per_px_target`. The
  native library compiles and the host CLI is correct; the *app* path is temporarily wrong by
  construction. Phase 4 closes it.
- **The §6 halt needs a ruling from the user, before phase 4's device run.** It is no longer a
  prediction — it fired on the project's own corpus (see phase 1.1's Result section for the
  measured image and dimensions). Every full-resolution phone capture will halt. The three
  options put to the user were: ship the halt as-is and let phase 4's device run show it;
  downscale the capture before normalizing; or grow the canvas as an accepted design decision
  rather than a hedge. **The user asked to clarify the question and the session ended before
  they answered — ask again, do not pick one.**
- The retry ladder's removal from the README path is still untested for detection regressions.
  It was added in round 4 (F18/F19) because detection genuinely failed without it. Phase 4's
  device run is the first place a regression would surface. Recorded as a flag in `fix-4.md`.
- The mask coordinate-space conflict (`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §5.2 vs
  README §9/§12) is still unresolved and still ADR-worthy. `fix-4.md`'s open flags carry it.

## Next steps

1. **Phase 3** — [`fix-phase-4/3-constants.md`](fix-phase-4/3-constants.md). Reconcile
   `training_frame_px` (720x720) against the README's 960x540, and record the standing of the
   304 px/m baseline doc. Does not depend on the §6 ruling.
2. **Get the user's §6 ruling** before starting phase 4.
3. **Phase 4** — app wiring, including removing `pipeline.cpp`'s own ladder and regenerating
   the manifest through the exporter. **Never hand-edit `assets/ml/manifest.json`** — see
   `changelog.md`'s 2026-09-14 entry.
4. Phases 5 then 6. Phase 6 is Dart/UI work and is independent of the native phases.

## Build / environment

Unchanged from the previous handoff except for one correction worth keeping:

- **The native build directory is `packages/instaham_ml_ffi/src/build/host`** (Ninja
  generator), not `.../src/build`. Building against the latter fails with
  `Error: could not load cache`.
- Build from the **PowerShell tool**, invoking
  `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat`
  through `cmd /c` — BuildTools, *not* Community. The `'vswhere.exe' is not recognized` line is
  benign.
- The host CLI builds separately in `ML/host_scale_test/build`.
- `ctest` after this session: **8 of 9 pass**. `test_abi` and `test_scale_normalization` are
  pre-existing failures, unchanged from `06d2ecd`. `test_segmentation_canvas` newly passes
  after being rewritten in phase 1.1.
- Python is `C:\Users\Adrian Jared Sido\AppData\Local\Programs\Python\Python313\python.exe`.
  Plain `python`/`python3` from Bash hits the Microsoft Store stub and fails.
- Firebase Test Lab was not used and must not be submitted without an explicit instruction for
  that specific run.

## Rollback points

Branch `initial_health`, nothing pushed.

- `06d2ecd` — pre-README shipped behaviour.
- `d653956` — phase 1 as originally built (switch off by default, fallback and ladder intact).
  Created this session because that work had never been committed.
- `5b4d9f7` — phase 1.1, current HEAD.
