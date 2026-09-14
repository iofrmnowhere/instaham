# Docs Index

Routing only. Follow one link — do not read the folder.

## Start here

- [handoff.md](handoff.md) — current session state, read this first
- [changelog.md](changelog.md) — closed-out work log, one line per closed plan or fix

## Contracts and reference

- [spec.md](spec.md) — model I/O contract, the shipped manifest's values and what verified them (spec-drift)
- [architecture.md](architecture.md) — app shape, Flutter↔FFI↔C++↔ONNX, and the boundaries that matter
- [architecture-2.md](architecture-2.md) — `lib/` module layout, layering rules, the FFI seam
- [ffi-bridge.md](ffi-bridge.md) — Dart↔C++ signatures, memory ownership, error propagation
- [app-flow.md](app-flow.md) — capture → routing → one native call → persisted results, and what each result card may claim
- [design-system.md](design-system.md) — UI contract: tokens, widgets, screen structure, accessibility floors
- [pipeline/README.md](pipeline/README.md) — pipeline stage redirect table; open the one file it names, never the folder
- [adr/](adr/) — architectural decision records, numbered and titled; read filenames first, open one. ADRs are immutable — a reversal is a new ADR that supersedes the old
- [libraries-app.md](libraries-app.md) — every library the app and its FFI plugin link, and why
- [INSTAHAM_CAMERA_SCALE_NORMALIZATION.md](INSTAHAM_CAMERA_SCALE_NORMALIZATION.md) — the camera-scale specification; authority for the PIGRGB floor-plane 304 px/m baseline

## Active work (planner)

- [plan.md](plan.md) / [fix.md](fix.md) — the live plan and fix documents
- [fix-2.md](fix-2.md) — round 6: the weight branch froze the app after "Confirm analysis" (phases 2.1 and 3 superseded by `fix-3.md`)
- [fix-3.md](fix-3.md) — round 7: the weight branch rasterized the mask twice; F55's composed transform
- [metrics-plan.md](metrics-plan.md) — activating the 21 skipped tests across the §14/§16 metric suite
- [test-plan.md](test-plan.md) — host-side replication of the weight branch to settle `cm_per_px_target`
- [sweep.md](sweep.md) — closed: the `cm_per_px_target` sweep rebuild; see the results document below

## Measurements and results

Observed numbers, not predictions. Check each one's status banner before citing it.

- [scale-constant-sweep-results-2.md](scale-constant-sweep-results-2.md) — **current.** The 2026-09-14 two-corpus sweep on the post-F55 path: both corpora minimize MAE at 0.34, plus the `k = 1.0` arm isolating ~5% residual error from non-scaling stages
- [scale-constant-sweep-results.md](scale-constant-sweep-results.md) — **superseded.** Measured the pre-F55 double-rasterisation path over the retired `sub_1.78/` corpus; do not cite its numbers
- [conversion-justification.md](conversion-justification.md) — how 0.35 was originally fitted and whether fitting the constant at all was valid
- [device-metrics-results.md](device-metrics-results.md) — metrics 1–3 measured across three device tiers on Firebase Test Lab
- [metric-4-results.md](metric-4-results.md) — mobile model package file sizes
- [metric-6-results.md](metric-6-results.md) — quantization and model export parity
- [metric-16-traceability-results.md](metric-16-traceability-results.md) — §16 traceability, and the missing `thresholds.json` gap

## Runbooks and environment

- [device-testing-plan.md](device-testing-plan.md) — Firebase Test Lab runbook. Free-tier quota is 5 physical device runs per day; never submit a run without explicit per-run approval
- [firebase-setup.md](firebase-setup.md) — the one-time Test Lab setup required before a device run can happen at all
- [phase2-toolchain-teardown.md](phase2-toolchain-teardown.md) — what the host C++ build installed on this machine, and how to remove it

## Folders

Listed as folders deliberately — open the parent document above, which indexes the phases, rather than reading these directly.

- [plan-phase/](plan-phase/) — phase files split out of `plan.md` under the 150-line rule
- [fix-phase/](fix-phase/), [fix-phase-2/](fix-phase-2/), [fix-phase-3/](fix-phase-3/) — phase files for `fix.md`, `fix-2.md` and `fix-3.md` respectively
- [metrics-phase/](metrics-phase/) — phase files for `metrics-plan.md`, including the device-metric defect findings
- [test-plan-phase/](test-plan-phase/) — phase files for `test-plan.md`
- [sweep-phase/](sweep-phase/) — phase files for the closed `sweep.md`; `4-run-and-record.md` is the primary record behind the current sweep results
- [logs/](logs/) — raw captured output: device scans, builds, reference-marking runs. Evidence, not narrative

## History

- [handoff-2.md](handoff-2.md) — superseded round-10 handoff, kept only as history; delete once nothing references it
