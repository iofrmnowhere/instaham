import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class MockAnalyticsRepository implements IAnalyticsRepository {
  @override
  Stream<WeightAnalytics> watchWeightAnalytics() =>
      Stream.value(WeightAnalytics.empty());

  @override
  Stream<HealthAnalytics> watchHealthAnalytics() =>
      Stream.value(HealthAnalytics.empty());

  @override
  Stream<List<WeightDataPoint>> watchWeightTimeSeries() => Stream.value([]);

  @override
  Stream<List<HealthClassBar>> watchHealthClassBars() => Stream.value([]);
}
