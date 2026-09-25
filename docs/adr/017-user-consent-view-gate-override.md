# ADR-017: The view-suitability gate is overridable by explicit per-photograph user consent

Status: Partly superseded by [ADR-020](020-view-route-override-either-route.md)

## Context

The view classifier (`view_v2`, MobileNetV4-Conv-Small — [ADR-006](006-view-classifier-swapped-to-mobilenetv4.md))
decides the route for every capture: `dorsal_valid` runs the full graph, `health_only` runs
health alone, `reject` stops the pipeline before any branch executes.

Round 9 measured that classifier on landscape input and recorded the result as **F67** in
`docs/fix-5.md`. Running `assets/ml/view/model.onnx` directly over corpus A with the
manifest's declared preprocessing, portrait captures were decisive on all four images
(`dorsal_valid` at ≥0.98), while landscape captures were not: two of four lost `dorsal_valid`
entirely, one landed on `reject` at 0.46, and the same photograph flipped verdict between
clockwise and counter-clockwise rotation. The centre crop was inspected and is not the
mechanism — the pig is fully visible in both orientations. The model appears simply not to
have been trained on landscape-oriented dorsal frames.

This collides with two standing commitments. Landscape capture is a required capability, and
round 8 phase 6 shipped a landscape capture rule ([ADR-014](014-capture-orientation-contract.md))
that assumes a landscape capture can reach the segmenter at all. On this evidence it often
cannot. Before this decision the rejection dialog offered exactly one action, `Retake`, so a
correct landscape photograph the model disliked was a dead end: retaking it in the same
orientation reproduces the same verdict.

Fixing the classifier needs landscape training data. That is a data-collection question with
no timeline, and it does not help a user holding a usable photograph today.

## Decision

On a `reject` verdict the app offers two actions: **Retake**, which behaves exactly as before,
and **Analyze anyway**, which runs the full analysis on that photograph and shows whatever
result comes out.

The override is bounded deliberately:

- **Per photograph, never per session or per scan.** Consent is recorded as a
  `view_override` `PipelineEvent` keyed to the sha256 of the image's bytes — the same
  content-hash mechanism [phase 1](../fix-phase-5/1-view-verdict-cache.md) introduced for the
  cached verdict itself (F66). A scan-scoped override would leak onto every later photograph
  in the same capture-screen session, because `_sessionId` is reused across retakes. A
  missing identity is a mismatch, never a wildcard.
- **Routing changes; the verdict does not.** The stored label stays `reject` everywhere — in
  the database, in the envelope, and on the results screen's view card. The envelope's `view`
  block gains `"override": true` so no later reader can mistake the run for a clean
  `dorsal_valid` one.
- **An overridden `reject` is routed as `dorsal_valid`.** The user is overriding the
  classifier's opinion that this is not a dorsal photograph, and the only useful thing to do
  with that override is run the branches a dorsal photograph gets. A `reject` label is neither
  `is_dorsal` nor `is_health_only`, so without this it would fall into the `view_unresolved`
  block that skips every stage — an "analysis" computing nothing.
- **Only the view gate is bypassed.** The truncation gate, the posture gate, the
  reference-scale checks, and the feature-domain gate all still run and can still decline to
  produce a number.
- **The result is labelled.** The results screen carries a banner stating the photo failed the
  view check and was analyzed at the user's request, so an overridden result is never
  presented as indistinguishable from a normal one.

Mechanically this rides the existing request-shaped FFI entrypoint as an optional
`view_gate_override` boolean; no exported symbol changes signature. See
[../ffi-bridge.md](../ffi-bridge.md).

## Consequences

**Accepted tension with AGENTS.md rules 3 and 8.** Rule 3 requires all eligibility checks to
pass before weight estimation; rule 8 forbids forcing a prediction after a failed quality or
eligibility check. The narrowing this ADR adopts is that explicit, per-photograph, recorded
user consent *replaces the view classifier's verdict as the eligibility input for that one
photograph* — it does not weaken any other check, and it cannot be given once and reused. This
is the paragraph to re-read if the behaviour is ever questioned.

**F67 is not closed by this.** The classifier's landscape unreliability is unchanged. This is
an escape hatch layered over a model gap, and treating it as a fix would be wrong: whether to
gather landscape training data or restrict the capture rule remains open.

**An overridden analysis may still fail one stage later.** Nothing is known about how the
segmenter behaves on the photographs this classifier rejects, so the override buys the user an
attempt, not a result. That is the honest contract and the dialog says so.

**Overridden results are not currently held out of history or trends.** They are labelled but
not excluded or aggregated differently. If they should be, that is a separate decision.

**Verification.** Host: four Dart tests pin that the override applies to its own image, not to
a different one in the same scan, and that a `view_override` event never satisfies the
`view`-stage verdict cache. Device (2026-09-22): Retake, Analyze anyway, and the no-leak check
— a second rejected photograph re-asks rather than inheriting the earlier choice — all
confirmed on a sideloaded build. A native `ctest` fixture exercising the flag through real ORT
runners is still owed.
