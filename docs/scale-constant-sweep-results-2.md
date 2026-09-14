# `cm_per_px_target` sweep — host results, re-run (2026-09-14)

Supersedes [`scale-constant-sweep-results.md`](scale-constant-sweep-results.md), which measured
the pre-F55 double-rasterisation path over the retired `sub_1.78/` corpus. This document
re-measures the same question on the current pipeline: `weight_branch_cli.cpp`'s single composed
`transform_mask_to_training_space()`, over `PIGRGB-Weight/sub_1.88/` (replacing `sub_1.78/`, no
1.78→1.88 m rescaling assumption needed) and `.pig_pictures/` (four field photographs, corpus A).

Full run detail, entry-condition checks, per-image tables and acceptance-criteria verdict:
[`sweep-phase/4-run-and-record.md`](sweep-phase/4-run-and-record.md). This document is the
decision-facing summary; that one is the primary record.

## What was run

| what | value |
|---|---|
| binary | `ML/host_scale_test/build/weight_branch_cli.exe`, built 2026-09-13 23:08:55, newer than every linked source |
| manifest digest | `assets/ml/manifest.json` SHA-256 `b3fdfd6e615b4c0314cfee9005a2b86da4ab07ab20393f5b63cf436d1dea318f`; committed `cm_per_px_target` is `0.3289473684210526` (ADR-011) |
| corpus B | `Instaham/PIGRGB-Weight/sub_1.88/`, 5 PNGs, 960×540, `cm_per_px_actual = 0.3289473684210526` (`100/304`, no rescaling) |
| corpus A route | Route 2, host-side (no device attached); decoders `pillow_heif` 1.6.0 / `libheif` 1.23.2 / `Pillow` 12.3.0 — see [`sweep-phase/2-corpus-a-results.md`](sweep-phase/2-corpus-a-results.md) |
| ONNX Runtime | host build 1.29.0 against API-17 headers — a host number, not a device number |
| drivers | `ML/host_scale_test/run_sweep.py`, `run_sweep_corpus_a.py`, `sweep_constants.py`, `sweep_constants_corpus_a.py` |
| raw output | `ML/host_scale_test/out/{results.csv, results_corpus_a.csv, constant_sweep.json, constant_sweep_corpus_a.json, envelope_*.json}` |

## Two-arm result: `0.35` vs `0.3289473684210526`

| corpus | rows | `0.35` MAE / bias | `0.3289…` MAE / bias |
|---|---|---|---|
| B (`sub_1.88`, 4 informative rows, floor row excluded) | 4 | 4.1% / −4.1% | 5.4% / +5.4% |
| A (`.pig_pictures`, 3 informative rows, no-device-row excluded) | 3 | 7.4% / −7.4% | 7.7% / +4.2% |

`0.35` has a lower MAE on both corpora, but the margin is inside corpus A's 5.18–12.55%
hand-marking jitter band, and smaller on corpus B than the residual error the `k = 1.0` arm shows
exists independent of scaling (below). Neither this margin nor the direction reversal in bias
(consistent underestimate at 0.35, mixed at 0.3289) is a clean win for either candidate.

## The `k = 1.0` result

Corpus B's `cm_per_px_actual` is `0.3289473684210526` — bit-identical to the shipped
`cm_per_px_target` — so setting the target to the same value makes `k` exactly `1.0` and the
resample step a genuine no-op (`mask_area_px` confirmed unchanged, not merely close). This arm
therefore isolates everything **except** the scale constant: segmentation, the cutter, feature
extraction, the regressor, and the 304 px/m geometric theory.

Per-image signed error, floor row excluded: **+2.46%, +14.29%, +4.79%, −0.16%** — MAE **5.42%**,
bias **+5.35%**. Zero contribution from scaling, and the error is not negligible: one image at
+14.3%, a one-sided bias. **This bounds how good any constant choice can make corpus B look** —
no value of `cm_per_px_target` can push corpus B's MAE meaningfully below ~5%, because that much
error is already present with scaling turned off. The two-arm result above should be read against
this floor, not against zero.

## N-arm plateau sweep

Targets `0.28, 0.30, 0.3289473684210526, 0.34, 0.35, 0.36, 0.38, 0.42` — dense through the
0.32–0.36 band `docs/fix-phase/1-diagnosis.md` already identified as an equivalence region.

| target | corpus B MAE % (4 rows) | corpus A MAE % (3 rows) |
|---|---|---|
| 0.28 | 49.2 | 41.1 |
| 0.30 | 27.2 | 26.9 |
| 0.3289473684210526 | 5.4 | 7.7 |
| **0.34** | **2.1** | **4.0** |
| 0.35 | 4.1 | 7.4 |
| 0.36 | 7.5 | 12.2 |
| 0.38 | 14.2 | 19.7 |
| 0.42 | 20.0 | 22.8 |

**Both corpora independently minimize MAE at `0.34` — a value neither candidate under test.**
Full per-image tables, including bias and spread, in
[`sweep-phase/4-run-and-record.md`](sweep-phase/4-run-and-record.md#run-3--n-arm-plateau-sweep).

## Reading

Verdict, in the terms `sweep-phase/4-run-and-record.md` set out: **(b), plateau, qualified by
(c).** Neither `0.35` nor `0.3289473684210526` is the empirical optimum on either corpus; `0.34`
is, independently, on both — evidence that the choice between the two candidates specifically
does not matter much, because the true surface is a shallow bowl through 0.32–0.36, not a step
function with either candidate sitting at a distinguishable point on it. The `k = 1.0` arm shows
this plainly: roughly 5% of corpus B's error is present with the constant contributing nothing at
all, which caps what any single scalar here can fix.

**This round's decision: ship `0.34`.** Chosen from within the plateau as the measured minimum on
both corpora (2.1% / 4.0% MAE, near-zero bias on B at +0.2%), over `0.35`'s deliberate
underestimation bias and over the currently-shipped `0.3289473684210526`, which is the worst of
the three candidates on both corpora's MAE.

**This contradicts [ADR-011](adr/011-derived-scale-target.md), which ships
`0.3289473684210526`.** ADR-011 reasoned from the pre-F55, `sub_1.78`-based sweep and its own
text says the accuracy consequence of its change was "presently unknown" pending exactly this
re-run. That re-run is now done, and on both corpora `0.3289473684210526` has the highest MAE of
the three candidates compared here. Per this phase's scope, that contradiction is flagged here
and not resolved here — **no ADR is written by this document**; recording or superseding ADR-011
is `pipeline-docs`' decision to make, informed by the tables above.

## Caveats, carried and new

- **Seven informative rows total** (4 corpus B + 3 corpus A). Enough to see a large difference
  between candidates, not a small one — the `0.34` vs `0.35` gap (2 points on B, 3.4 on A) is
  within what 7 rows can plausibly resolve, but is not proof against a larger corpus reshuffling
  the ranking.
- **Corpus A is a Route-2 host approximation**, not the device path; see
  `sweep-phase/2-corpus-a-results.md` for the cross-check that validates it.
- **Corpus B is the regressor's own training distribution.** Good agreement there is partly
  memorisation and does not predict field accuracy on its own — corpus A's independent minimum at
  the same value (`0.34`) is the stronger evidence.
- **Both corpora's floor rows are genuinely floor rows, for different reasons**, and both are
  excluded from every aggregate above: corpus B's `74.4kg_9.png` is confirmed by
  `extrapolated_features` (`[]` at `0.35`, `["shortest"]` at the derived constant — it crosses the
  ~73 kg regressor floor between arms, ADR-010); corpus A's `75kg_pig_meter_stick.jpg` has no
  device-recorded row to cross-check against, a narrower and unrelated reason.
- **Host-only.** ONNX Runtime 1.29.0 on the host vs the Android `.so` on device — same graphs,
  not bit-identical. Do not present these numbers as device numbers.
- **This document does not change what ships.** `assets/ml/manifest.json` was not edited by this
  round; only gitignored `manifest.test_*.json` copies were used and deleted after each run. See
  "What follows" below for what actually shipping `0.34` requires.

## What follows

Flagged for owners outside this document's scope (`AGENTS.md` skill ownership):

1. **`pipeline-docs`** — an ADR recording or superseding ADR-011 with this round's measurement,
   if `0.34` ships.
2. **`pipeline-docs`** — update `docs/pipeline/prediction.md`, `prediction-2.md`,
   `prediction-4.md`, which carry the shipped constant and the standing "no accuracy figure may
   be quoted" rule this round's `k = 1.0` result and MAE tables partially lift.
3. **`spec-drift`** — re-verify `docs/spec.md`'s `capture_contract` if the constant changes.
4. **Manifest + exporter, together.** `ML/export/export_xgboost.py` emits both
   `cm_per_px_target` and the `weight.note` text alongside `assets/ml/manifest.json`. If `0.34`
   ships, both must move together or the next re-export silently reverts the manifest to whatever
   the exporter still hardcodes — this already happened once, in round 25.
5. **The 1.88 m calibration capture** (`docs/conversion-justification.md` §6 action 1) still
   stands regardless of this result. It is the only route to a *measured* rather than derived or
   fitted `cm_per_px_target`, and nothing in this round's numbers reduces its value.
