import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/analytics/data/analytics_dao.dart';

void main() {
  late AppDatabase database;
  late AnalyticsDao dao;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dao = database.analyticsDao;
  });

  tearDown(() => database.close());

  test(
    'watchWeightAnalytics computes stats and excludes soft-deleted scans',
    () async {
      final s1 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.saveWeightResult(
        scanId: s1,
        eligible: true,
        valueKg: 80.0,
      );

      final s2 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.saveWeightResult(
        scanId: s2,
        eligible: true,
        valueKg: 100.0,
      );

      final s3 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.saveWeightResult(
        scanId: s3,
        eligible: false,
        failureReason: 'Blocked',
      );

      // Soft-deleted scan
      final s4 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.saveWeightResult(
        scanId: s4,
        eligible: true,
        valueKg: 500.0,
      );
      await (database.update(database.scanRecords)
            ..where((row) => row.id.equals(s4)))
          .write(ScanRecordsCompanion(deletedAt: Value(DateTime.now())));

      final stats = await dao.watchWeightAnalytics().first;
      expect(stats.totalScans, 3);
      expect(stats.eligibleScans, 2);
      expect(stats.blockedScans, 1);
      expect(stats.averageKg, 90.0);
      expect(stats.minKg, 80.0);
      expect(stats.maxKg, 100.0);
    },
  );

  test(
    'watchHealthAnalytics aggregates classes, uncertain, and blocked counts',
    () async {
      final s1 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.saveHealthResult(
        scanId: s1,
        eligible: true,
        className: 'Healthy',
      );

      final s2 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.saveHealthResult(
        scanId: s2,
        eligible: true,
        className: 'Healthy',
      );

      final s3 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.saveHealthResult(
        scanId: s3,
        eligible: true,
        className: 'Sick',
        uncertain: true,
      );

      final s4 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.saveHealthResult(
        scanId: s4,
        eligible: false,
        failureReason: 'Blurry',
      );

      final stats = await dao.watchHealthAnalytics().first;
      expect(stats.totalScans, 4);
      expect(stats.eligibleScans, 3);
      expect(stats.uncertainScans, 1);
      expect(stats.blockedScans, 1);
      expect(stats.classCounts['Healthy'], 2);
      expect(stats.classCounts['Sick'], 1);
    },
  );

  test(
    'watchTotalScanRecords counts active non-deleted scan records',
    () async {
      await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.createDraftScan(goal: ScanGoal.weightAndHealth);

      final s3 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await (database.update(database.scanRecords)
            ..where((row) => row.id.equals(s3)))
          .write(ScanRecordsCompanion(deletedAt: Value(DateTime.now())));

      final count = await dao.watchTotalScanRecords().first;
      expect(count, 2);
    },
  );

  test(
    'watchWeightAnalytics filters by pigDisplayName across multiple pigs',
    () async {
      final s1 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.assignPig(scanId: s1, tag: 'TAG-1', displayName: 'Bella');
      await database.saveWeightResult(
        scanId: s1,
        eligible: true,
        valueKg: 80.0,
      );

      final s2 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.assignPig(scanId: s2, tag: 'TAG-2', displayName: 'Bella');
      await database.saveWeightResult(
        scanId: s2,
        eligible: true,
        valueKg: 100.0,
      );

      final s3 = await database.createDraftScan(goal: ScanGoal.weightAndHealth);
      await database.assignPig(scanId: s3, tag: 'TAG-3', displayName: 'Max');
      await database.saveWeightResult(
        scanId: s3,
        eligible: true,
        valueKg: 150.0,
      );

      final statsBella = await dao
          .watchWeightAnalytics(pigDisplayName: 'Bella')
          .first;
      expect(statsBella.totalScans, 2);
      expect(statsBella.averageKg, 90.0);

      final statsMax = await dao
          .watchWeightAnalytics(pigDisplayName: 'Max')
          .first;
      expect(statsMax.totalScans, 1);
      expect(statsMax.averageKg, 150.0);
    },
  );
}
