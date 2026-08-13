import '../models/analytics_models.dart';

abstract interface class IAnalyticsRepository {
  Stream<WeightAnalytics> watchWeightAnalytics({
    DateTime? since,
    String? pigDisplayName,
  });
  Stream<HealthAnalytics> watchHealthAnalytics({
    DateTime? since,
    String? pigDisplayName,
  });
  Stream<List<WeightDataPoint>> watchWeightTimeSeries({
    DateTime? since,
    String? pigDisplayName,
  });
  Stream<List<HealthClassBar>> watchHealthClassBars({
    DateTime? since,
    String? pigDisplayName,
  });
  Stream<int> watchTotalScanRecords({DateTime? since, String? pigDisplayName});
  Stream<List<PigSuggestion>> watchPigSuggestions(String query);
}
