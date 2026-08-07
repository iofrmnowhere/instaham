import '../models/analytics_models.dart';

abstract interface class IAnalyticsRepository {
  Stream<WeightAnalytics> watchWeightAnalytics();
  Stream<HealthAnalytics> watchHealthAnalytics();
}
