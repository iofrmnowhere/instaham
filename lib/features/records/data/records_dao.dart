import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/models/local_scan_bundle.dart';
import '../../../../core/models/pig_suggestion.dart';
import '../../../../core/models/scan_with_pig.dart';

part 'records_dao.g.dart';

@DriftAccessor(
  tables: [
    ScanRecords,
    Pigs,
    ReferenceAnnotations,
    WeightResults,
    HealthResults,
  ],
)
class RecordsDao extends DatabaseAccessor<AppDatabase> with _$RecordsDaoMixin {
  RecordsDao(super.db);

  Stream<List<ScanWithPig>> watchRecentScans({int limit = 100}) {
    // docs/fix-7.md F73: left-joined so the display-status split (Health only vs. Blocked)
    // can be worked out per row without a second query per scan.
    final query =
        select(db.scanRecords).join([
            leftOuterJoin(db.pigs, db.pigs.id.equalsExp(db.scanRecords.pigId)),
            leftOuterJoin(
              db.weightResults,
              db.weightResults.scanId.equalsExp(db.scanRecords.id),
            ),
            leftOuterJoin(
              db.healthResults,
              db.healthResults.scanId.equalsExp(db.scanRecords.id),
            ),
          ])
          ..where(db.scanRecords.deletedAt.isNull())
          ..orderBy([OrderingTerm.desc(db.scanRecords.updatedAt)])
          ..limit(limit);

    return query.watch().map((rows) {
      return rows.map((row) {
        final weight = row.readTableOrNull(db.weightResults);
        final health = row.readTableOrNull(db.healthResults);
        return ScanWithPig(
          scan: row.readTable(db.scanRecords),
          pig: row.readTableOrNull(db.pigs),
          hasWeightValue: weight?.valueKg != null,
          hasEligibleHealth: health?.eligible ?? false,
        );
      }).toList();
    });
  }

  Future<LocalScanBundle?> loadScanBundle(String scanId) async {
    final scan = await (select(
      db.scanRecords,
    )..where((row) => row.id.equals(scanId))).getSingleOrNull();
    if (scan == null) return null;

    final pig = scan.pigId == null
        ? null
        : await (select(
            db.pigs,
          )..where((row) => row.id.equals(scan.pigId!))).getSingleOrNull();
    final reference = await (select(
      db.referenceAnnotations,
    )..where((row) => row.scanId.equals(scanId))).getSingleOrNull();
    final weight = await (select(
      db.weightResults,
    )..where((row) => row.scanId.equals(scanId))).getSingleOrNull();
    final health = await (select(
      db.healthResults,
    )..where((row) => row.scanId.equals(scanId))).getSingleOrNull();
    final viewEvent = await loadLatestEvent(scanId, 'view');

    return LocalScanBundle(
      scan: scan,
      pig: pig,
      reference: reference,
      weight: weight,
      health: health,
      viewEvent: viewEvent,
    );
  }

  /// Latest `PipelineEvent` for `scanId` at `stage` (e.g. `'view'`), or null if that stage
  /// has never run for this scan. `stage`'s events use `status` for the decided label
  /// (`dorsal_valid` | `health_only` | `reject`) and `message` for the confidence, set by
  /// RunAndPersistPipelineUseCase -- see TASKS.md's P0/P2 plan.
  Future<PipelineEvent?> loadLatestEvent(String scanId, String stage) {
    final query = select(db.pipelineEvents)
      ..where((row) => row.scanId.equals(scanId) & row.stage.equals(stage))
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Stream<List<PigSuggestion>> watchPigSuggestions(String query) {
    final trimmed = query.trim().toLowerCase();
    final selectQuery = select(db.pigs)..where((p) => p.deletedAt.isNull());
    return selectQuery.watch().map((rows) {
      final seen = <String>{};
      final result = <PigSuggestion>[];
      for (final p in rows) {
        final name = p.displayName?.trim() ?? '';
        final tag = p.tag?.trim() ?? '';
        final label = name.isNotEmpty
            ? name
            : (tag.isNotEmpty ? tag : 'Pig ${p.id}');
        if (trimmed.isNotEmpty && !label.toLowerCase().contains(trimmed)) {
          continue;
        }
        if (seen.add(label)) {
          result.add(PigSuggestion(displayName: label));
        }
      }
      return result;
    });
  }
}
