# Session handoff — round 28: sweep phases 3, 4 and 5 executed; sweep plan closed

**Active work: `none` for plan/fix.** Neither `docs/plan.md` nor `docs/fix.md` was worked as the
live plan. `docs/plan.md` was edited once, as a phase 5 close-out step (open question 1 answered);
that is not an active-work claim on it.
**`docs/sweep.md` is now closed** — all five phases done, cleared to a stub pointing at the
successor document. F-numbering unchanged at **F59**.

**This file supersedes round 27.**

## Goal

Execute `docs/sweep.md` phases 3–5 and settle whether the shipped `cm_per_px_target` should be
the fitted `0.35` or the derived `0.3289473684210526`. Round 27 closed phases 1–2; this round
closed the rest and the plan.

## Current state

The sweep is finished and written up. **The answer is neither candidate: `0.34` is the measured
MAE minimum on both corpora, independently.** This round's decision, made by the user after
reviewing the tables, was to ship `0.34`. It has **not** shipped — `assets/ml/manifest.json` was
never written, and shipping it needs an ADR first (see Next steps).

Result and reading: `docs/scale-constant-sweep-results-2.md` (decision-facing).
Primary run record with per-image tables, entry conditions and the acceptance verdict:
`docs/sweep-phase/4-run-and-record.md`. Both corpora are reported separately throughout; do not
combine them.

## Files changed

Harness (`ML/host_scale_test/`):

- `run_sweep.py` — repointed at `sub_1.88`, direct `cm_per_px_actual`, 960×540 assertion, hard
  `k == 1.0` check, two float-precision fixes.
- `sweep_constants.py` — docstring plus `TARGETS` set to phase 4's eight-value list.
- `run_sweep_corpus_a.py` — **new**. Corpus A two-arm driver; corpus A needs its own because
  `cm_per_px_actual` is per-image there (one hand-marked reference object per photo), so
  `run_sweep.py`'s single-constant machinery does not apply and there is no `k = 1.0` arm.
- `sweep_constants_corpus_a.py` — **new**. Corpus A N-arm plateau sweep.
- `out/*` — results CSVs, 18 envelopes, two sweep JSONs. Untracked.

Docs:

- `docs/scale-constant-sweep-results-2.md` — **new**. The successor decision document.
- `docs/scale-constant-sweep-results.md` — superseded banner added; body untouched.
- `docs/conversion-justification.md` — §4 and §6 revised against the re-run; §6 action 2 closed,
  action 1 (1.88 m calibration capture) kept unsoftened.
- `docs/plan.md` — open question 1 struck through and answered.
- `docs/changelog.md` — one entry appended, dated 2026-09-14.
- `docs/sweep.md` — cleared to a closed-plan stub.
- `docs/sweep-phase/3,4,5-*.md` — statuses and checklists updated to what actually ran.

## Decisions made

1. **`0.34` over `0.35` and over the shipped `0.3289473684210526`.** User's call. `0.34` is the
   MAE minimum on corpus B (2.1%) and corpus A (4.0%) independently, with near-zero bias on B.
   The alternative argument — that `0.35`'s consistent underestimation is a safer direction for a
   weight readout — was raised and declined.
2. **The `0.34` decision contradicts [ADR-011](adr/011-derived-scale-target.md) and was flagged,
   not resolved.** Phase 5's scope explicitly stops at flagging; `pipeline-docs` owns the ADR.
3. **Two float-precision bugs had to be fixed before `k == 1.0` was exact**, and both are the
   kind that silently produce a near-miss instead of an error. Written up in
   `docs/sweep-phase/3-training-corpus.md`'s "Known hazards" — read that before touching the
   drivers again.
4. **`docs/sweep-phase/` was deliberately not deleted**, against phase 5's close-out contract,
   because the successor document cites `4-run-and-record.md` as its primary record. Rationale in
   `docs/sweep-phase/5-writeup.md`. Delete it only after moving that detail somewhere else.
5. **Corpus B's floor row and corpus A's excluded row are excluded for different reasons** —
   `74.4kg_9.png` by `extrapolated_features` (crosses the ~73 kg floor *between* arms, contrary
   to the phase doc's expectation that it would sit flat), `75kg_pig_meter_stick.jpg` because no
   device row exists to cross-check it. Do not describe the second as a floor-row exclusion.

## Open questions / blockers

- **Shipping `0.34` is a four-part sequence, none of it done:** an ADR (`pipeline-docs`);
  `assets/ml/manifest.json` **and** `ML/export/export_xgboost.py` moved together, or the next
  re-export silently reverts it (this trap already fired in round 25); `docs/pipeline/prediction*.md`
  updates; `spec-drift` re-verification of `capture_contract`.
- **The `k = 1.0` arm is the most consequential new finding and has no owner.** With the scale
  step a proven no-op, corpus B still shows 5.42% MAE and one image at +14.3%. That error belongs
  to segmentation, the cutter, feature extraction, the regressor, or the 304 px/m theory — not to
  this constant. It probably deserves its own fix or plan round.
- **Seven informative rows total** (4 + 3). Enough to rank `0.34` above both candidates, not
  enough to make that ranking durable against a larger corpus.
- **Corpus A is still a Route-2 host approximation.** Route 1 (device-side) remains preferred and
  unblocked only by the phone being absent.
- **The research-image question is open a fourth round.** `health_pigs/` and `.pig_pictures/` are
  tracked and pushed in `db13bbc`; `ML/host_scale_test/corpus_a/` is a second, derived copy of the
  same four photographs, still untracked. Decide before anything commits it.
- Carried unchanged, none addressed: the three unowned device findings in
  `docs/metrics-phase/6.2-metric-measurement-defects.md` Findings 4–6; the round-18
  view-classifier finding, still the most consequential open defect; no `thresholds.json`;
  `capabilities.weight.protocol_version` nested a level deeper than its siblings; `test_abi`
  failing on a stale pre-slice-2 expectation; `test_scale_normalization` failing at
  `test_scale_normalization.cpp:77`, undiagnosed; scenario 11 endpoints unmarked; scenario 9
  needing a second manifest copy; `weight_branch_cli.cpp` duplicating `pipeline.cpp`'s weight
  branch with nothing enforcing sync; `docs/design-system.md` ~211–216 stale about the cutter.

## Deliberately parked (do not propose as next steps)

`docs/fix-3.md` phase 4 and `docs/fix.md` phase 7 are open a **seventeenth** round. Subphase 5.1
remains parked permanently by round 20's decision 1.

## Next steps

1. **Decide whether `0.34` actually ships.** If yes, run `pipeline-docs` for the ADR first, then
   the manifest and exporter together, then `spec-drift`. If no, say so in
   `docs/scale-constant-sweep-results-2.md` — the decision is recorded there and nowhere else.
2. **Open a round for the `k = 1.0` residual.** This is the live lead the sweep uncovered, and no
   document owns it yet.
3. Answer the research-image question, now with a third copy of the four photographs on disk.
4. Then the parked `docs/fix.md` phase 7 / `docs/fix-3.md` phase 4, if they are ever unparked.

## Build / environment state

Round 20's environment section still holds for the native/host side; Test Lab specifics live in
`docs/device-testing-plan.md`; harness toolchain is in `ML/host_scale_test/README.md`.

- **`weight_branch_cli.exe` is still current as of 2026-09-13 23:08:55** — re-verified newer than
  every file under `packages/instaham_ml_ffi/src/`. **No rebuild happened this round**, so no
  `vcvars64.bat` shell was needed.
- **Shelling out to `cmd.exe` from the Bash tool needs `MSYS_NO_PATHCONV=1`.** Without it the run
  hangs looking like a slow build. Also noted in `docs/sweep-phase/1-harness-rebuild.md`.
- Full sweeps are slow on this host: 40 CLI calls ≈ 4 min. Run them backgrounded.
- Host ONNX Runtime is 1.29.0 against API-17 headers — the supported pairing, do not "fix" it.
- `python` works on this host; `python3` does not. `Pillow` 12.3.0 is available and `run_sweep.py`
  now imports it for the dimension assertion.
- **Quota, unchanged from round 27:** `instaham-test-lab` **exhausted** (5/5);
  `instaham-test-lab-2` has **2 of 5 spent**. **Nothing was spent this round.**
- **Standing user rule, unchanged: never submit a Test Lab run without explicit per-run
  approval.**

## Repository state

`origin/initial_health` is at `db13bbc`. Everything above is uncommitted, on top of round 25's
`.gitignore` line and rounds 26–27's documents. No patched `manifest.test_*.json` copies remain
(verified); `assets/ml/manifest.json` was never written.

Round 18's warning still holds: `generate_fixtures.py` clobbers every fixture's `meta.json`, so
snapshot `test/fixtures/scenarios/` before running it. It was not run this round.
