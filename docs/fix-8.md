# Fix (round 12): one pig per record, auto pig IDs, marker opacity, folder dialogs, folder taps

Eighth fix document, opened as **round 12** on 2026-09-26 from the user's instructions. It builds
on the uncommitted pig-folder work in [`plan-6.md`](plan-6.md) (steps 1–6 implemented, device
check pending) and does not reopen [`fix-7.md`](fix-7.md) (F71–F73, device check pending).

Finding numbering continues at **F74** (F73 was the last assigned, in round 11).

## Symptom

- **F74.** Assigning a scan asks the user to type a "Pig tag or ID", and every scan typed with
  the same tag is merged into one pig. The user wants every record to be its own pig, with an
  ID the app generates, instead of a typed unique ID (confirmed 2026-09-26: "Each record is its
  own pig"; repeat scans of the same animal are not linked).
- **F75.** On the reference-marking screen, the pink line and the caliper-jaw markers are fully
  opaque, so they cover the end of the stick. The user cannot see whether a point was placed a
  little short of the real end.
- **F76.** The folder dialogs have badly placed buttons. In the delete dialog, "Cancel",
  "Delete folder only", and "Delete folder and records" wrap into a right-aligned stack that is
  not centred. The folder picker used when assigning a pig to a folder is also misaligned.
- **F77.** Tapping a pig inside a folder does nothing, so the user cannot open that record.

## Root cause

- **F74.** `AppDatabase.assignPig()` (`app_database.dart:453`) looks up a pig by the typed
  `tag` and reuses it if it exists. `_assignPig()` in `results_screen.dart` requires the tag.
  Scans start with no pig at all (`createDraftScan()` does not create one).
- **F75.** `_ReferenceLinePainter` and `_ReferenceJawPainter` in
  `reference_marking_screen.dart` paint with full-alpha `AppColors.signalPink` and
  `Colors.white`.
- **F76.** `delete_folder_dialog.dart` puts three buttons in `AlertDialog.actions`. When they do
  not fit in one row, the dialog's `OverflowBar` stacks them aligned to the end, at their own
  widths. The results-screen folder picker is a `SimpleDialog` of plain left-aligned text
  options with no button styling. The "Add pigs" dialog on the folder detail screen uses the
  same right-aligned actions row.
- **F77.** `_FolderPigTile` in `folder_detail_screen.dart` has no `onTap`, and `FolderPig`
  carries no scan to open.

## Change made

### F74: one pig per record, with an auto-generated ID

- Every scan gets its own pig when the scan is created: `createDraftScan()` also inserts a pig
  in the same transaction and sets `scanRecords.pigId`.
- The pig's `tag` is the auto ID `PIG-0001`, `PIG-0002`, …: one more than the highest existing
  `PIG-` number, including soft-deleted pigs so a number is not reused while its row exists.
  `id` stays `newLocalId('pig')` (stable local ID, separate from what the user sees).
- The display name stays optional and editable. `assignPig()` is replaced by
  `renamePig(pigId, displayName)`. The results screen's "Assign"/"Change" button becomes
  **"Rename"**, and its dialog has only the display-name field. The auto ID is shown read-only
  under the name ("ID PIG-0007").
- **Schema v7 → v8, data only** (no table or column change):
  - every scan with no pig gets a new pig with an auto ID;
  - every pig with more than one scan is split: its oldest scan keeps the pig, and each other
    scan gets a new pig with an auto ID that copies the display name and `folderId`, so folder
    membership is kept;
  - tags typed by the user on existing pigs are kept as they are.
- The migration tests build the current schema and roll it back. Since v8 changes no
  structure, the v3→4, v4→5, v5→6, and v6→7 tests need no new rollback step.
- The demo-scan seeder (`app_database.dart:639`) uses the new path instead of a random
  `TAG-xxx`.
- Unchanged: records search and analytics still filter by display name, so records sharing a
  name ("Bella") are still found together. Folder totals and averages use the same summary
  function; each pig now has exactly one scan, so its "latest eligible weight" is that scan's.

### F75: see-through reference markers

- `_ReferenceLinePainter`: the line is drawn at about 40 % opacity.
- `_ReferenceJawPainter`: the white halo and the pink outline at about 50 %; the measuring edge
  (the side that sits exactly on the point) at about 70 %, so it still reads as the mark.
- Only paint colours change. Point positions, coordinate mapping, and the jaw geometry are not
  touched (AGENTS.md rules 6 and 9). Exact values are tuned on the device check.

### F76: centred, full-width dialog buttons

- The delete dialog shows its choices as a vertical stack of full-width buttons, centred:
  "Delete folder only" (outlined), "Delete folder and records" (destructive), then "Cancel"
  (text). The second "This cannot be undone" dialog uses the same layout.
- The folder picker on the results screen uses the same layout: one full-width button per
  folder, then "No folder", "New folder", and "Cancel".
- The "Add pigs" dialog's actions row is centred to match. Each pig is listed by its auto ID
  and display name, since several records may now share a name.
- One small shared helper in `lib/core/widgets/` builds the stacked layout, because both the
  records and results features use it. Every button is at least 44 logical pixels tall.

### F77: tapping a pig in a folder opens its record

- `FolderPig` gains the pig's scan (id, goal, image path).
- `_FolderPigTile` becomes tappable and opens `/analysis` with the same `ScanFlowArgs` the
  records list uses. The remove button stays a separate target.

## Verification

- `dart format` on changed files, `flutter analyze`.
- `dart run build_runner build --delete-conflicting-outputs` (schema version change).
- `test/core/database/app_database_test.dart`: a new scan has its own pig with the next auto
  ID; two scans never share a pig; the v7 → v8 migration backfills pigless scans and splits a
  two-scan pig while keeping its folder.
- Update existing `assignPig` callers in tests (`app_database_test.dart`,
  `analytics_dao_test.dart`, `records_dao_test.dart`, `results_screen_folder_line_test.dart`).
- Widget tests: delete dialog buttons are full width and all three choices still return the
  right result; tapping a folder pig pushes `/analysis` for its scan.
- Full `flutter test` suite (schema change is cross-cutting), bounded with `timeout`.
- Device check by the user: marker opacity, dialog layout, rename, tap-through from a folder.

## Steps

- [ ] F74 one pig per record + auto ID + v8 migration
- [ ] F75 marker opacity
- [ ] F76 dialog layout
- [ ] F77 folder pig tap opens record
- [ ] Full suite, then device check

## Open questions

1. Existing pigs keep their typed tags (for example `TAG-1`) as their ID; only new pigs get
   `PIG-####`. Say so if old tags should be renumbered too.
2. "Assigning the folder" is read as the results-screen folder picker and the "Add pigs"
   dialog. Say so if a different dialog was meant.

Plan rating: 7/10. Pros: fixes all five issues; F75–F77 are small and local; the v8 migration
is data-only, keeps folder membership, and never deletes a scan; auto IDs are separate from
the stable local IDs. Cons: splitting multi-scan pigs is a one-way change to existing data;
creating a pig for every draft scan means an abandoned draft uses an ID number (gaps in the
numbering); growth over time for one animal is no longer tracked by pig, only by shared
display name.
