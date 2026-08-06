class WeightAnalytics {
  final int totalScans;
  final int eligibleScans;
  final int blockedScans;
  final double? averageKg;
  final double? minKg;
  final double? maxKg;

  const WeightAnalytics({
    required this.totalScans,
    required this.eligibleScans,
    required this.blockedScans,
    this.averageKg,
    this.minKg,
    this.maxKg,
  });

  factory WeightAnalytics.empty() =>
      const WeightAnalytics(totalScans: 0, eligibleScans: 0, blockedScans: 0);
}

class HealthAnalytics {
  final int totalScans;
  final int eligibleScans;
  final int uncertainScans;
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
