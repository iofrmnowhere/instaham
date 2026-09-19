# Phase 2 — Measure it: detection, MAE and jitter against the shipped path

Status: done 2026-09-18 — **verdict VOID as of 2026-09-19. Do not repeat this phase.**

**The REJECT verdict is overruled and carries no authority.** The user designated
[`INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md`](../../INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md)
as the basis for round 8; this phase was a gate that could discard that basis, which made it a
counter-proposal rather than a plan step. The round now brute-forces the README, and no phase in
it is a gate.

What survives: the measured numbers, as observations. Corpus B measuring worse is a real,
recorded counter-indication to the change this round ships, and the parent document carries it
as such. It is not a reason to skip phases 3 to 6. The "verdict rules" section below is retained
only so the void verdict's reasoning is auditable — do not apply it.

Also note the numbers predate phase 6's capture-orientation rule, so neither corpus satisfies
it. That is a second reason not to re-run this comparison as written.

Full results, tables and the CLI/script changes that produced them: [`../fix-phase-4-2-results.md`](../fix-phase-4-2-results.md).
Summary: detection tied 9/9 both arms on corpora A+B; corpus A MAE moved 0.14pp
(3.95% -> 3.80%), inside the 5.18-12.55% jitter band; corpus B MAE got worse (1.67% -> 2.83%);
re-mark jitter mixed (92kg worse, 96kg much better, 118kg roughly flat); F61's oversize-canvas
fallback never triggered on either corpus, so the frame-geometry-parity claim was never
separated from scale normalization. Per the verdict rules below, this is Reject, not
Inconclusive.

Parent: [`../fix-4.md`](../fix-4.md). ~~This phase is the round's gate. If the new path does not
win here, phases 3 to 5 are not worked and the round closes by superseding the README.~~
Struck 2026-09-19: the round has no gate, and the README is not superseded by anything in this
document.

## Symptom

The README's central claim — that presenting the pig in training-like framing fixes the
segmentation failures — has never been measured on this project's corpora. The shipped path was
tuned in round 4 against real detections; the proposed path has no numbers at all.

## Root cause

Not a defect. This phase exists because
[`fix-phase-2/3-normalization-order.md`](../fix-phase-2/3-normalization-order.md) F48 asked for
exactly this measurement before any reorder, and it was never taken.

## Change made

Run both paths over both corpora with `ML/host_scale_test/`, no device involved:

- Corpus A: `.pig_pictures/` field photographs.
- Corpus B: `Instaham/PIGRGB-Weight/sub_1.88/`, 960x540 PNGs at
  `cm_per_px_actual = 0.3289473684210526`.

Arms:

1. `canvas_scale` — the shipped path, `input_cm_per_px = 1.1` with the ladder. The baseline.
2. `normalize_first` — phase 1's path on a 960x540 canvas.
3. `normalize_first` with the enlarged canvas, for any capture that triggers the F61 oversize
   fallback, so the frame-geometry-parity claim is separated from the scale-normalization claim.

Record per image, per arm:

- whether a pig was detected at all, and at which ladder rung;
- `selected_box_frame_fraction`, `mask_diagonal_fraction`, `selected_mask_area_proto` and the
  runner-up area, so a near-tie selection is visible;
- predicted weight, signed error against ground truth, and corpus MAE;
- re-mark jitter, using the recorded marks in `logs/recorded.md` the way
  [`fix-phase-3/3.1-host-remark-replay.md`](../fix-phase-3/3.1-host-remark-replay.md) did;
- for corpus A, detection outcome split by capture orientation, which is the only measurement
  this round takes of README §4's head-at-top assumption.

Write the results into a durable document under `docs/` as each run completes, not at the end.

## Verification

The phase is done when the table exists and a verdict is written with its numbers. Read the
result against three reference points that already exist, so the verdict is not scored against
zero:

- the `k = 1.0` arm's 5.42% MAE and +5.35% bias on corpus B
  ([`scale-constant-sweep-results-2.md`](../scale-constant-sweep-results-2.md)), which bounds
  how good any framing change can make corpus B look;
- corpus A's 5.18-12.55% hand-marking jitter band
  ([`fix-phase-2/2.1-reference-length-sensitivity.md`](../fix-phase-2/2.1-reference-length-sensitivity.md)),
  which is wide enough to swallow a small MAE difference;
- round 7's post-rewire worst-case jitter, 10.3% native and 10.9% at 1280.

Verdict rules, decided now so the result is not read favourably after the fact:

- **Adopt** if the new path detects at least as often as the baseline on every image and
  improves corpus A MAE by more than corpus A's jitter band, or fixes a detection failure the
  baseline has.
- **Reject** if it detects less often anywhere, or if MAE moves inside the jitter band in either
  direction.
- **Inconclusive** is a real outcome: if detection is unchanged and MAE moves inside the band,
  say so and take the decision to the user rather than adopting on a tie. This is the case the
  parent document flags as the plan's weakest point.

Ground-truth weights below roughly 73-74 kg are outside the regressor's domain (ADR-010) and
must not be cited as evidence in either direction.

## Deferred

No device run, no Firebase Test Lab run, no APK. Phase 4 owns on-device confirmation, and the
Test Lab quota is not spent on this round without an explicit instruction.
