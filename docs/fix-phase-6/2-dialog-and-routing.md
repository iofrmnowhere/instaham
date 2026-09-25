# Phase 2 — three-option dialog and Dart routing

Status: done (2026-09-25), with one verification substitution (see Result)

Parent: [`../fix-6.md`](../fix-6.md) (round 10), findings F68 and F70. Needs phase 1.

## Symptom

The capture screen shows a two-button dialog on `reject` only, and a `health_only` verdict is
routed without asking (`capture_screen.dart:416-480`). Dart records an override as a yes/no
fact and sends a boolean to native.

## Root cause

See F68 in the parent. On the Dart side, `recordViewGateOverride` stores status `'override'`
with no route, `hasViewGateOverride` returns a `bool`, and `execute` only looks for an override
when the verdict is `reject`.

## Change made (planned)

1. **Dialog, for both `reject` and `health_only`.** One shared dialog builder in
   `capture_screen.dart`, returning a three-value choice (retake / health only / weight and
   health; a dismissal counts as retake, as it does today). Proposed wording:

   | Verdict | Title | Body |
   |---|---|---|
   | `reject` | Photo not recognized | This photo wasn't recognized as a clear pig photo. The check can be wrong, so you can choose how to continue. |
   | `health_only` | Weight may not be measurable | This photo looks right for a health check, but not for a weight estimate, which needs the pig's whole back seen from above. The check can be wrong, so you can choose how to continue. |

   Buttons, in this order: **Retake photo**, **Check health only**, **Check weight and
   health**. Three labels this long do not fit on one row on a small phone, so the actions are
   stacked full-width (each at least 44 px high), not left to `AlertDialog`'s overflow
   behaviour. Each button gets a semantic label.
2. **Routing after the dialog.**
   - Retake photo: as today for `reject` (status `rejected`, back to the camera). The same for
     `health_only`, as the user decided on 2026-09-25. No override is recorded.
   - Check health only: `health_only` verdict → today's path, no override recorded. `reject`
     verdict → record an override with route `health_only`, then the health-only path
     (status `analyzing`, `analysis`/`queued` event, push `/analysis`).
   - Check weight and health: record an override with route `dorsal_valid`, then the reference
     marking path, as "Analyze anyway" does today.
3. **Override event carries the route.** `recordViewGateOverride` gains a required
   `route` and writes it as the event's status: `'override:dorsal_valid'` or
   `'override:health_only'`. The stage stays `'view_override'`, and the image identity and the
   message stay as they are. A legacy row with status `'override'` is read as `dorsal_valid`,
   which is all it could mean in round 9. No schema change.
4. **Reading it back.** `hasViewGateOverride` is replaced by a `viewRouteOverride(db, scanId,
   imagePath)` that returns the chosen route, or null. It keeps the same identity-match rule
   (a null or different identity is never a match).
5. **`execute`.** It looks up the override for **any** verdict, not only `reject`. The
   "stop at the view gate" early return applies only to a `reject` with no override. The route
   is passed down as `viewRouteOverride` through `PipelineService.run` and
   `MlRuntime.runPipeline`, which sends `"view_route_override"` in the request and uses the
   request entrypoint whenever it is set. The boolean parameter is removed, and the four test
   fakes that implement `IPipelineService` are updated to the new parameter.
6. **F70, the cards read the route that ran.** `LocalScanBundle.viewOverridden` is replaced by
   the effective route (the override when present, otherwise the verdict). `_weightCard` says
   **Skipped** only when the effective route is not the full route. `_healthCard` says
   **Skipped** only for a `reject` with no override.

## Verification

- Extend `test/features/inference_pipeline/view_gate_override_test.dart`: route round-trip for
  both values, a legacy `'override'` row reads as `dorsal_valid`, an override for image A never
  applies to image B, and `execute` forwards the right route for each of the five choices in the
  parent's table (fake pipeline service capturing the argument).
- A widget test for the dialog: three buttons on both verdicts, the right choice returned for
  each, and dismissal treated as retake.
- A widget test for F70: an overridden full-route scan with an ineligible weight result shows
  "Unavailable".
- `dart format` on changed files, `flutter analyze` (no new issues), then the full
  `flutter test`, because `IPipelineService` changes shape across several test files.

### Result (2026-09-25)

- The dialog is a public top-level function, `showViewChoiceDialog()`, with a public
  `ViewChoice` enum, in `capture_screen.dart`, so the widget test can call it without mocking
  the camera (`test/features/capture/view_choice_dialog_test.dart`).
- The override event's status is `override:<route>`; `viewRouteOverride()` replaces
  `hasViewGateOverride()`. `view_gate_override_test.dart` now has 11 tests.
- **Deviation: the F70 widget test was replaced by a unit test.** A widget test that pumped the
  real `ResultsScreen` hung for 10 minutes on every attempt: its `tearDown` could not delete the
  temp image directory because `Image.file` still held the file open (Windows file locking, with
  the repo under OneDrive). It was replaced by
  `test/core/models/local_scan_bundle_effective_route_test.dart`, a unit test of
  `LocalScanBundle.effectiveRoute`, which is the value the weight and health cards read. The
  card rendering itself is not covered by an automated test.
- `flutter test` (full suite): 151 passed, 39 skipped, 0 failed. `flutter analyze`: no new
  issues. The `use_null_aware_elements` info at `lib/services/ml/ml_runtime.dart:240-241` was
  left as is; it matches the existing `cm_per_px` line's pattern.

## Open questions

- None. The user approved the wording above and chose `rejected` for Retake on 2026-09-25
  (parent's open questions 1 and 2).
