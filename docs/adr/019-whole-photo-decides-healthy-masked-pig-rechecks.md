# ADR-019: The whole photo decides "healthy"; the masked pig only re-checks other labels

Status: Accepted

## Context

The health classifier (GhostNetV3-100, 10 classes) shipped running on the whole photo
(`full_frame`). A visibly healthy pig once came back with P(disease) = 0.937 on the whole
photo. That raised the question of whether isolating the pig would give a better reading.

`docs/plan-3.md` implemented two ways to isolate it: `segmentation_crop` (the pig's padded
box) and `segmentation_masked` (the same box with everything outside the pig mask filled
with the ImageNet mean). It then measured both against the whole photo
(`docs/logs/phase3-health-protocol-measurement.md`). On all three healthy fixtures, the
masked input on its own gave a disease label with P(Healthy) below 0.01. The whole photo
called all three `Healthy`. The mask overlays were checked by eye and do line up with the
pig, so a bad mask does not explain the result.

The user's reading, recorded 2026-09-24: the health model was trained on close-up
condition photos that still contain their natural background. A `Healthy` result from the
whole photo is therefore in distribution and can be trusted. A masked silhouette on a flat
grey background is not what the model was trained on.

So neither input is good enough on its own. The whole photo is the right judge of "healthy
or not". Only the isolated pig removes background that might be driving a particular
disease label.

## Decision

**Run the health classifier in two stages, controlled by the manifest
(`capabilities.health.cascade`).**

1. Classify the whole photo. If the label is the manifest's `healthy_label` (`Healthy`,
   looked up by name, never by index), that result is final.
2. Otherwise, if a region with a real mask exists, classify again with
   `second_stage_protocol` (`segmentation_masked`), and report that second result as final.
3. With no usable mask, or if the second pass fails or falls back to full frame, the first
   result stays final. The envelope's `cascade.second_stage` says which of these happened.

`segmentation_masked` is **not** made the default first-pass protocol, and neither is
`segmentation_crop`. Masking is only ever a second opinion on a label that was already not
healthy.

The logic lives in one function, `run_health_cascade()` in `src/classifier.cpp`. Both
`pipeline.cpp` and the host measurement CLI call it. Details are in
[../pipeline/health.md](../pipeline/health.md) and `docs/plan-4.md`.

## Consequences

- **Healthy results are unchanged.** A pig the whole photo calls `Healthy` never reaches the
  second pass. The three healthy host fixtures and the user's 2026-09-25 phone check both
  confirm this.
- **The second pass cannot clear a false alarm.** If the whole photo wrongly flags a healthy
  pig, the masked pass will almost certainly also call it diseased, and the result may look
  more certain than it is. The app therefore words the final label as a possible condition
  to re-check, never a confirmed diagnosis.
- **Whether the second pass names the right condition is unmeasured.** The repo has no
  labelled photo of a whole diseased pig. Every number behind this decision comes from three
  healthy pigs.
- **Only the `dorsal_valid` route can reach the second pass.** The `health_only` route never
  segments, so it has no mask and ends at `no_region`. `instaham_ml_classify_health_json`
  has no region either and stays single-pass.
- **A second pass costs about 30-40 ms** on the host (about 22 ms to decode the image again,
  about 10 ms to run inference). That only happens on non-healthy results.
- **Switching it off is a manifest change, not a rebuild.** With `cascade.enabled: false`
  the envelope is exactly the old single-pass output, with no `cascade` key. A bad cascade
  block disables the cascade instead of failing the manifest load.
- **Revisit this decision** if a health model is retrained on masked or cropped pigs, or if
  labelled whole-pig disease photos show the masked second pass naming conditions worse than
  the whole photo does.
