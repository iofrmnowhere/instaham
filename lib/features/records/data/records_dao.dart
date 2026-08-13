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
    final query =
        select(db.scanRecords).join([
            leftOuterJoin(db.pigs, db.pigs.id.equalsExp(db.scanRecords.pigId)),
          ])
          ..where(db.scanRecords.deletedAt.isNull())
          ..orderBy([OrderingTerm.desc(db.scanRecords.updatedAt)])
          ..limit(limit);

    return query.watch().map((rows) {
      return rows.map((row) {
        return ScanWithPig(
          scan: row.readTable(db.scanRecords),
          pig: row.readTableOrNull(db.pigs),
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

    return LocalScanBundle(
      scan: scan,
      pig: pig,
      reference: reference,
      weight: weight,
      health: health,
    );
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
