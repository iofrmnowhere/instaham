# Phase 3 — validation and documentation

Status: in progress — tests and docs done; device check and the deferred capture-review widget test outstanding

## Goal

Prove phases 1 and 2 on a real device, cover them with the host tests that are actually
possible, and update the documents that now describe the app incorrectly.

## Design/Approach

Host tests cannot load the native library, so the test split is deliberate:

- **Host-testable**: the Dart-side serialization of native calls (through a fake invoker), the
  progress widget's states, the capture review screen's disabled actions, and the absence of
  fabricated stage-completion text. Every existing test double for `IPipelineService` keeps
  working because phase 1 does not change the interface.
- **Device-only**: that the UI stays responsive during a 12–71 second run, that results for a
  given photo are unchanged by the thread move, and that memory does not regress against the
  figures in `docs/device-metrics-results.md`.

Note: round 9 (`fix-5.md` phase 2) already owes a capture-screen widget test for the reject
dialog. The test added here covers the review screen's busy state instead. They are separate
debts — do not close one by writing the other.

## Steps

- [x] Host test: two overlapping calls through `MlRuntime`'s lock complete strictly in order.
      `test/core/utils/call_queue_test.dart` — 3 tests: enqueue-order completion, a failed
      task not wedging the queue, and the failing task's own error still reaching its own
      caller.
- [x] Widget test: `AnalysisProgressView` renders its phase label and indicator, and renders no
      stage-completion text. `test/features/results/analysis_progress_view_test.dart` — 4
      tests: label + indicator render, label updates on phase change, no fabricated
      stage/cancel text, live-region semantics wiring. The elapsed-seconds *value* is not
      assertable under `tester.pump()`: the widget's counter reads a real `Stopwatch`, which
      the test binding's fake `Timer` clock does not advance, so the test checks the counter's
      accessible wiring at `0 s` instead of a fast-forwarded value.
- [ ] Widget test: capture review disables "Retake"/"Verify reference" and shows the busy
      indicator while the view gate runs. **Deferred, not written** — same reason 2.1 deferred
      capture-screen widget tests: `CaptureScreen` has no `camera`/`image_picker`
      platform-channel test harness in this repo, and `initState` calls `_initCamera()`
      unconditionally, so pumping the widget at all requires mocking those plugins first.
      Building that harness is its own piece of work, not phase 3's smallest coherent step
      (AGENTS.md); it is not built here.
- [x] `dart format` on changed Dart files; `flutter analyze`; targeted
      `flutter test test/features/... ` for the new tests; full `flutter test` last, since the
      threading change is cross-cutting.
      **Correction to this line's own baseline claim:** the true pre-phase-3 baseline is
      **119 passed, 39 skipped** — verified by pulling the two new test files back out and
      rerunning the full suite. The handoff that flagged "119" as stale and "122" as current
      had it backwards; 122 does not reproduce. `dart format` reformatted one new file only;
      `flutter analyze` found the same 8 pre-existing issues, zero new; full suite after adding
      the tests is 126 passed, 39 skipped (119 + 7 new, skip count unchanged).
- [ ] Device check on a sideloaded APK: one full scan end to end, watching for a continuously
      animating indicator, an unchanged stored result for the same photo, and a back-press
      mid-analysis leaving a complete scan in Records.
- [x] `docs/app-flow.md` — stage B currently describes `/analysis` as running the pipeline with
      no mention of where it runs or what the user sees. Update both waits. Plain doc, edit
      directly. Done: stage B gained a "Where the work runs, and what the user sees" section
      (worker isolate + `CallQueue`, the three phase labels, warn-once `PopScope`, no cancel,
      no stage ticks), and stage A gained "When the scan row is actually created" and "The
      capture-time wait".
      **Correction to the handoff's premise for this step:** the handoff said `_usePhoto` is
      now the first creator of a scan. It is not — `_capture()`/`_pickFromGallery()` create it
      first, via `_ensureSession()` after the mounted check, and `_usePhoto()` normally finds
      it already there. The handoff also said a capture the user quits out of "writes nothing
      at all"; that holds only while processing is still in flight. Reaching the review screen
      and then leaving does leave a `captured` row with no results, and nothing cleans it up.
      `app-flow.md` documents the behaviour as it actually is.
- [x] `docs/design-system.md` — record the loading/progress contract (indeterminate indicator,
      honest phase label, expectation line, no fabricated stage ticks, no cancel) so the next
      screen that needs one does not invent a second pattern. Plain doc, edit directly. Done:
      a "Loading and progress contract" subsection under "Approved End-to-End Scan Flow", eight
      rules with `AnalysisProgressView` named as the reference implementation.
- [x] Flag a `pipeline-docs` run: the FFI bridge's threading contract changes (native calls now
      execute on a worker isolate's thread, `instaham_ml_last_error`'s `thread_local` scope
      becomes load-bearing, and callers must be serialized). That is ADR-worthy —
      `ffi-bridge.md` and a new ADR belong to `pipeline-docs`, not to this plan. Flag raised in
      `plan-2.md`'s "Relationship to the open documents" section and in the changelog line,
      spelling out the three contract changes and what ADR-018 owes. The `pipeline-docs` run
      itself has NOT been made.
- [x] `docs/changelog.md` — one line when all three phases close, per the planner contract.
      Written 2026-09-23. It states plainly that phase 3's device check is still owed and its
      capture-review widget test is deferred, rather than closing the round as fully verified.

## Verification

Report the exact commands run and their output. Do not report a device result that was not
observed, and do not cite the existing `device-metrics-results.md` latencies as if they were
re-measured after this change — if the run is not repeated, say so.

## Open questions

- Whether a re-measure of metric 2 (inference latency) is wanted after the thread move. The
  computation is unchanged, so the median should not move; confirming that costs Firebase Test
  Lab quota and must not be submitted without an explicit instruction for that specific run.
