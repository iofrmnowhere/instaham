import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/records/data/records_dao.dart';

void main() {
  late AppDatabase database;
  late RecordsDao dao;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dao = database.recordsDao;
  });

  tearDown(() => database.close());

  test(
    'watchRecentScans excludes soft-deleted records and orders by updatedAt desc',
    () async {
      final s1 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      final s2 = await database.createDraftScan(goal: ScanGoal.healthOnly);
      final s3 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);

      // Soft delete s2
      await (database.update(database.scanRecords)
            ..where((row) => row.id.equals(s2)))
          .write(ScanRecordsCompanion(deletedAt: Value(DateTime.now())));

      final scans = await dao.watchRecentScans().first;
      expect(scans.length, 2);
      expect(scans.map((item) => item.scan.id), containsAll([s1, s3]));
      expect(scans.any((item) => item.scan.id == s2), isFalse);
    },
  );

  test('watchRecentScans respects limit', () async {
    for (var i = 0; i < 5; i++) {
      await database.createDraftScan(goal: ScanGoal.healthOnly);
    }

    final scans = await dao.watchRecentScans(limit: 3).first;
    expect(scans.length, 3);
  });

  test('loadScanBundle returns null for non-existent scan', () async {
    final bundle = await dao.loadScanBundle('non-existent-id');
    expect(bundle, isNull);
  });

  test('loadScanBundle returns complete bundle for valid scan', () async {
    final scanId = await database.insertSampleRecord();
    final bundle = await dao.loadScanBundle(scanId);

    expect(bundle, isNotNull);
    expect(bundle!.scan.id, scanId);
    expect(
      bundle.scan.status,
      isIn([ScanStatuses.completed, ScanStatuses.blocked]),
    );
    expect(bundle.pig?.tag, startsWith('TAG-'));
    expect(bundle.health?.className, isNotNull);
    expect(bundle.reference, isNotNull);
  });
}
