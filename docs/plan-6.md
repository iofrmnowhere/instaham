# Plan (round 6): pig folders on the Records screen

Opened 2026-09-26 from the user's instructions. Numbered round 6 because round 5
(`plan-5.md`, tap-to-find reference endpoints) is parked on the `round5-auto-find` branch and
keeps its number. The three small fixes requested in the same session are
[`fix-7.md`](fix-7.md) (round 11), a separate document.

## Goal

Let the user organise pigs into folders they create themselves, and see each folder's total
and average weight.

- The user creates, renames, and deletes folders by hand. The app never creates one on its own.
- A folder holds pigs (identified by their existing name or tag). Each pig is in at most one
  folder; a folder holds any number of pigs.
- The folder shows **total weight** and **average weight**, both computed from each pig's
  **latest eligible weight** (the newest scan of that pig with an eligible weight result and a
  value). Pigs with no such weight are left out of both numbers.
- The folder shows the count, for example "4 of 6 pigs weighed", so a partial total is not
  mistaken for the whole group.
- Deleting a folder offers two choices:
  - **Delete folder only.** The folder goes; its pigs become ungrouped and keep their scans.
  - **Delete folder and records.** The folder, its pigs, and all of those pigs' scans and
    results are deleted.
- Scans saved without a pig name stay outside folders and still appear in the normal records
  list (option A, confirmed by the user). A pig name stays optional when saving a scan.

## Design/Approach

**Schema v6 → v7.**

- New table `PigFolders`: `id` (text, local ID from `AppDatabase.newLocalId('folder')`),
  `name` (text, required), `createdAt`, `updatedAt`, `remoteId` (nullable, per the
  "stable local IDs, separate remote IDs" rule). No sync behaviour is added.
- `Pigs.folderId`: nullable text, references `PigFolders.id`. Null means ungrouped.
- Migration `if (from < 7)`: `createTable(pigFolders)`, `addColumn(pigs, pigs.folderId)`. No
  backfill; every existing pig starts ungrouped.
- `deleteAllUserRecords()` also clears `pigFolders` (after `pigs`, since pigs reference it).

**Data access.** A new `FoldersDao` (Drift accessor over `PigFolders`, `Pigs`, `ScanRecords`,
`WeightResults`), exposed through a folder repository interface. Both live in `lib/core/`
(next to the database), not in `lib/features/records/`, because two features use them: the
records feature (folder screens) and the results feature (folder picker). Features must not
import each other. Widgets never query the database directly.

- `watchFolders()`: each folder with its pig count, weighed-pig count, total kg, average kg.
- `watchFolderPigs(folderId)`: the folder's pigs, each with its latest eligible weight or none.
- `watchUngroupedPigs()`: pigs available to add.
- `createFolder(name)`, `renameFolder(id, name)`, `setPigFolder(pigId, folderId?)`.
- `deleteFolder(id, {required bool includeRecords})`: one transaction. With records, delete in
  foreign-key order: pipeline events, weight results, health results, reference annotations,
  sync outbox entries for those scans, the scans, the pigs, then the folder.
- The latest-weight rule and the total/average arithmetic live in one pure function so they
  can be unit-tested without a database.

**UI** (in `lib/features/records/presentation/`, following `docs/design-system.md`):

- Records screen header gets a **Folders** button (44×44 minimum, semantic label) opening a
  folders list screen: one card per folder with name, total kg, average kg, and
  "N of M pigs weighed", plus a "New folder" action (name dialog).
- Folder detail screen: the summary card, the list of pigs with each one's latest weight (or
  "No weight yet"), "Add pigs" (multi-select from ungrouped pigs), remove a pig from the
  folder, rename, and delete with the two-choice dialog. "Delete folder and records" asks for
  a second confirmation, because it cannot be undone.
- New routes under `/records/folders` and `/records/folders/:id`.
- Results screen (`lib/features/results/presentation/screens/results_screen.dart`): the pig
  card gains a **Folder** line under the pig name, showing the pig's folder or "No folder",
  with a button that opens a picker: the user's folders, "No folder", and "New folder" (name
  dialog, then the pig goes into it). Moving a pig to another folder takes it out of the old
  one (one folder per pig). The line appears only when the scan has a pig assigned; an
  unassigned scan shows no folder option, since folders hold pigs, not scans.
- No invented numbers: when no pig in a folder has a weight, total and average show "—".

## Steps

- [ ] 1. Schema: `PigFolders`, `Pigs.folderId`, `schemaVersion` 7, migration, regenerate
      Drift output (`dart run build_runner build --delete-conflicting-outputs`), migration
      test from v6, and `deleteAllUserRecords()` clears folders.
- [ ] 2. Pure summary function (latest eligible weight per pig, total, average, counts) with
      unit tests: repeat scans of one pig, ineligible latest scan, no weights at all.
- [ ] 3. `FoldersDao` + repository, with DAO tests: create/rename, add/remove pig, one folder
      per pig, both delete modes (with records: other folders' pigs and ungrouped scans stay).
- [ ] 4. Folders list screen, folder detail screen, routes, Records header button, delete
      dialog. Widget tests for the summary card ("—" when empty, "N of M pigs weighed") and
      the two delete choices.
- [ ] 5. Results screen folder line and picker. Widget tests: hidden for an unassigned scan,
      shows the current folder, picking a folder moves the pig, "New folder" creates and
      assigns.
- [ ] 6. `dart format`, `flutter analyze`, targeted tests, then the full suite (schema change
      is cross-cutting). Device check by the user.

## Open questions

1. Resolved 2026-09-26: pigs can be added from both the folder detail screen and the results
   screen (the user's choice). The records card is not included.
2. Resolved 2026-09-26: "latest" means the newest scan by `capturedAt`, falling back to
   `createdAt` for scans with no capture time. The two only differ for old gallery photos.
3. Resolved 2026-09-26: the user has no plans to revive round 5 (`round5-auto-find`), so its
   schema v7 does not constrain this plan.

Plan rating: 8/10. Pros: one new table and one nullable column; the latest-weight rule is
isolated and testable; follows the existing DAO/repository pattern; both delete modes are
explicit; pigs can be filed right after a scan or later from the folder. Cons: two entry
points to test; the DAO sits in `lib/core/` rather than the records feature so both features
can share it; a pig with no name/tag cannot be found easily in the picker.
