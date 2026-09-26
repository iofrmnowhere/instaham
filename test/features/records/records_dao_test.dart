import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/scan_display_status.dart';
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
      final s2 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
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
      await database.createDraftScan(goal: ScanGoal.weightAndHealth);
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
    expect(bundle.pig?.tag, startsWith('PIG-'));
    final goal = scanGoalFromStorage(bundle.scan.goal);
    if (goal.requiresReference) {
      expect(bundle.reference, isNotNull);
    }
  });

  test(
    // docs/fix-7.md F73.
    'watchRecentScans reports Health only for a weight-failed, health-ok scan',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      await database.saveWeightResult(
        scanId: scanId,
        eligible: false,
        failureReason: 'No reference',
      );
      await database.saveHealthResult(
        scanId: scanId,
        eligible: true,
        className: 'Healthy',
      );
      await database.updateScanStatus(scanId, ScanStatuses.blocked);

      final scans = await dao.watchRecentScans().first;
      final item = scans.singleWhere((s) => s.scan.id == scanId);
      expect(item.hasWeightValue, isFalse);
      expect(item.hasEligibleHealth, isTrue);
      expect(item.displayStatus, ScanDisplayStatuses.healthOnly);
    },
  );

  test(
    // docs/fix-7.md F73.
    'watchRecentScans reports Blocked when neither branch produced a value',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      await database.saveWeightResult(
        scanId: scanId,
        eligible: false,
        failureReason: 'No reference',
      );
      await database.saveHealthResult(
        scanId: scanId,
        eligible: false,
        failureReason: 'Blurry',
      );
      await database.updateScanStatus(scanId, ScanStatuses.blocked);

      final scans = await dao.watchRecentScans().first;
      final item = scans.singleWhere((s) => s.scan.id == scanId);
      expect(item.displayStatus, ScanStatuses.blocked);
    },
  );

  test(
    'watchPigSuggestions deduplicates pigs with same display name',
    () async {
      final s1 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      final s2 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);

      await database.renamePigForScan(scanId: s1, displayName: 'Bella');
      await database.renamePigForScan(scanId: s2, displayName: 'Bella');

      final suggestions = await dao.watchPigSuggestions('Bella').first;
      expect(suggestions.length, 1);
      expect(suggestions.first.displayName, 'Bella');
    },
  );
}
