import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/models/local_scan_bundle.dart';

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

  Stream<List<ScanRecord>> watchRecentScans({int limit = 100}) {
    final query = select(db.scanRecords)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
      ..limit(limit);
    return query.watch();
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
}
