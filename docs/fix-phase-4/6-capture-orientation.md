# Phase 6 — Enforce capture orientation (portrait head-up, landscape head-right)

Status: not started

Parent: [`../fix-4.md`](../fix-4.md). Opened 2026-09-19 from the user's instruction. Closes F65.

The rule, as given:

- **Portrait captures require the pig's head facing up.**
- **Landscape captures require the pig's head facing right.**

## Symptom

README §4 assumes a portrait capture has the pig's head at the top and forbids inferring head
direction during preprocessing. Nothing in the app makes that assumption true. A portrait
capture with the head at the bottom is rotated 90° clockwise like any other and reaches the
segmenter head-left, mirrored relative to every frame the model was trained on, with no
error and no signal in the envelope.

## Root cause

F65, stated in the parent document. The README closed the inference route without opening a
substitute; the user's instruction supplies it. Constrain the capture so the assumption holds,
rather than detect the violation afterwards.

Why both halves are needed, and why they agree: portrait rotates 90° clockwise per §4, so
head-up becomes head-right. Landscape does not rotate, so it must already be head-right. Both
rules therefore state the same downstream fact — **the pig reaches the segmenter head-right** —
and the pipeline gets one orientation instead of four. The landscape half is an addition to the
README, which says only "do not rotate" for landscape and is silent on head direction; record
it as this project's rule, not as a README quotation.

## Change made

This is Dart and UI work. No native change, and nothing in `stages/segmentation.cpp` learns
about head direction — §4's ban on dynamic inference at preprocessing time still holds.

1. **State the rule where the user reads it.** Add both sentences to the tips list in
   `capture_guidance_screen.dart:15-21`, phrased for the orientation the phone is actually in
   rather than as a conditional the user has to evaluate. This list is the existing contract
   surface; do not build a second one.

2. **Show it during capture, not only before it.** In `capture_screen.dart`, display an
   orientation-aware prompt driven by the live sensor orientation: portrait shows the head-up
   instruction, landscape shows the head-right instruction. Use the orientation the capture will
   actually be written with, not `MediaQuery` alone — these can disagree with rotation lock on.

3. **Require an explicit confirmation before the photograph is accepted.** The app cannot verify
   head direction; no head detector exists and §4 forbids adding one at preprocessing. So
   "forced" here means the user attests to it and the attestation is recorded — not that the app
   silently believes it. Add a confirm step after capture that names the rule for the captured
   orientation and cannot be dismissed by default action. Do not block on it silently and do not
   pre-tick it.

4. **Record the attestation and the capture orientation** with the capture, alongside the
   existing fields on `captured_image_entity.dart` / `captured_image_result.dart`, and carry
   both into the envelope so a wrong-looking mask can be checked against what the user declared.
   A schema change here needs a `schemaVersion` increment, an explicit migration, regenerated
   Drift output and a migration test — see AGENTS.md. If the attestation can live on the
   existing capture record without a schema change, prefer that.

5. **Do not reject a capture the app cannot check.** The rule is enforced by instruction and
   attestation. An automatic head-direction check is out of scope for this round and belongs in
   its own plan if it is ever wanted.

### Accessibility

Both prompts and the confirm control need semantic labels, readable contrast, scalable text and
a touch target of at least 44x44 logical pixels. The prompt must not be colour-only — a user who
cannot distinguish the state must still get the sentence.

## Verification

- `dart format` on the changed Dart files.
- `flutter analyze`.
- Targeted `flutter test` on the changed behaviour: the prompt text switches with orientation,
  the confirm step is required before the capture is accepted, and the attestation plus
  orientation reach the capture record.
- If a schema change proves necessary: `dart run build_runner build --delete-conflicting-outputs`
  and a migration test for the version step.
- Report the exact commands run and any that could not run.

## Deferred

Automatic head-direction detection. Any change to the native rotation rule — §4's
`normalizedHeight > normalizedWidth` test is unchanged by this phase. Re-capturing the existing
host corpora to satisfy the new rule: the corpora are fixed historical images, and phase 2's
recorded numbers were produced before this rule existed, which is one more reason they are
evidence rather than a gate.
