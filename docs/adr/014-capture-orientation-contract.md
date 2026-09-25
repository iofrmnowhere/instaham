# ADR-014: Enforce capture head-direction by instruction and attestation, not detection

Status: Accepted

Context: README §4 assumes a portrait capture already has the pig's head at the top and forbids
inferring head direction dynamically at preprocessing time — segmentation must not learn about
head direction. Nothing in the app made that assumption true (F65): a portrait capture with the
head at the bottom was rotated 90° clockwise like any other and reached the segmenter head-left,
mirrored relative to every frame the model trained on, with no error and no signal in the
envelope. The README is silent on landscape's head direction; it says only "do not rotate"
there. Round 8's normalize-first order (ADR-013) rotates portrait captures 90° clockwise before
the segmenter runs, which turns a head-up portrait and a head-right landscape into the same
downstream fact — the pig reaches the segmenter head-right — so one capture-time rule covers both
orientations.

Decision: Constrain the capture instead of detecting the violation afterward. This is a
Flutter/Dart and UI change with no native counterpart:

- **Portrait captures require the pig's head facing up; landscape captures require the pig's
  head facing right.** The landscape half is this project's addition to the README, not a
  quotation from it.
- The rule is stated in the existing tips list (`capture_guidance_screen.dart`), shown live
  during capture via an orientation-aware prompt driven by
  `CameraController.value.deviceOrientation` (not `MediaQuery`, which can disagree with rotation
  lock), and gated by an un-pre-ticked confirm checkbox on the review screen before "Verify
  reference" is enabled.
- The confirmation is an **attestation**, not a verification — no head detector exists, and §4
  forbids adding dynamic inference at this stage. The app records that the user attested to the
  rule, not that it confirmed the rule holds.
- The captured orientation (`CaptureOrientation.fromDimensions`, matching README §4's own
  `normalizedHeight > normalizedWidth` test) and the attestation are persisted on the scan record
  (`ScanRecords.captureOrientation`/`.headOrientationAttested`, schemaVersion 4 → 5) so a
  wrong-looking mask can later be checked against what the user declared.

Decided against: an automatic head-direction detector. Out of scope for this round by the
README's own §4 restriction and the user's instruction; would need its own plan if ever wanted.

Consequences: Enforcement is social, not mechanical — a user who ignores or misreads the prompt
can still submit a mirrored capture, and the pipeline has no way to catch that at inference time.
The attestation field exists precisely so a future session can correlate a wrong prediction with
a declared orientation after the fact, not so the app can refuse a bad capture up front. There is
no widget-level test driving the confirm-step gating or the live-prompt banner directly — this
repo has no harness for mocking the `camera` plugin's platform channel, and building one was
judged out of this round's scope; the underlying `CaptureOrientation` logic the widgets wrap is
unit-tested instead
([`fix-phase-4/6-capture-orientation.md`](../fix-phase-4/6-capture-orientation.md)). The existing
host corpora were captured before this rule existed and were not re-captured to satisfy it; they
remain historical evidence, not a gate on this decision.
