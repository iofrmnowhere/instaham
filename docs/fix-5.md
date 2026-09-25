# Fix (round 9): the view gate's verdict is cached per scan and reused for different photos

Fifth active fix document, opened as **round 9** on 2026-09-22. Unrelated to
[`fix-4.md`](fix-4.md)'s normalize-first scaling work (round 8), which stays open on its own
device-sideload step; this document is not a phase of that round and must not be worked as one.

Finding numbering continues at **F66** (F65 was the last assigned, in round 8's
capture-orientation phase).

## Symptom

Observed by the user on a sideloaded device build, 2026-09-22:

- Feeding a photo that the app had just rejected, then feeding a different, known-good photo in
  the same capture screen, produced the **same rejection** — the new photo was never assessed.
- After force-quitting and reopening the app, the same photo was **accepted**.
- Once a session had accepted one photo, subsequent photos were accepted too, **including
  non-dorsal views** ("it accepts even non dorsal view").
- The behaviour reads as random from the user's seat: the same image yields different verdicts
  across app launches, and different images yield the same verdict within one launch.

## Root cause

**F66 — `resolveViewGate` caches by scan, not by image, and the scan never rotates.** Two
independent facts combine:

1. `_sessionId` in `capture_screen.dart` is assigned exactly once — at
   `didChangeDependencies` from `widget.initialArgs?.sessionId`, or by `_createSession()` when
   that is null (lines 40, 135, 162, 166) — and **nothing ever clears it**. Not a retake, not a
   rejection (the reject path calls `setState(() => _reviewingPhoto = false)` and returns), not
   picking a different photo from the gallery.
2. `resolveViewGate` (`run_and_persist_pipeline_use_case.dart:357-370`) looks up
   `pipeline_events` by `scanId` and `stage == 'view'` **only**. It never consults the image
   path. When a row exists it returns that stored label and confidence and **does not run the
   model**.

So the first photograph fed in a capture-screen session decides the verdict for every
photograph after it in that session. The failure is symmetric: a `reject` sticks to good
photos, and a `dorsal_valid` sticks to photos that are not dorsal at all. `markCaptured`
overwrites the scan row's `imagePath` each time, so after the second photo the scan row and the
cached view event describe **different images**, with nothing recording the disagreement.

Force-quitting appears to fix it because the `CaptureScreen` widget is destroyed and a fresh
launch creates a new draft scan with no cached event.

**Not affected:** the first photo after a cold start, which creates a new draft scan and is
genuinely classified. **Affected immediately:** re-entering an existing scan through
`initialArgs.sessionId`, where a verdict is already stored before the screen ever opens.

**Partial downstream mitigation, not a fix.** `execute()` compares the native pipeline's own
`view` envelope block against the cached decision and degrades to the failure path on
disagreement rather than re-routing (`run_and_persist_pipeline_use_case.dart:111-115`), so a
mis-accepted photo is unlikely to publish a weight. The routing damage — skipping or forcing
reference marking, and the rejection dialog — has already happened at capture time.

## Secondary finding

**F67 — the view classifier is unreliable on landscape input (host-measured).** Measured
2026-09-22 by running `assets/ml/view/model.onnx` directly over corpus A with the manifest's
declared preprocessing (resize shorter side to 255, centre crop 224, ImageNet normalisation).
These are **host observations, not device behaviour**:

| image | portrait | landscape CW | landscape CCW |
|---|---|---|---|
| 118kg | `dorsal_valid` 1.00 | **`reject` 0.46** | `health_only` 0.61 |
| 75kg | `dorsal_valid` 1.00 | `health_only` 0.56 | `health_only` 0.85 |
| 92kg | `dorsal_valid` 1.00 | `dorsal_valid` 1.00 | `dorsal_valid` 0.71 |
| 96kg | `dorsal_valid` 0.98 | `dorsal_valid` 0.91 | `dorsal_valid` 0.55 |

Portrait is decisive on all four (≥0.98). Landscape is not: two of four images lose
`dorsal_valid` entirely, and the same photograph flips verdict between the two rotation
directions. The centre crop is not the mechanism — the crops were inspected and the pig is
fully visible in both orientations. The model appears simply not to have been trained on
landscape-oriented dorsal frames. This bears directly on round 8 phase 6's landscape half
(portrait head-up / landscape head-right): the orientation rule assumes a landscape capture can
reach the segmenter at all, and on this evidence it often cannot.

F67 is recorded here, not fixed here. It needs training data, not a code change, and it is a
decision for the user rather than a defect to patch.

**The user supplied their answer on 2026-09-22: let the user override a rejection.** On a
`reject` verdict the app offers Retake or "Analyze anyway", and the second choice runs the full
analysis on that photograph whatever the outcome. That is planned as
[phase 2](fix-phase-5/2-view-reject-override.md). It is an escape hatch over the model gap, not
a fix for it — F67's underlying cause (a view model that was not trained on landscape dorsal
frames) is unchanged and stays open.

## Change made

Nothing yet — this document is a plan.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Key the cached view verdict to the image it classified | done — device-confirmed 2026-09-22 | [fix-phase-5/1-view-verdict-cache.md](fix-phase-5/1-view-verdict-cache.md) |
| 1.1 | `resolveViewGate`'s latest-event selection must break ties on `id`, not `createdAt` | done | [fix-phase-5/1.1-latest-view-event-tiebreak.md](fix-phase-5/1.1-latest-view-event-tiebreak.md) |
| 2 | User override of a view-gate rejection ("Analyze anyway") | device-verified 2026-09-22 (Retake, Analyze anyway, no-leak all confirmed); native ctest fixture and widget test owed | [fix-phase-5/2-view-reject-override.md](fix-phase-5/2-view-reject-override.md) |

## Verification

The round closes when feeding a sequence of different photographs through one capture-screen
session produces one classification per photograph, each matching what the model returns for
that image on its own, and when a scan re-entered through `initialArgs.sessionId` re-classifies
rather than inheriting a verdict for an image it no longer points at.

## Open flags

- **Device-side view and landscape evidence gathered before this fix is contaminated.** Any
  verdict collected as the second or later photo of a capture-screen session may be the
  previous photo's answer. The round 8 landscape investigation that surfaced this defect falls
  in that category and must still be redone before any of its device conclusions are cited.
  The host numbers in F67 above are unaffected — they never went through the app.
  **Update 2026-09-22:** phase 1 is device-confirmed, so the redo no longer needs the
  one-photograph-per-app-launch discipline — multi-photo sessions now classify each photograph
  on its own.
- **F67's landscape unreliability is unresolved** and is the larger product question. Round 8
  phase 6 shipped a landscape capture rule the view model may not support. The user's answer
  (2026-09-22) is phase 2's user override, which makes a rejected photo analyzable but does not
  make the classifier right; whether to gather landscape training data or restrict the capture
  rule is still open and still theirs.
- **The app cannot currently tell a user which photo a verdict belongs to.** The `view`
  pipeline event stores only label and confidence (`recordViewGate`,
  `run_and_persist_pipeline_use_case.dart:379-390`). Phase 1's preferred fix adds the image
  identity, which also closes this reporting gap.

## Plan rating: 8/10

**Pros.** The defect is fully characterised from source before any code is touched — both
contributing lines are identified, the symmetry of the failure is explained, and the two
unaffected paths (cold start, first photo) are stated so the fix can be verified against real
behaviour rather than a guess. Scoping it as its own round rather than appending it to
`fix-4.md` keeps round 8's scaling work auditable, per AGENTS.md's rule against combining
unrelated work. Recording the evidence contamination protects the next session from citing
device numbers that were never valid.

**Cons.** The fix itself is small and well understood, so a single-phase round is arguably
heavier process than the change needs. F67 is recorded but unowned — it is the more consequential
finding of the two and this document can only flag it, which risks it being read as handled
because it is written down. The host measurements behind F67 come from four images in one
corpus, which is enough to show instability but not enough to characterise it.
