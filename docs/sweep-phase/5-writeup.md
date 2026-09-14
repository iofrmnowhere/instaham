# Phase 5 — write up and supersede the stale document

Status: done

## Goal

Convert phase 4's tables into a decision document, retire
`docs/scale-constant-sweep-results.md`, and propagate whatever the result implies — without
overstepping into documents this plan does not own.

## Steps

- [x] **Supersede `docs/scale-constant-sweep-results.md`.** Body left intact; superseded banner
      added at the top naming the successor (`scale-constant-sweep-results-2.md`) and the reason
      (pre-F55 double-rasterisation path + retired `sub_1.78` corpus).
- [x] **Write the successor document.** `docs/scale-constant-sweep-results-2.md` — what was run,
      the two-arm table (both corpora separate), the `k = 1.0` result in its own section, the
      N-arm plateau table, the reading, caveats, and a "What follows" flag list.
- [x] **Update `docs/conversion-justification.md`.** §4 revised: the 2026-09-09 out-of-sample
      check it credited to 0.35 no longer establishes what the section used it to establish, and
      now points at the successor doc. §6 revised: action 2 (re-run) is marked done with its
      result summarized; action 1 (1.88 m calibration capture) is kept, unsoftened, with an added
      note that the `k = 1.0` arm's residual error floor means this action is needed regardless
      of which constant ships.
- [x] **State the shipping decision explicitly.** Verdict is **(b) plateau, qualified by (c)** —
      neither candidate is the empirical optimum, `0.34` is on both corpora. **This round's
      decision (user call, made after reviewing phase 4's tables): ship `0.34`.** Stated plainly
      in the successor document's "Reading" section that this **contradicts ADR-011**
      (which ships `0.3289473684210526`), and stopped there — no ADR written by this phase, per
      "What this phase does not do" below.

## What this phase does not do

Ownership boundaries, from AGENTS.md. Each of these is flagged for its owner, not written here.

- **No ADR.** If the result changes or confirms the shipped constant on new evidence, that is
  ADR-worthy and belongs to `pipeline-docs`. Flag it; do not write it.
- **No `docs/pipeline/*` edits.** `prediction.md`, `prediction-2.md` and `prediction-4.md` all
  carry the shipped constant and the standing rule that no accuracy figure may be quoted against
  it. That rule is exactly what phase 4 lifts, so those files need updating — by `pipeline-docs`.
- **No `docs/spec.md` edits.** If the constant changes, that is a `capture_contract` change and
  `spec-drift` owns the re-verification.
- **No `assets/ml/manifest.json` edit and no re-export.** If the constant changes, note that
  `ML/export/export_xgboost.py` emits both `cm_per_px_target` and the `weight.note` text, so the
  generator and the asset must move together or the next re-export silently reverts the change.
  That trap already fired once, in round 25.

## Closing out

- [x] Appended one line to `docs/changelog.md`, dated 2026-09-14, with the `0.34`/ADR-011
      contradiction and the `pipeline-docs` flag stated in the entry itself (no ADR number to
      reference yet — none has been written).
- [x] Updated `docs/plan.md`'s open question 1: struck through, answered, pointing at the
      successor document.
- [x] Cleared `docs/sweep.md` to a short closed-plan stub pointing at the successor document.
      **Deviation: did not delete `docs/sweep-phase/`.** The successor document
      (`scale-constant-sweep-results-2.md`) repeatedly cites `4-run-and-record.md` as "the
      primary record" with per-image tables, envelope paths and acceptance-criteria detail this
      summary does not repeat. Deleting the directory would break those references and discard
      the only copy of that detail. Directory deletion is also hard to reverse cleanly and wasn't
      asked for explicitly — flagging this rather than doing it silently. Left the whole
      `sweep-phase/` tree in place, all five phase files already marked `Status: done`.

## Verification

- [x] `docs/scale-constant-sweep-results.md` carries a superseded marker naming its successor.
- [x] No document in the repository quotes an MAE or bias figure against either constant that is
      not sourced from phase 4's run — `conversion-justification.md` and `plan.md`'s edits both
      cite figures already in `scale-constant-sweep-results-2.md`/`4-run-and-record.md`; no new
      figures introduced.
- [x] `grep` for `sub_1.78` across `docs/` returns only historical references marked as
      describing a retired corpus — confirmed: only in the superseded doc's now-banner-marked
      body and in this plan's own "retirement" language.
- [x] The flags for `pipeline-docs` and `spec-drift` are written down where they will be seen:
      `scale-constant-sweep-results-2.md`'s "What follows" section, and the changelog entry
      above. **Not** additionally written into `docs/handoff.md` directly — `handoff` owns that
      file exclusively as an end-of-session overwrite (per `AGENTS.md`), so hand-editing it here
      mid-session would conflict with that ownership; the next `handoff` run will pick these
      flags up from the changelog and successor document.
