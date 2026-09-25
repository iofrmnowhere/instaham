# Plan (round 4): two-stage health cascade — closed 2026-09-25

## Goal

Run the health classifier in two stages:

1. Classify the whole photo (`full_frame`, today's shipped default).
2. If the result is `Healthy`, that is the final output. Nothing else runs.
3. If the result is any disease class, classify again on the pig alone, using the current
   mask + crop isolation (`segmentation_masked`), and report that second result as the final
   output.

Healthy results are identical to today's. The second pass exists only as a re-analysis of
results that were not healthy, and it runs only when the first pass asks for it.

## Why this shape

Round 3 (`docs/plan-3.md`) measured every way of isolating the pig against the whole photo and
found that isolation, used on its own, turned all three healthy pigs into a disease label
(`docs/logs/phase3-health-protocol-measurement.md`). The user's reading of that result, recorded
on 2026-09-24: the health model was trained on photos that include their background, so a
`Healthy` verdict from the whole photo is trustworthy and should stand without re-analysis. The
mask was checked visually against the pig (`docs/logs/phase3-mask-dumps/*/image_01_mask_overlay.bmp`)
and lines up, apart from the small expected excess at the edge, so the masked pass is ready to use.

The cascade therefore uses each input for the job it is suited to: the whole photo decides
healthy versus not healthy, and the isolated pig gives the second reading of which condition.

## Evidence the plan carries forward (must not be lost)

These limits come from round 3 and are the reason the UI wording in phase 3 is hedged:

- **The second pass cannot clear a false alarm.** On all three healthy pigs, the masked pass
  gave a disease label with P(Healthy) below 0.01. If the whole photo wrongly flags a healthy
  pig, the second pass will almost certainly agree that it is sick, so the result may look
  more certain than it is.
- **How well the second pass names the right disease has not been measured.** The repo has no
  labelled photo of a whole diseased pig. The one lesion fixture, `06_lesion_closeup`, is on
  the `health_only` route, which never produces a mask.
- **n = 3, all healthy.** Every number behind this design comes from three photos.

So the final result is a *possible* condition, never a confirmed diagnosis, and the app must
not describe the second pass as confirming anything (AGENTS.md: never display invented model
state).

## Design decisions taken up front

- **The manifest decides, not the code.** A new `capabilities.health.cascade` block turns the
  cascade on and names the healthy class and the second-stage protocol by name. With the block
  absent or disabled, behaviour is exactly today's single `full_frame` pass.
- **The healthy class is found by label, never by index** (AGENTS.md rule 1). The manifest names
  `"Healthy"`; at load time it is checked against the class map, and a name that is not in the
  map disables the cascade with a logged reason instead of crashing.
- **One implementation, called from both the app and the host tools.** The cascade lives in a
  single function next to `run_classifier()`, and `pipeline.cpp` and the host CLI call that same
  function. This is the lesson of round 3's subphase 2.1: tests must run the shipped code, not a
  copy of its logic.
- **The second pass never blocks or weakens the health result** (AGENTS.md rule 4). If there is
  no pig region (the `health_only` route, or segmentation failed), if the mask turns out empty
  so the masked input would fall back to full frame, or if the second inference errors, the
  first-stage result is the final output, and the envelope says why.
- **Everything is reported.** The envelope keeps the final label, confidence and probabilities
  where Dart already reads them, and adds a `cascade` object holding the first-stage result and
  which stage produced the final answer. No stage is ever claimed that did not run.
- **No database schema change.** The stage that produced the final answer is stored in the
  existing, currently unused `HealthResults.preprocessingVersion` column. If the user later
  wants the first-stage label persisted as well, that is a schema change and a separate decision.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Native cascade and manifest switch | done | docs/plan-phase-4/1-native-cascade.md |
| 2 | Host verification on real captures | done | docs/plan-phase-4/2-host-verification.md |
| 3 | Persist and show the stage in the app | done | docs/plan-phase-4/3-app-surfacing.md |
| 4 | Contract docs, fixtures and device check | done | docs/plan-phase-4/4-docs-fixtures-device.md |

Phases run in numerical order.

## Relationship to the other open documents

This is the **fifth** plan/fix document open at once: `plan.md` (Chen16 swap, phase 5
outstanding), `plan-2.md` (round 2, device check only), `fix-4.md` (round 8) and `fix-5.md`
(round 9). `plan-3.md` (round 3) is complete except for its closing changelog step, and this
plan replaces its open question about the cascade.

Round 4 touches only the health branch: `classifier.{h,cpp}`, `health_input.{h,cpp}`,
`manifest.{h,cpp}`, the health block of `pipeline.cpp`, the health CLI, and on the Dart side
the pipeline use case and the results screen's health card. It shares no file region with the
weight branch's open work.

## Open questions

1. **The second pass says `Healthy`.** Per the user's rule, the second pass's result is the
   final output, so a pig that the whole photo flagged and the isolated pig cleared is reported
   as `Healthy`. Round 3 suggests this will be rare (P(Healthy) under 0.01 on all three), but it
   is allowed and must be shown truthfully.
2. **Should the first-stage label be shown to the user?** The plan shows only the final label,
   plus a line saying the result was re-checked on the pig alone. Showing both labels ("whole
   photo: Sunburn, pig only: Ringworm") is more honest about disagreement but needs a UI decision.
3. **Decoding twice.** `run_classifier()` decodes the image from its path, so the second pass
   decodes it again. That only happens on non-healthy results; phase 1 measures the cost and
   only refactors if it is noticeable.
4. **Retraining.** If the model is ever retrained on masked images, round 3's measurement should
   be repeated, because the case for the cascade's current shape would change.

## Plan rating: 8/10

**Pros.** Healthy results do not change at all, and the cascade can be switched off from the
manifest, so the risk to today's behaviour is close to zero. Almost every piece already exists and
is tested: the masked protocol, the coordinate recovery, the parity gate and the measurement CLI
from round 3. Real verification is possible on the host because forcing the second stage on the
three real captures must reproduce round 3's recorded masked labels exactly, which checks that the
new code path wires the region correctly. No schema change, and the ABI does not move because the
new fields are additive JSON.

**Cons.** On the photos available today, the second stage never runs by itself (all three are
healthy and the lesion fixture has no mask), so its natural trigger is only exercised by forcing
it. How accurately the final label names a disease is unmeasured and stays unmeasured, because the
data to measure it does not exist. The second pass cannot overturn a whole-photo false alarm, so
the design adds cost on those scans without fixing them. It opens a fifth plan/fix document, against
a convention that wants one.

**Why not higher.** The payoff, better disease naming, cannot be shown with the data in the repo.

**Why not lower.** The change is small, reversible from the manifest, leaves the healthy path
untouched, and every phase has a concrete check that uses the shipped code.
