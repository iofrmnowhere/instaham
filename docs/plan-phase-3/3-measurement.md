# Phase 3 — measure the three protocols on real captures

Status: done

## Goal

Find out what masking actually does to this checkpoint's predictions, on this project's own
photographs, before any default changes. This phase produces a number and a recommendation, not
a code change.

## Design/Approach

The question is not "does the crop look better" but "does the prediction get more trustworthy".
Those come apart, and only the second justifies flipping the manifest.

### What to run

For every available capture, run the health classifier three times — `full_frame`,
`segmentation_crop`, `segmentation_masked` — over the same decoded image and the same mask, and
record the full probability vector each time, not only the argmax. The pipeline already emits
the vector under `health.probabilities`.

Run this on the host, not on a phone. `ML/host_scale_test/` is the established pattern for
host-side replication using the real shipped C++ stages and the real models; the gate CLI from
phase 2 is most of what this needs already. Do not write a Python reimplementation of the
inference path for this — the whole point is to measure the shipped code.

### What to report

Per capture, per protocol: predicted label, confidence, and `P(Healthy)`. Then across the
corpus:

- **Agreement with ground truth**, where ground truth exists. This is the only measure that can
  justify a flip.
- **How often the label changes** between protocols. A large change rate with no accuracy
  signal means the input is being moved without being improved.
- **The healthy-pig case specifically.** `health_input.h` records `P(disease) = 0.937` on a
  visibly healthy pig under full frame. Whether the masked protocols move that is the single
  most informative data point available, and it should be called out on its own.

### The honest failure mode

If the label changes often and agreement does not improve, the correct conclusion is that the
checkpoint needs fine-tuning on masked crops and that phase 4 should not be taken. Write that
down as the result rather than flipping the default on the strength of a nicer-looking crop.
Equally, a result measured on a handful of captures is a weak result and must be labelled as
one — record the corpus size next to every figure.

## Steps

- [x] Decide and record the corpus: which captures, how many, and which have ground-truth
      labels. State plainly how many do not.
- [x] Extend the phase 2 CLI (or add a sibling) to run inference and emit the probability
      vector per protocol.
- [x] Run all three protocols over the corpus; write raw per-capture rows to `docs/logs/`, not
      into this file.
- [x] Summarise here: agreement, label-change rate, and the healthy-pig case.
- [x] State a recommendation for phase 4 — flip, do not flip, or flip only
      `segmentation_crop` — with the evidence it rests on.

## Result

Full raw output: `docs/logs/phase3-health-protocol-measurement.md`. New CLI:
`packages/instaham_ml_ffi/src/test/health_protocol_measure_cli.cpp`, which runs the actual
shipped `run_segmentation` -> `construct_pig_mask` -> `pig_region_from_base_mask()` ->
`run_classifier()` chain (the same code `pipeline.cpp` calls) three times per image, once per
protocol, and prints the full probability vector each time.

**Corpus: n=3.** The three `valid_dorsal` scenario fixtures phase 2's parity gate already
used, each a real `.pig_pictures/` photo with a real user-marked `cm_per_px`. This is the
entire set of real captures in this repository that both (a) is a genuine field photo and
(b) has a recorded reference scale, which segmentation requires (AGENTS.md rule 7: no
fabricated cm/pixel). **None of the three carries a disease label** — all three are healthy
pigs recorded for weight measurement. Per open question 1: ground truth is not "almost none",
it is **none**, for this corpus. Accuracy cannot be reported; only the label-change rate and
the healthy-pig case can be, exactly as the open question anticipated.

**Label-change rate: 3/3 (100%).** Every image that was `Healthy` under `full_frame` changed
label under both region protocols. `P(Healthy)` collapsed from 0.68-0.97 (full frame) to
0.002-0.010 (segmentation_crop) and 0.002-0.005 (segmentation_masked) — not a narrow miss, a
near-total collapse of the correct class's probability mass.

**The healthy-pig case.** `health_input.h`'s motivating number, `P(disease) = 0.937` on a
visibly healthy pig under full frame, is not one of these three fixtures (that number predates
this measurement and its source image is not identified in this repo), but this measurement
reproduces the same failure mode on fresh evidence: full frame already gets closer to right
than either region protocol makes it. Full frame's own worst case here (image 01, P(Healthy)
0.68) is still the correct label; every region-protocol result across all three images is
wrong, and confidently so (0.52-0.99).

**Direction, not just magnitude.** This is not simply "the crop moves the prediction" — the
crop moves it in the wrong direction on this corpus, three times out of three, which is the
opposite of what section "Why this is worth doing" in `plan-3.md` hypothesised (that removing
background would move captures toward the close-up training distribution).

## Recommendation for phase 4: do not flip

Per this phase's own "honest failure mode" clause: the label changes often (always, on this
corpus) and agreement does not improve (it gets worse, from 3/3 correct to 0/3 correct) — the
correct conclusion is that the checkpoint would need fine-tuning on masked/cropped inputs
before either region protocol is trustworthy, and that is a training job outside this plan's
scope. Phase 4 (flip the default, update fixtures) should **not be taken** on the strength of
this evidence. The manifest should keep `protocol: "full_frame"`.

The code from phases 1-2.1 is not wasted: it is now measured and rejected with a specific,
reproducible reason, rather than left an untested hypothesis. Shipping it inert (built,
tested, not defaulted-to) keeps the option open if the checkpoint is later retrained on masked
inputs, without exposing users to the regression measured here.

**This is a weak result and is labelled as one.** n=3, all healthy, no disease-positive
capture in the corpus. A checkpoint this confident in the wrong direction on 3/3 healthy
photos would need a much larger and more balanced corpus to fully characterize, but the
direction and the size of the effect (confidence 0.5-0.99 on the wrong class, `P(Healthy)`
under 0.01 in five of six region-protocol runs) are strong enough on their own that no result
on a larger corpus is likely to reverse a "do not flip" recommendation to a "flip" one — only
a fine-tuned checkpoint would.

## Verification

Every figure above is transcribed from `docs/logs/phase3-health-protocol-measurement.md`,
which is the CLI's raw JSON output, unedited except for formatting into tables. No predicted
or expected value is reported here as though observed. Host build only, per open question 2's
own reasoning: the crop is a resample, not a new model pass, and no Firebase Test Lab run was
proposed or run for this phase.

## Open questions

1. **Resolved.** Ground truth for this corpus is none, not "almost none" — see Result above.
2. **Resolved.** Device measurement was not needed; this phase used the host build only.
