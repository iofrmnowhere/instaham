# Session handoff — documentation build-out, round 4 still untested

**Active work:** `docs/fix.md`, phase 3 (`docs/fix-phase/3-open-verification.md`). No plan is
open.

**State:** ref_fix.md round 4 (F18–F23) is **applied and committed** (`c198456`, branch
`initial_health`) but **has never been run on a device**. The ±15% result quoted throughout
the docs comes from the Python harness, not from the app. Do not read any doc's "fixed"
language as verified.

This session wrote documentation only — no source, model, or manifest changes. The only
non-doc change is `handoff.md` moved from the repo root into `docs/` (staged rename).

## Goal

Stand up the `docs/` folder as the project's real documentation: architecture, FFI contract,
pipeline stages, ADRs, the active fix, the model I/O spec, and a changelog. Going forward all
fixes and plans live under `docs/`, not the repo root.

## Files created this session

- `docs/README.md` — routing index for everything below
- `docs/architecture.md` — app shape, data-flow diagram, the four boundaries that matter
- `docs/ffi-bridge.md` — the 14 C symbols, memory ownership, three-layer error model
- `docs/pipeline/README.md` — stage redirect table
- `docs/pipeline/segmentation.md` — stages 1–2, including the scale ladder
- `docs/pipeline/prediction.md` — stages 3–5, the six ordered weight checks
- `docs/adr/001-cutter-identity-stub.md`, `002-json-string-c-abi.md`,
  `003-scale-aware-segmentation-canvas.md`
- `docs/fix.md` + `docs/fix-phase/1-diagnosis.md`, `2-applied-changes.md`,
  `3-open-verification.md` — the active fix, split by the 150-line rule
- `docs/spec.md` — model I/O contract, initial capture (no drift check possible yet)
- `docs/changelog.md` — three backfilled entries, rounds 2–4

Read `docs/README.md` first; it points at all of the above. Do not re-derive any of it from
source — it was written by reading the tree, not `ref_fix.md`.

## Decisions made

- **Fix and plan docs live in `docs/`.** User's standing preference. The `planner` and
  `project-checklist` skills at `~/.claude/skills/` were patched this session to say
  `docs/plan.md`, `docs/fix.md`, `docs/spec.md`, etc. — they previously used bare filenames
  and would have written to the repo root. A byte-identical copy of these skills exists at
  `OneDrive/Documents/thesis-skills/` and was deliberately **left unpatched** at the user's
  instruction; it will drift.
- **Numbering continues at F25.** F1–F24 are cited from source comments; reusing them makes
  those comments point at the wrong item.
- **`build_fix.md` was left out of the changelog.** It is a separate fix thread (the
  `libinstaham_ml.so` link failure) whose own header still says "proposed, not applied". The
  APK evidently builds, so it probably was applied, but that was not confirmed from the tree.
- Three architectural decisions are in `docs/adr/` — reference by number, don't restate.

## Open questions

- Does the harness's round-4 result reproduce on device at all?
- **F24** (open, carried from round 4): the harness reports `RA` = 0.00728 on the 118 kg photo
  against the app's 0.00086, on a mask whose other four features agree within 5%. First thing
  to check is `RA`'s denominator, which flips with `scale_ok` between the manifest's 720×720
  training frame and the mask's own dimensions. F20's telemetry makes this a log read.
- Is `input_cm_per_px = 1.10` plus the ladder stable outside the three `.pig_pictures/`
  photos — one animal type, one photographer, one phone?

## Next steps

1. Run the harness first: `python ML/tools/replicate_native_weight_branch.py . T`. Seconds,
   not an APK cycle, and it is the loop that produced every number in the docs.
2. Rebuild native, sideload, re-run all three `.pig_pictures/` scans. The user tests on their
   own physical phone; there is no device or emulator attached to this environment.
3. Judge against the acceptance and non-acceptance criteria in
   `docs/fix-phase/3-open-verification.md` — note especially that the 96 kg photo is the
   control and must not regress.
4. Read the persisted `segmentation` / `construction` pipeline events from that run and
   settle F24, F25 (orientation sensitivity) and F26 (ladder-rung distribution) from the log.
5. If it passes, `planner` closes out `docs/fix.md` and appends the round-4 line to
   `docs/changelog.md`.

## Environment notes

- Branch `initial_health`; `docs/CODEX_TASK_TEMPLATE.md` was deleted before this session and
  is still unstaged. The `handoff.md` → `docs/handoff.md` rename is staged.
- No C++ toolchain in this environment — native changes cannot be compiled or run here.
  Python 3.13 with `numpy`, `opencv`, `onnxruntime` and `pillow-heif` **is** available, and
  `assets/ml/` carries the real exported models, which is what makes step 1 possible.
- Native deps (opencv-mobile, onnxruntime) are already fetched under
  `packages/instaham_ml_ffi/src/third_party/`; no `scripts/fetch_deps.sh` run needed.
- No Drift schema change is pending: no `schemaVersion` bump, no migration, no
  `build_runner`.
