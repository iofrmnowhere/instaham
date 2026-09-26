export '../../../../core/models/pig_suggestion.dart';

class WeightAnalytics {
  final int totalScans;
  final int eligibleScans;

  /// Weight-ineligible scans whose health branch also failed. docs/fix-7.md F73.
  final int blockedScans;

  /// Weight-ineligible scans whose health branch succeeded. docs/fix-7.md F73: these are
  /// "Health only" rather than "Blocked".
  final int healthOnlyScans;
  final double? averageKg;
  final double? minKg;
  final double? maxKg;

  const WeightAnalytics({
    required this.totalScans,
    required this.eligibleScans,
    required this.blockedScans,
    this.healthOnlyScans = 0,
    this.averageKg,
    this.minKg,
    this.maxKg,
  });

  factory WeightAnalytics.empty() => const WeightAnalytics(
    totalScans: 0,
    eligibleScans: 0,
    blockedScans: 0,
    healthOnlyScans: 0,
  );
}

class HealthAnalytics {
  final int totalScans;
  final int eligibleScans;
  final int uncertainScans;

  /// Scans where the health branch failed *and* the weight branch also failed. docs/fix-7.md
  /// F73's both-failed rule: a health-ineligible scan whose weight branch succeeded is not
  /// counted here, since that scan is not the sort of "Blocked" result F73 is about.
  final int blockedScans;
  final Map<String, int> classCounts;

  const HealthAnalytics({
    required this.totalScans,
    required this.eligibleScans,
    required this.uncertainScans,
    required this.blockedScans,
    required this.classCounts,
  });

  factory HealthAnalytics.empty() => const HealthAnalytics(
    totalScans: 0,
    eligibleScans: 0,
    uncertainScans: 0,
    blockedScans: 0,
    classCounts: {},
  );
}

class WeightDataPoint {
  final DateTime date;
  final double kg;

  const WeightDataPoint({required this.date, required this.kg});
}

class HealthClassBar {
  final String className;
  final double percentage;

  const HealthClassBar({required this.className, required this.percentage});
}

enum AnalyticsDateFilter { allTime, thisMonth, thisWeek }
