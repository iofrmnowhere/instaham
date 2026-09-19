# Phase 2 results — canvas_scale vs normalize_first, host measurement

Parent: [`fix-4.md`](fix-4.md) phase 2, [`fix-phase-4/2-measurement.md`](fix-phase-4/2-measurement.md).
Produced by `ML/host_scale_test/run_phase2_mode_ab.py`, run 2026-09-18. Raw envelopes and CSV
under `ML/host_scale_test/out/phase2_*`. `weight_branch_cli.cpp` gained three envelope fields
this run (`selected_box_frame_fraction`, `selected_mask_area_proto`, `runner_up_mask_area_proto`)
that already existed on `SegmentationOutput` but were not surfaced — needed for this phase's
near-tie visibility requirement.

## Setup

Two manifest copies of `assets/ml/manifest.json` (deleted after the run; the shipped file was
never edited): `canvas_scale` (mode absent, today's behaviour) and `normalize_first`
(`capabilities.segmentation.input_scale.mode = "normalize_first"`). Both otherwise identical —
same `cm_per_px_target = 0.34`, same `conf = 0.25`.

- Corpus A: `ML/host_scale_test/corpus_a/*.jpg` (the already-converted `.pig_pictures/` field
  photos), each with its own hand-marked `cm_per_px_actual`.
- Corpus B: `Instaham/PIGRGB-Weight/sub_1.88/*.png`, 5 images, `cm_per_px_actual =
  0.3289473684210526`.
- Jitter: the 18 recorded marks (3 photos x 6 marks, from `docs/logs/recorded.md` round 2) run
  through both arms, so the spread is compared arm-to-arm on the current code rather than
  against old device numbers.

## Detection

**9 of 9 images detected on both arms; no baseline detection failure exists for the new path to
fix.** `candidates_kept = 1` everywhere on both arms. Every corpus A image is portrait and every
corpus B image is landscape, so this corpus set cannot exercise a detection difference by
capture orientation — README §4's head-at-top assumption is not measured here, an acknowledged
gap.

## MAE / bias

| Corpus | Arm | MAE | Bias | n |
|---|---|---|---|---|
| A (75kg excluded, floor row per prior convention) | canvas_scale | 3.95% | −0.92% | 3 |
| A (75kg excluded) | normalize_first | 3.80% | −3.80% | 3 |
| A (all 4) | canvas_scale | 8.11% | — | 4 |
| A (all 4) | normalize_first | 7.49% | — | 4 |
| B | canvas_scale | 1.67% | +0.10% | 5 |
| B | normalize_first | 2.83% | −2.83% | 5 |

Corpus A's three-image MAE moved by **0.14 percentage points** (3.95% → 3.80%) — this is the
number the verdict rule tests, and it is far short of the 5.18-12.55% jitter band any real
improvement would need to clear. Corpus B, the frame-geometry-parity secondary check, got
**measurably worse** under `normalize_first` (1.67% → 2.83% MAE, and the bias flipped sign and
grew), with `used_normalize_first = true` on every corpus B row.

## Re-mark jitter (18 marks, 3 photos)

| Photo | canvas_scale spread | normalize_first spread | Direction |
|---|---|---|---|
| 92kg | 3.64% | 7.19% | worse (≈2x) |
| 96kg | 8.24% | 1.31% | much better |
| 118kg | 4.54% | 4.95% | roughly tied, slightly worse |

Mixed — one image improves substantially, one gets clearly worse, one is a wash. This is the
same shape of outcome that killed the round-6 phase-2.1 candidate: a per-image mixed result on
jitter is not evidence of a systematic win.

## F61 oversize canvas

**Never triggered.** On all 9 `normalize_first` rows, `canvas_w`/`canvas_h` equal
`canvas_w_requested`/`canvas_h_requested` (960x540 exactly). Hand computation confirms why:
corpus A's normalized-then-rotated content lands around 558-576 px on its long side, corpus
B's around 522-540 — both well inside the 960x540 bound. **The measurement therefore cannot
separate the frame-geometry-parity claim from the scale-normalization claim (phase 2's stated
reason for a third arm)** — no image in either corpus reaches the oversize path, so that split
is untested by this round. `selected_box_frame_fraction` was recorded per row for a future
near-tie check but no row showed a runner-up detection (`candidates_kept = 1` throughout, so
`runner_up_mask_area_proto = 0` everywhere).

## Extrapolation note

`75kg_pig_meter_stick.jpg`'s `difference` feature is flagged `extrapolated: true` under
`normalize_first` but `false` under `canvas_scale` — the new composition pushes at least one
feature outside the training domain on the lowest-weight image that isn't already excluded by
ADR-010's ~73-74 kg floor. Not disqualifying on its own, but a second domain-shift signal
alongside the MAE and jitter numbers above.

## Verdict: **Reject**

Applying the rules fixed in `fix-phase-4/2-measurement.md` before this run:

- Detection is tied (9/9 both arms) — no baseline failure exists to fix, so that adopt path is
  unavailable.
- Corpus A MAE moved 0.14 points, inside the 5.18-12.55% jitter band in either direction — this
  alone satisfies the reject rule.
- Corpus B MAE got worse and the jitter band is mixed with one clear regression, reinforcing
  rather than complicating the reject call — this is not the "inconclusive, ask the user" case.

**The shipped `canvas_scale` path stays. `normalize_first` does not ship.** Per
`fix-4.md`, phases 3-5 are not worked. The round closes by superseding
`INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md` with this measurement, and F49
(open since round 6) is closed on this basis. The ADR pipeline-docs owns should record: (a) this
reject verdict and why, (b) that F61's fallback remains unexercised and unvalidated by any
measurement, and (c) the still-open coordinate-space conflict between
`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §5.2 and the README's §9/§12, which this
rejection does not resolve — the README's stance loses on evidence, not the coordinate-space
question, which remains a separate decision.

## What was not measured

- No device run, no APK, no Test Lab (out of scope for phase 2, and Test Lab is not run without
  explicit instruction for that occasion).
- Detection rate by capture orientation (README §4) — corpus set has no landscape corpus A
  image or portrait corpus B image to compare.
- The F61 oversize-canvas path — never triggered by either corpus at 0.34 cm/px.
