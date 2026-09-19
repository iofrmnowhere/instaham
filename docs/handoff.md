# Handoff — 2026-09-18 (session 2)

## Active work

`fix.md` — specifically [`fix-4.md`](fix-4.md) (round 8). **Read the correction below before
anything else.** The round is currently recorded on disk as closed with a REJECT verdict; the
user overruled that at the end of the session. Do not act on the reject.

## Goal

Implement [`INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md`](../INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md)
— normalize the capture to 0.34 cm/px *before* YOLO, rotate portrait 90° clockwise, centre it
unchanged on a 960x540 canvas, segment, then undo canvas and rotation. The user designated that
file as the basis for this work.

## The correction — start here

The plan built the README's change **behind a manifest switch that defaults off**, then made it
win an A/B measurement before it was allowed to ship. It "lost" on a 0.14 percentage-point MAE
difference, and the round was closed as REJECT.

The user's response: *"we are only talking about scaling are you following the md file I told
you to serve as basis? Did you overthink the plan?"*

A measurement gate that can reject the designated spec is itself a counter-proposal. Treat the
reject verdict as overruled. The measurement in
[`fix-phase-4-2-results.md`](fix-phase-4-2-results.md) is a one-line flag to the user — corpus B
measured worse, corpus A was a wash — not authority to discard their document.

**Also discovered, and worse than it first looked:**
`packages/instaham_ml_ffi/src/pipeline.cpp` never calls the normalize-first path and does not
read `input_scale_mode` at all. Only `ML/host_scale_test/weight_branch_cli.cpp` honours it.
**The app has never once run the README's pipeline** — phase 1 landed it in the host harness
only.

## How phases 1-2 diverge from the README

1. Built as an off-by-default manifest switch; the README states this *is* the pipeline.
2. Host CLI only; `pipeline.cpp` (the app, README §13's sequence) never calls it.
3. Retry ladder kept (4 rungs); README §13 is a single pass at one scale.
4. F61 oversize-canvas fallback added; README §6 says halt and investigate, never fall back.
5. Inverse rotation happens one stage later (`rotate_pig_mask_90_ccw`, after mask construction)
   than README §8 describes. Same result, different place.
6. stb `BOX`/`TRIANGLE` resize filters instead of README §2's OpenCV `INTER_AREA`/
   `INTER_LINEAR` — `image_io.cpp` carries no OpenCV.
7. Phase 2 itself appears nowhere in the README, which says implement, not A/B test.
8. §16's ten debug stage outputs — never done (was phase 5).
9. §17's required assertions — never done (was phase 5).
10. §12's coordinate rule — unresolved, still conflicts with
    [`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md`](../INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md)
    §5.2.

Items 1 and 2 are the substantive ones. Everything was built, then left switched off and
unplugged from the app.

## What this session did

- Bookkeeping via `planner`: `fix-4.md` phase 1 marked done; `fix-3.md` phase 4 deferred then
  noted as no longer gated; coordinate-space conflict recorded as an ADR-worthy open flag.
- Executed `fix-4.md` phase 2 — the measurement. Numbers, method and the verdict rules applied
  are in [`fix-phase-4-2-results.md`](fix-phase-4-2-results.md); not repeated here.
- Recorded REJECT and closed the round across `fix-4.md`, `fix-phase-4/2-measurement.md`,
  `fix-phase-2/3-normalization-order.md` (F49) and `changelog.md`. **All of that now needs
  revisiting.**

## Open questions

- **Which document governs the mask's destination coordinate space** —
  `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §5.2 (original image coordinates) vs the
  README's §9/§12 (0.34 cm/px, forbids full-resolution camera coordinates). Unresolved; ADR is
  `pipeline-docs`' file. Recorded in `fix-4.md`'s open flags.
- **The retry ladder and the F61 fallback** both exist in code and are both forbidden by the
  README (§13 and §6). Their fate is a decision for the user, not an implementation detail.
- The user asked to defer discussion: *"let's do a handoff for now and talk about the issues
  next time."* The list above is the agenda, not agreed work.

## Next steps

1. Discuss the issues above with the user before implementing — that is what they asked for.
2. Reopen `fix-4.md`: phase table, verification section, `fix-phase-4/2-measurement.md`'s
   status line, the F49 closure in `fix-phase-2/3-normalization-order.md`, and the
   `changelog.md` entry all record an overruled verdict. Via `planner`.
3. Wire `pipeline.cpp` to honour `input_scale_mode` (README §13).
4. Declare `input_scale.mode = "normalize_first"` in `ML/export/export_yolo.py` (~line 130) and
   regenerate `assets/ml/manifest.json` by re-running the exporter. **Never hand-edit the
   manifest** — see `changelog.md`'s 2026-09-14 entry for why.
5. README §16 (debug outputs) and §17 (assertions).

## Files created / changed

- `docs/fix-phase-4-2-results.md` — the phase 2 measurement, tables and verdict (verdict now
  overruled).
- `ML/host_scale_test/run_phase2_mode_ab.py` — two-arm A/B driver; patches manifest copies,
  never the shipped asset.
- `ML/host_scale_test/out/phase2_*` — 18 envelopes, `phase2_results.csv`, `phase2_jitter.json`.
- `ML/host_scale_test/weight_branch_cli.cpp` — emits `selected_box_frame_fraction`,
  `selected_mask_area_proto`, `runner_up_mask_area_proto` (already on `SegmentationOutput`,
  previously unsurfaced).
- Docs touched by `planner`: `fix-4.md`, `fix-phase-4/1-normalize-before-segment.md`,
  `fix-phase-4/2-measurement.md`, `fix-3.md`, `fix-phase-3/4-validation.md`,
  `fix-phase-2/3-normalization-order.md`, `changelog.md`.
- `assets/ml/manifest.json` was never edited; the two patched test copies were deleted by the
  script.

## Build / environment

- **Build from the PowerShell tool, not Bash.** vcvars lives at
  `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat`
  — BuildTools, *not* Community; the Community path does not exist on this machine. The
  `'vswhere.exe' is not recognized` line it prints is benign.
- Python is `C:\Users\Adrian Jared Sido\AppData\Local\Programs\Python\Python313\python.exe`.
  Plain `python`/`python3` from Bash hits the Microsoft Store stub and fails.
- `ctest` after this session: **7 of 9 pass**. `test_abi` and `test_scale_normalization` fail
  and were already failing beforehand (confirmed against `06d2ecd` last session).
- A full phase 2 run takes roughly 20-25 minutes — every CLI invocation reloads both ONNX
  models.
- Firebase Test Lab was not used and must not be submitted without an explicit instruction for
  that specific run.
