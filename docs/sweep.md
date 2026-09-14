# Plan: rebuild the `cm_per_px_target` scale-constant sweep — closed

Status: **closed, all 5 phases done.** Superseded by
[`scale-constant-sweep-results-2.md`](scale-constant-sweep-results-2.md) (the decision-facing
result) and the phase files under [`sweep-phase/`](sweep-phase/) (the run-by-run record, kept —
see the deviation note in [`sweep-phase/5-writeup.md`](sweep-phase/5-writeup.md) for why the
close-out contract's directory deletion was not applied this round).

This plan produced a current-pipeline comparison of `cm_per_px_target = 0.35` (fitted) against
`0.3289473684210526` (derived, ADR-011), plus a `k = 1.0` self-consistency arm and an N-arm
plateau sweep. Result: neither candidate is the empirical MAE optimum on either corpus; `0.34`
is, independently, on both. This round's decision was to ship `0.34`, contradicting ADR-011 —
flagged for `pipeline-docs` and not yet applied to `assets/ml/manifest.json`. Full reading,
caveats, and open flags in the successor document above.

`docs/plan.md`'s open question 1 is answered by this result; see that document.
