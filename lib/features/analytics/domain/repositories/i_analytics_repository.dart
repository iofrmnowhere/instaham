import '../models/analytics_models.dart';

abstract interface class IAnalyticsRepository {
  Stream<WeightAnalytics> watchWeightAnalytics({
    DateTime? since,
    String? pigId,
  });
  Stream<HealthAnalytics> watchHealthAnalytics({
    DateTime? since,
    String? pigId,
  });
  Stream<List<WeightDataPoint>> watchWeightTimeSeries({
    DateTime? since,
    String? pigId,
  });
  Stream<List<HealthClassBar>> watchHealthClassBars({
    DateTime? since,
    String? pigId,
  });
  Stream<int> watchTotalScanRecords({DateTime? since, String? pigId});
  Stream<List<PigSuggestion>> watchPigSuggestions(String query);
}
