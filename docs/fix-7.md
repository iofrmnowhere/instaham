# Fix (round 11): orientation prompt, full local wipe, and "Health only" status

Seventh fix document, opened as **round 11** on 2026-09-26 from the user's instructions. Three
small, independent fixes. The pig-folder feature requested in the same session is a separate
document, [`plan-6.md`](plan-6.md), and is not a phase of this round.

Finding numbering continues at **F71** (F70 was the last assigned, in round 10).

## Symptom

- **F71.** The camera shows a live "Portrait: keep the pig's head facing up" /
  "Landscape: keep the pig's head facing right" prompt, and the capture tips list repeats both
  sentences. The user wants both removed.
- **F72.** "Delete all local records" on the privacy screen leaves captured photos
  (`instaham_cap_*.jpg` in the temp directory) on disk, and deleted rows stay readable in the
  SQLite file's free pages until a `VACUUM`.
- **F73.** A scan whose weight branch fails but whose health branch succeeds is shown as
  **Blocked** in the records list, counted under "Needs Review" on the records and home
  screens, and counted as blocked on the analytics weight panel.

## Root cause

- **F71.** `_buildOrientationPrompt()` in `capture_screen.dart` and the last two entries of
  `tips` in `capture_guidance_screen.dart`, both added by
  `docs/fix-phase-4/6-capture-orientation.md`.
- **F72.** `AppDatabase.deleteAllUserRecords()` only runs `DELETE` statements. Nothing removes
  image files or compacts the database.
- **F73.** `run_and_persist_pipeline_use_case.dart:343` writes `ScanStatuses.blocked` whenever
  the weight branch is not eligible, regardless of health. The records list prints the raw
  status, and the analytics weight panel counts every ineligible weight row as blocked.

## Change made

### F71: remove the orientation prompt (keep the attestation)

- Remove `_buildOrientationPrompt()` and its call site, plus the now-unused
  `_orientationFor()` if nothing else uses it.
- Remove the two portrait/landscape tips from `capture_guidance_screen.dart`.
- Remove `CaptureOrientationCopy.headDirectionInstruction` if it has no other caller.
- **Keep** the review-step attestation checkbox, `attestationLabel`, and the
  `_usePhoto` gate unchanged.

### F72: complete the local wipe (custom references kept)

- After the delete transaction, run `VACUUM` so deleted rows leave the file.
- Delete every photo copy in the app's own temp directory (`getTemporaryDirectory()`, which is
  the app cache on Android), searched recursively, by image extension (`.jpg`, `.jpeg`, `.png`,
  `.webp`, `.heic`). This covers, as confirmed by the user on 2026-09-26:
  - the app's processed copies, `instaham_cap_*.jpg`;
  - the camera plugin's raw shot from `takePicture()`, which the plugin writes to the cache
    and the app never deletes;
  - the image picker's cached copy of a camera or gallery pick.
- Files outside the app's temp directory (for example the original photo in the phone's
  gallery) are never deleted.
- Custom references and privacy preferences are kept. The dialog text names both.
- File deletion lives in a small service in `lib/core/`, not in the widget.

### F73: "Health only" and "Blocked" worked out at display time

The stored status is not changed, so older scans display correctly without a data migration.

- New pure helper, in `lib/core/models/`: given the stored status, whether a weight value
  exists, and whether a health result exists, return the displayed status.
  - Stored `blocked`, with no weight value and an eligible health result → **Health only**.
  - Stored `blocked`, with neither a weight value nor an eligible health result → **Blocked**.
  - Everything else → unchanged.
- `RecordsDao.watchRecentScans` left-joins `HealthResults` and `WeightResults`, and
  `ScanWithPig` carries the two booleans.
- Records list pill shows "Health only". "Needs Review" (records filter and home-screen count)
  counts only **Blocked** and `rejected`, not Health only (confirmed by the user on
  2026-09-26).
- Analytics: the weight panel's "Ineligible / Blocked" card becomes two counts, **Health only**
  and **Blocked** (both branches without a value). The health panel's "Blocked" uses the same
  both-failed rule.
- The per-branch cards on the results screen (weight card "Blocked" when that branch failed)
  are not changed; they describe one branch, not the scan.

## Verification

- `dart format` on changed files, `flutter analyze`.
- Unit test for the display-status helper (all four cases).
- `test/features/records/records_dao_test.dart`: a weight-failed, health-ok scan reports
  health available.
- `test/features/analytics/analytics_dao_test.dart`: Health only and Blocked counts.
- `test/core/database/app_database_test.dart`: the wipe keeps custom references and privacy
  preferences and empties every other user table.
- Photo deletion is covered by a test on the service, using a temporary directory.
- Device check by the user after the next APK build.
