import 'package:drift/drift.dart';
import 'dart:math';

import '../../../../core/database/app_database.dart';
import '../domain/models/analytics_models.dart';

part 'analytics_dao.g.dart';

@DriftAccessor(tables: [WeightResults, HealthResults, ScanRecords])
class AnalyticsDao extends DatabaseAccessor<AppDatabase>
    with _$AnalyticsDaoMixin {
  AnalyticsDao(super.db);

  Stream<WeightAnalytics> watchWeightAnalytics() {
    final query = select(db.weightResults).join([
      innerJoin(
        db.scanRecords,
        db.scanRecords.id.equalsExp(db.weightResults.scanId),
      ),
    ])..where(db.scanRecords.deletedAt.isNull());

    return query.watch().map((rows) {
      final results = rows
          .map((row) => row.readTable(db.weightResults))
          .toList();
      if (results.isEmpty) return WeightAnalytics.empty();

      final totalScans = results.length;
      final eligibleRows = results.where((r) => r.eligible).toList();
      final eligibleScans = eligibleRows.length;
      final blockedScans = totalScans - eligibleScans;

      if (eligibleRows.isEmpty) {
        return WeightAnalytics(
          totalScans: totalScans,
          eligibleScans: 0,
          blockedScans: blockedScans,
        );
      }

      final values = eligibleRows
          .map((r) => r.valueKg)
          .whereType<double>()
          .toList();

      if (values.isEmpty) {
        return WeightAnalytics(
          totalScans: totalScans,
          eligibleScans: eligibleScans,
          blockedScans: blockedScans,
        );
      }

      final sum = values.reduce((a, b) => a + b);
      final avg = sum / values.length;
      final minVal = values.reduce(min);
      final maxVal = values.reduce(max);

      return WeightAnalytics(
        totalScans: totalScans,
        eligibleScans: eligibleScans,
        blockedScans: blockedScans,
        averageKg: avg,
        minKg: minVal,
        maxKg: maxVal,
      );
    });
  }

  Stream<HealthAnalytics> watchHealthAnalytics() {
    final query = select(db.healthResults).join([
      innerJoin(
        db.scanRecords,
        db.scanRecords.id.equalsExp(db.healthResults.scanId),
      ),
    ])..where(db.scanRecords.deletedAt.isNull());

    return query.watch().map((rows) {
      final results = rows
          .map((row) => row.readTable(db.healthResults))
          .toList();
      if (results.isEmpty) return HealthAnalytics.empty();

      final totalScans = results.length;
      int eligibleScans = 0;
      int uncertainScans = 0;
      int blockedScans = 0;
      final Map<String, int> classCounts = {};

      for (final r in results) {
        if (!r.eligible) {
          blockedScans++;
        } else {
          eligibleScans++;
          if (r.uncertain) {
            uncertainScans++;
          }
          final name = r.className?.trim();
          if (name != null && name.isNotEmpty) {
            classCounts[name] = (classCounts[name] ?? 0) + 1;
          }
        }
      }

      return HealthAnalytics(
        totalScans: totalScans,
        eligibleScans: eligibleScans,
        uncertainScans: uncertainScans,
        blockedScans: blockedScans,
        classCounts: classCounts,
      );
    });
  }

  Stream<List<WeightDataPoint>> watchWeightTimeSeries() {
    final query =
        select(db.weightResults).join([
            innerJoin(
              db.scanRecords,
              db.scanRecords.id.equalsExp(db.weightResults.scanId),
            ),
          ])
          ..where(
            db.scanRecords.deletedAt.isNull() &
                db.weightResults.eligible.equals(true),
          )
          ..orderBy([OrderingTerm.asc(db.weightResults.createdAt)]);

    return query.watch().map((rows) {
      return rows
          .map((row) {
            final w = row.readTable(db.weightResults);
            if (w.valueKg == null) return null;
            return WeightDataPoint(date: w.createdAt, kg: w.valueKg!);
          })
          .whereType<WeightDataPoint>()
          .toList();
    });
  }

  Stream<List<HealthClassBar>> watchHealthClassBars() {
    final query =
        select(db.healthResults).join([
          innerJoin(
            db.scanRecords,
            db.scanRecords.id.equalsExp(db.healthResults.scanId),
          ),
        ])..where(
          db.scanRecords.deletedAt.isNull() &
              db.healthResults.eligible.equals(true),
        );

    return query.watch().map((rows) {
      final results = rows
          .map((row) => row.readTable(db.healthResults))
          .toList();
      if (results.isEmpty) return <HealthClassBar>[];

      final totalEligible = results.length;
      final Map<String, int> counts = {};

      for (final r in results) {
        final name = r.className?.trim();
        if (name != null && name.isNotEmpty) {
          counts[name] = (counts[name] ?? 0) + 1;
        }
      }

      return counts.entries.map((entry) {
        final percentage = (entry.value / totalEligible) * 100.0;
        return HealthClassBar(className: entry.key, percentage: percentage);
      }).toList();
    });
  }
}
