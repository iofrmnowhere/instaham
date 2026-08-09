import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class MockAnalyticsRepository implements IAnalyticsRepository {
  @override
  Stream<WeightAnalytics> watchWeightAnalytics({
    DateTime? since,
    String? pigId,
  }) => Stream.value(WeightAnalytics.empty());

  @override
  Stream<HealthAnalytics> watchHealthAnalytics({
    DateTime? since,
    String? pigId,
  }) => Stream.value(HealthAnalytics.empty());

  @override
  Stream<List<WeightDataPoint>> watchWeightTimeSeries({
    DateTime? since,
    String? pigId,
  }) => Stream.value([]);

  @override
  Stream<List<HealthClassBar>> watchHealthClassBars({
    DateTime? since,
    String? pigId,
  }) => Stream.value([]);

  @override
  Stream<int> watchTotalScanRecords({DateTime? since, String? pigId}) =>
      Stream.value(0);

  @override
  Stream<List<PigSuggestion>> watchPigSuggestions(String query) =>
      Stream.value([]);
}
