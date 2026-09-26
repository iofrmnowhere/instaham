import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/folder_pig.dart';
import '../models/folder_summary.dart';
import '../services/folder_weight_summary.dart';

part 'folders_dao.g.dart';

// docs/plan-6.md (round 6, pig folders): lives in lib/core/ rather than a single feature
// because both the records feature (folder screens) and the results feature (folder
// picker) use it, and features must not import each other.
@DriftAccessor(tables: [PigFolders, Pigs, ScanRecords, WeightResults])
class FoldersDao extends DatabaseAccessor<AppDatabase> with _$FoldersDaoMixin {
  FoldersDao(super.db);

  /// Each folder with its pig count, weighed-pig count, total kg, and average kg. One
  /// left-joined query across folders, pigs, scans, and weight results, so the stream
  /// reacts to a change in any of them; the latest-weight rule and the arithmetic are the
  /// pure functions in `folder_weight_summary.dart`.
  Stream<List<FolderSummary>> watchFolders() {
    final query = select(db.pigFolders).join([
      leftOuterJoin(db.pigs, db.pigs.folderId.equalsExp(db.pigFolders.id)),
      leftOuterJoin(
        db.scanRecords,
        db.scanRecords.pigId.equalsExp(db.pigs.id) &
            db.scanRecords.deletedAt.isNull(),
      ),
      leftOuterJoin(
        db.weightResults,
        db.weightResults.scanId.equalsExp(db.scanRecords.id),
      ),
    ]);

    return query.watch().map((rows) {
      final foldersById = <String, PigFolder>{};
      final pigIdsByFolder = <String, Set<String>>{};
      final scansByFolderPig = <String, Map<String, List<ScanWeightSample>>>{};

      for (final row in rows) {
        final folder = row.readTable(db.pigFolders);
        foldersById[folder.id] = folder;

        final pig = row.readTableOrNull(db.pigs);
        if (pig == null) continue;
        pigIdsByFolder.putIfAbsent(folder.id, () => {}).add(pig.id);

        final scan = row.readTableOrNull(db.scanRecords);
        if (scan == null) continue;
        final weight = row.readTableOrNull(db.weightResults);
        scansByFolderPig
            .putIfAbsent(folder.id, () => {})
            .putIfAbsent(pig.id, () => [])
            .add(
              ScanWeightSample(
                capturedAt: scan.capturedAt,
                createdAt: scan.createdAt,
                eligible: weight?.eligible ?? false,
                valueKg: weight?.valueKg,
              ),
            );
      }

      final summaries = foldersById.values.map((folder) {
        final pigIds = pigIdsByFolder[folder.id] ?? const <String>{};
        final scansByPig = scansByFolderPig[folder.id] ?? const {};
        final latestWeights = pigIds.map(
          (pigId) => latestEligibleWeightKg(scansByPig[pigId] ?? const []),
        );
        final summary = summarizeFolderWeights(latestWeights);
        return FolderSummary(
          folder: folder,
          pigCount: summary.totalCount,
          weighedCount: summary.weighedCount,
          totalKg: summary.totalKg,
          averageKg: summary.averageKg,
        );
      }).toList();
      summaries.sort((a, b) => a.folder.name.compareTo(b.folder.name));
      return summaries;
    });
  }

  /// The folder's pigs, each with its latest eligible weight or none.
  Stream<List<FolderPig>> watchFolderPigs(String folderId) {
    final query = select(db.pigs).join([
      leftOuterJoin(
        db.scanRecords,
        db.scanRecords.pigId.equalsExp(db.pigs.id) &
            db.scanRecords.deletedAt.isNull(),
      ),
      leftOuterJoin(
        db.weightResults,
        db.weightResults.scanId.equalsExp(db.scanRecords.id),
      ),
    ])..where(db.pigs.folderId.equals(folderId) & db.pigs.deletedAt.isNull());

    return query.watch().map((rows) {
      final pigsById = <String, Pig>{};
      final scansByPig = <String, List<ScanWeightSample>>{};

      for (final row in rows) {
        final pig = row.readTable(db.pigs);
        pigsById[pig.id] = pig;

        final scan = row.readTableOrNull(db.scanRecords);
        if (scan == null) continue;
        final weight = row.readTableOrNull(db.weightResults);
        scansByPig
            .putIfAbsent(pig.id, () => [])
            .add(
              ScanWeightSample(
                capturedAt: scan.capturedAt,
                createdAt: scan.createdAt,
                eligible: weight?.eligible ?? false,
                valueKg: weight?.valueKg,
              ),
            );
      }

      final folderPigs = pigsById.values.map((pig) {
        return FolderPig(
          pig: pig,
          latestWeightKg: latestEligibleWeightKg(
            scansByPig[pig.id] ?? const [],
          ),
        );
      }).toList();
      folderPigs.sort((a, b) => _pigLabel(a.pig).compareTo(_pigLabel(b.pig)));
      return folderPigs;
    });
  }

  /// The pig's current folder id, reactively -- null when ungrouped. docs/plan-6.md step 5:
  /// the results screen's Folder line reads this instead of the scan bundle's once-loaded
  /// `Pig.folderId`, so a move made from the picker (or elsewhere) shows up immediately.
  Stream<String?> watchPigFolderId(String pigId) {
    final query = select(db.pigs)..where((p) => p.id.equals(pigId));
    return query.watchSingleOrNull().map((pig) => pig?.folderId);
  }

  /// Pigs available to add to a folder: ungrouped and not soft-deleted.
  Stream<List<Pig>> watchUngroupedPigs() {
    final query = select(db.pigs)
      ..where((p) => p.folderId.isNull() & p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.asc(p.displayName)]);
    return query.watch();
  }

  Future<String> createFolder(String name) async {
    final id = AppDatabase.newLocalId('folder');
    final now = DateTime.now();
    await into(db.pigFolders).insert(
      PigFoldersCompanion(
        id: Value(id),
        name: Value(name.trim()),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return id;
  }

  Future<void> renameFolder(String id, String name) {
    return (update(db.pigFolders)..where((f) => f.id.equals(id))).write(
      PigFoldersCompanion(
        name: Value(name.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Sets `pigId`'s folder to `folderId`, or clears it (ungroups the pig) when null. A pig
  /// is in at most one folder, so this replaces its previous folder rather than adding to it.
  Future<void> setPigFolder(String pigId, String? folderId) {
    return (update(db.pigs)..where((p) => p.id.equals(pigId))).write(
      PigsCompanion(
        folderId: Value(folderId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// docs/plan-6.md: deletes the folder. With `includeRecords`, also deletes its pigs and
  /// all of those pigs' scans and results, in foreign-key order (pipeline events, weight
  /// results, health results, reference annotations, sync outbox entries, the scans, then
  /// the pigs). Without, the folder's pigs are ungrouped and keep their scans. One
  /// transaction either way.
  Future<void> deleteFolder(String id, {required bool includeRecords}) async {
    await transaction(() async {
      if (includeRecords) {
        final pigIds = await (select(
          db.pigs,
        )..where((p) => p.folderId.equals(id))).map((p) => p.id).get();

        if (pigIds.isNotEmpty) {
          final scanIds = await (select(
            db.scanRecords,
          )..where((s) => s.pigId.isIn(pigIds))).map((s) => s.id).get();

          if (scanIds.isNotEmpty) {
            await (delete(
              db.pipelineEvents,
            )..where((e) => e.scanId.isIn(scanIds))).go();
            await (delete(
              db.weightResults,
            )..where((w) => w.scanId.isIn(scanIds))).go();
            await (delete(
              db.healthResults,
            )..where((h) => h.scanId.isIn(scanIds))).go();
            await (delete(
              db.referenceAnnotations,
            )..where((r) => r.scanId.isIn(scanIds))).go();
            await (delete(db.syncOutboxEntries)..where(
                  (e) => e.entityType.equals('scan') & e.entityId.isIn(scanIds),
                ))
                .go();
            await (delete(
              db.scanRecords,
            )..where((s) => s.id.isIn(scanIds))).go();
          }
          await (delete(db.pigs)..where((p) => p.id.isIn(pigIds))).go();
        }
      } else {
        await (update(db.pigs)..where((p) => p.folderId.equals(id))).write(
          const PigsCompanion(folderId: Value(null)),
        );
      }
      await (delete(db.pigFolders)..where((f) => f.id.equals(id))).go();
    });
  }

  String _pigLabel(Pig pig) {
    final name = pig.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final tag = pig.tag?.trim();
    if (tag != null && tag.isNotEmpty) return tag;
    return pig.id;
  }
}
