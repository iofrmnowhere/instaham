# Handoff — 2026-09-25 (session 18)

## Active work

**None.** Round 10 (`docs/fix-6.md`) was closed this session. All four phases are done, and it
has a line in `docs/changelog.md`. The file and `docs/fix-phase-6/` stay in place with
"closed" in the title, following the `plan-4.md` convention.

Other documents are still open and were not touched this session: `plan-2.md` (round 2, device
check), `fix-5.md` (round 9), `fix-4.md` (round 8, device sideload), and `plan.md` (Chen16
swap, phase 5).

## State

- Round 10's behaviour and contract are in [ADR-020](adr/020-view-route-override-either-route.md),
  which partly supersedes ADR-017, and in `ffi-bridge.md`, `spec.md` (view classifier contract),
  `app-flow.md` and `design-system.md`.
- The user checked a sideloaded release build. Both dialog choices route correctly, the dialog
  appears on both `reject` and `health_only` photos, a dorsal photo goes straight to reference
  marking, and no photo-check card appears on results. The result is recorded in
  `docs/fix-phase-6/4-docs-and-device.md`.

## Decisions made (not obvious from the docs)

- **The full `flutter test` suite was not rerun after phase 3; the user agreed to skip it.**
  Phase 3 only deleted two private methods in `results_screen.dart`, which nothing else
  referenced. Only `test/features/results/` was run (10/10). The changelog line says so.
- **Phase 3's widget test covers `dorsal_valid` and `health_only` scans only, not an overridden
  one.** `viewRouteOverride()` matches on the sha256 of a real image file. Seeding one would
  bring back the `Image.file` Windows file lock that hung phase 2's F70 test, so the test seeds
  scans with no `imagePath`, the same way `health_card_cascade_test.dart` does.
- **`spec.md` had never recorded round 9's boolean override**, so both rounds were added to it
  in this session. This was an intentional catch-up, not drift.
- **A false alarm this session:** the user first reported a missing loading animation and a
  missing dialog. The cause was an older APK that had not been replaced. Nothing was changed,
  and the report was withdrawn.

## Next steps

1. Pick up the carried-over items in order: round 2's device check (`plan-2.md`), round 8's
   device sideload (`fix-4.md`), round 9 (`fix-5.md`), and the orphan Records rows.
2. Committing is the user's call. Nothing has been committed.

## Build / environment

- **MSVC is BuildTools.** Build through the PowerShell tool:
  `cmd /c '"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1 && cd /d "<repo>\packages\instaham_ml_ffi\src\build\host" && ninja'`.
- **Never run bare `ctest`**, because `test_abi` opens a modal dialog. Use
  `ctest -E test_abi --timeout 400`. The last result (session 17) was 11/12; the only failure
  is `test_scale_normalization`, which was already failing. No native code changed this
  session.
- **`flutter test` can take more than 2 minutes to compile cold**, so run it in the
  background. If a run is killed mid-compile, delete `build/test_cache/` before retrying.
- **A widget test that pumps `ResultsScreen` with a real image file hangs on Windows/OneDrive**
  (the `Image.file` lock blocks the temp-dir cleanup in `tearDown`). Seed scans without an
  `imagePath`.
- No Firebase Test Lab run without an explicit per-run instruction.

## Files changed this session

- `lib/features/results/presentation/screens/results_screen.dart`: removed `_viewCard()`,
  `_viewOverrideBanner()` and their call sites (F69).
- `test/features/results/results_screen_view_cards_removed_test.dart` (new): the phase 3
  widget test.
- `test/features/results/health_card_cascade_test.dart`: a stale layout comment was corrected.
- `docs/adr/020-view-route-override-either-route.md` (new); `docs/adr/017-*.md`: status line
  only.
- `docs/ffi-bridge.md`, `docs/architecture.md`, `docs/pipeline/README.md`: the view route
  override.
- `docs/spec.md`: the view override contract and the `envelope["view"]` fields.
- `docs/app-flow.md`, `docs/design-system.md`: the three-button dialog; no view card on results.
- `docs/fix-6.md`, `docs/fix-phase-6/1-4*.md`: statuses, results, and close-out.
- `docs/changelog.md`: the round 10 line.
- `docs/handoff.md`: this file.

## Rollback points

Branch `initial_health`, nothing pushed, and `HEAD` is still `96e8152`. Rounds 8, 9, 3, 4 and
10 are all uncommitted. **Do not commit without being asked.**
