# Phase 1 — Key the cached view verdict to the image it classified

Status: done — implemented, host-verified, and device-confirmed 2026-09-22 (see Device
confirmation below)

Parent: [`../fix-5.md`](../fix-5.md) (round 9). Closes F66.

## Symptom

Within one capture-screen session, every photograph after the first inherits the first one's
view verdict without being classified. A rejection sticks to good photographs; a `dorsal_valid`
sticks to photographs that are not dorsal. See the parent document for the user's device
observations.

## Root cause

F66, stated in full in the parent. In short: `resolveViewGate`
(`run_and_persist_pipeline_use_case.dart:357-370`) selects the newest `pipeline_events` row
with `scanId == <scan>` and `stage == 'view'` and returns its label and confidence without
consulting the image path, while `capture_screen.dart` reuses one `_sessionId` for every
photograph the screen handles (assigned at lines 135/162, never cleared).

The cache itself is wanted — it exists so analysis does not re-run the view model that capture
already ran (see the file header's note on TASKS.md P0). The defect is that its key is the scan
rather than the image, and the scan's image is mutable.

## Change made

1. **Record which image a view verdict describes.** `recordViewGate`
   (`run_and_persist_pipeline_use_case.dart:379-390`) currently writes only the label
   (`status`) and the confidence (`message`). Extend the persisted event so the classified
   image is identifiable. Prefer a content hash over the file path: `processCapture` writes
   `instaham_cap_<timestamp>.jpg`, so paths are unique per capture, but a path match would
   still wrongly hit if a file were ever replaced in place, and a hash also survives the temp
   directory being relocated. If the `PipelineEvents` table has no suitable column, a schema
   change here needs a `schemaVersion` increment, an explicit migration, regenerated Drift
   output and a migration test — see AGENTS.md. Check whether an existing free-form column can
   carry it before adding one.

2. **Make `resolveViewGate` reuse a verdict only for the image it belongs to.** It takes
   `imagePath` already. Compare the stored identity against the image being resolved; on a
   mismatch, ignore the stored row, run the model, and record the new verdict. On a match,
   return the stored verdict exactly as today. A scan whose stored event predates this change
   and carries no image identity must re-classify rather than being trusted — treat a missing
   identity as a mismatch, not as a wildcard.

3. **Do not fix this by clearing the event in `markCaptured`.** That was the other candidate
   and it is weaker: it makes the cache less wrong rather than correct, it leaves the analysis
   path (`execute()`) still able to read a verdict it cannot attribute, and it silently drops
   information instead of keeping it checkable. Keying the cache is the change; if
   `markCaptured` should also clear a now-stale event, that is a tidiness follow-on, not the
   fix.

4. **Leave `_sessionId`'s lifetime alone.** Reusing one draft scan across retakes within a
   screen is deliberate — it is what lets a user retake without littering the records list with
   abandoned scans. Once the cache is keyed correctly, the reuse is harmless. Do not change
   both at once; if the session lifetime turns out to need changing too, that is a separate
   finding with its own reasoning.

## Verification

- `dart format` on changed Dart files, `flutter analyze`, and targeted `flutter test`.
- A unit test proving the core behaviour: given a stored view event for image A, resolving the
  same scan against image B runs the model and records B's verdict rather than returning A's.
  Include the inverse — resolving against image A again returns the stored verdict without a
  model call — so the test pins the caching that is meant to survive.
- A test covering the legacy row: a stored event with no image identity must re-classify.
- If a schema change proves necessary: `dart run build_runner build
  --delete-conflicting-outputs` and a migration test for the version step.
- **On device, one photograph per app launch is no longer required after this lands** — that
  workaround exists only because of this defect. Confirm directly: in a single session, feed a
  photograph the model rejects, then a photograph it accepts, and check that the second is
  accepted. Then the reverse order. Record both results.
- Report the exact commands run and anything that could not run.

## Deferred

- **F67, the view classifier's unreliability on landscape input.** Recorded in the parent with
  host measurements. It is a training-data question, not a code defect, and it is not in this
  phase's scope.
- **Re-running the contaminated device evidence.** The round 8 landscape results collected
  before this fix cannot be trusted. Redoing them is the user's device work and should happen
  after this phase lands, at which point the one-photo-per-launch discipline is no longer
  needed.
- **Surfacing the view verdict's image in the UI.** Once the identity is persisted, the results
  screen could show which photograph a verdict describes. Useful, not required here.

## Result (2026-09-22)

**All four numbered change points are in place**, plus one correctness fix the tests surfaced
that the plan did not anticipate.

- **`PipelineEvents.imageIdentity`** (`app_database.dart`): a nullable `TEXT` column holding the
  sha256 of the classified image's bytes. No existing free-form column was reusable — `message`
  already carries the confidence string — so this is a real schema change: schemaVersion 5 → 6,
  migration step `from < 6` (nullable addition, no backfill), Drift output regenerated.
- **`RunAndPersistPipelineUseCase.imageIdentityOf`**: new helper, sha256 of `File(imagePath)`'s
  bytes (`package:crypto`, already a dependency — `ml_runtime.dart` uses the same pattern for a
  different check).
- **`resolveViewGate`**: now computes the current image's identity and compares it against the
  latest stored `view` event's `imageIdentity` before trusting it. A mismatch — including a
  stored row with no identity at all — falls through to `viewModelService.classify()` exactly
  as the "no stored event" path already did, and records the fresh verdict keyed to the new
  identity.
- **`recordViewGate`**: gained an optional `imageIdentity` parameter, threaded through from
  `resolveViewGate`; callers that don't pass one (matching a legacy row) store `null`.
- **`_sessionId` reuse untouched**, per the plan's fourth point.
- **A tiebreak defect surfaced mid-phase, written up as
  [phase 1.1](1.1-latest-view-event-tiebreak.md)** rather than fixed inline unflagged: the
  "latest" `view` event selection ordered by `createdAt`, which two events in the same
  wall-clock second (a fast retake) can tie on. See that file for the root cause and why it
  was applied together with phase 1 instead of deferred.
- **Existing tests using a nonexistent `/fake/image.jpg` path** (`reference_scale_forwarding_test.dart`,
  `weight_domain_failure_test.dart`) now back that path with a real temporary file, since
  `resolveViewGate` must read the image to hash it even on what used to be a no-I/O cache hit.
  Both files' pre-seeded `recordViewGate` calls now pass the matching `imageIdentity` so the
  cache hit they were written to exercise still occurs.

**Verification run:**
- `dart format` on all changed/added Dart files — clean.
- `flutter analyze` on all changed/added Dart files — no issues.
- `flutter test` targeted (`test/core/database/app_database_test.dart`,
  `test/features/inference_pipeline/view_verdict_cache_test.dart` (new),
  `test/features/inference_pipeline/reference_scale_forwarding_test.dart`,
  `test/features/inference_pipeline/weight_domain_failure_test.dart`) — 21 passed.
- Full suite (`flutter test`) run because this is a schema change — 115 passed, 39 skipped (all
  pre-existing skips: native-harness Tier B gate, unimplemented §14 fixtures; none new).
- `dart run build_runner build` — regenerated cleanly, 88 outputs.
- **Not run: the on-device confirmation** (Verification's last bullet — reject-then-accept and
  accept-then-reject in one session). That is the user's device work and is still owed; it is
  what closes F66 and unblocks redoing round 8's device comparison.

**Files changed:** `lib/core/database/app_database.dart` (+ generated `.g.dart`),
`lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`,
`test/core/database/app_database_test.dart`,
`test/features/inference_pipeline/reference_scale_forwarding_test.dart`,
`test/features/inference_pipeline/weight_domain_failure_test.dart`; new:
`test/features/inference_pipeline/view_verdict_cache_test.dart`.

## Device confirmation (2026-09-22)

Run by the user on a sideloaded build, reported in session. **Observed, not predicted:**

- With the reference-object pixel length held the same across the comparison, a landscape
  capture was **rejected**; the same photograph in portrait was then **accepted** within the
  same session — the second photograph got its own classification instead of inheriting the
  first's rejection.
- The accepted capture produced a **different weight** from the preceding one, which is the
  positive evidence that the second photograph was genuinely re-run rather than re-served from
  the first's stored result.
- **The reverse order was also checked** and behaved the same way.

This is the Verification bullet that required "one photograph per app launch" to be retired.
That workaround is no longer needed: multi-photograph capture-screen sessions now classify each
photograph on its own, so device evidence collected from here on is valid without it.

Not covered by this run, and still true: the round 8 landscape evidence collected **before**
this fix remains contaminated and must be redone — see the parent document's Open flags.
