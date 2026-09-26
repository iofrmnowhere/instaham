# Handoff — 2026-09-26 (session 31)

## Active work

**`docs/fix-8.md` (round 12): F74 is implemented. F75, F76, and F77 are not started. Nothing is committed.**

- Next is F75: make the reference-point markers partly transparent.
- The step checkboxes in `fix-8.md` are **not ticked**, including F74. Tick them through `planner`.
- `docs/plan-6.md` (pig folders): all 6 steps are implemented; only the user's device check is left.
  The checkboxes are still unticked.
- `docs/fix-7.md` (F71–F73): still waiting for the user's device check.

Other documents still open on this branch and not touched: `plan-2.md`, `fix-4.md`, `fix-5.md`, `plan.md`
(Chen16 swap, phase 5).

## State

- Branch `initial_health`, `HEAD` `4c9297b`. Everything is uncommitted: fix-7, plan-6, and fix-8 F74.
- No native, model, FFI, or manifest change, so neither pipeline-docs nor spec-drift needs to run.
- No APK rebuild and no device check yet, for fix-7, plan-6, or fix-8.

## Decisions made (not recorded in fix-8.md)

- **One pig per record** was the user's answer when asked (not "auto ID, but pigs still link scans").
  Repeat scans of the same animal are no longer linked.
- **`createDraftScan(pigId:)`:** when the caller passes a `pigId`, no pig is auto-created. Only
  `folders_dao_test.dart` does this. Otherwise every scan gets a new pig with tag `PIG-####`, where
  #### is the highest existing `PIG-` number plus 1.
- **`assignPig()` is removed.** It is replaced by `renamePigForScan(scanId, displayName)`. A blank name
  sets the display name to null, and the UI then shows the tag.
- **Schema v8 changes data only.** The `from < 8` step calls `_splitPigsOneScanEach()`.
  `build_runner` did not run, because no table or column changed. The v3–v7 migration tests needed no
  new rollback step.
- **Test harness fallout:** every scan now has a pig, so the results screen's Folder line always
  builds. Any widget test that pumps `ResultsScreen` needs:
  - a `FoldersScope`;
  - `flushDriftStreamTimers` at the end of the test.
  Both were added to `health_card_cascade_test.dart` and `results_screen_view_cards_removed_test.dart`.
- **The "no Folder line" test** now seeds a pigless scan with a direct `scanRecords` insert, because
  the app can no longer create one.

## Open questions / risks

- The two open questions in `fix-8.md` have not been answered by the user:
  1. Should old typed tags be renumbered to `PIG-####`?
  2. Which dialog does "assigning the folder" mean?
- **`_renamePig` in `results_screen.dart` disposes `nameController` right after `showDialog`
  returns.** This is the same "used after being disposed" pattern that session 30 fixed in
  `folder_name_dialog.dart`. Session 30 said to raise it, not fix it silently. It is still unraised,
  and this session carried the pattern into the new code. Raise it with the user; a fix could fit
  into F76.
- Minor, carried over: `records_screen.dart` pushes the literal `'/records/folders'` instead of
  `AppRoutes.recordsFolders`.

## Next steps

1. F75: in `reference_marking_screen.dart`, lower the alpha of `_ReferenceLinePainter` and
   `_ReferenceJawPainter`, following the values in `fix-8.md`.
2. F76: dialog layout.
3. F77: make a folder's pig open its record.
4. Run the full suite, then the user rebuilds the APK and device-checks fix-7, plan-6, and fix-8
   together.
5. After the device checks, tick the steps and close the documents through `planner`, which also
   writes the changelog.
6. Committing is the user's call. Ask before any `git add` or commit.

## Validation run this session

- Full `flutter test` before F74: 195 passed, 39 skipped, 0 failed. This closes plan-6 step 6.
- After F74:
  - `dart format` and `flutter analyze lib/ test/`: clean, apart from 2 older infos in
    `ml_runtime.dart`.
  - Full `flutter test`: 196 passed, 39 skipped, 0 failed.

## Build / environment

- Wrap every `flutter test` in `timeout`, and run long ones in the background. The Bash tool's own
  120 s limit moves slower foreground runs to the background.
- Free RAM was about 4–5 GB this session. Check `wmic OS get FreePhysicalMemory` before blaming a
  hang on the code.
- `dart format .` fails on the `build/` folder. Format only the files you changed.
- Carried over:
  - Never run bare `ctest`.
  - No Firebase Test Lab without an explicit instruction.
  - `EditableText.debugDeterministicCursor = true` stops cursor-blink hangs in tests.

## User preferences seen

- Wants short answers, one step at a time, and a report after each step. Code only after an explicit
  "do X".

## Files changed this session

- `docs/fix-8.md` (new): round 12 fix document, F74–F77.
- `lib/core/database/app_database.dart`:
  - schema v8 and the migration;
  - auto pig in `createDraftScan`;
  - `_nextPigNumber`, `_generatePigTag`, `_createPigAndAssign`, and `_splitPigsOneScanEach`;
  - `renamePigForScan`, which replaces `assignPig`;
  - the demo seeder now uses the new path.
- `lib/features/results/presentation/screens/results_screen.dart`: `_renamePig` and the "Rename"
  button.
- Tests:
  - `app_database_test.dart`: new v7→v8 migration test and updated assertions.
  - `analytics_dao_test.dart`, `records_dao_test.dart`: calls moved to `renamePigForScan`.
  - `results_screen_folder_line_test.dart`: pigless seed and rename.
  - `health_card_cascade_test.dart`, `results_screen_view_cards_removed_test.dart`: `FoldersScope`
    and the timer flush.
