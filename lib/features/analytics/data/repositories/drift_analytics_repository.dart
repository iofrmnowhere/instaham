import '../analytics_dao.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class DriftAnalyticsRepository implements IAnalyticsRepository {
  final AnalyticsDao _dao;

  DriftAnalyticsRepository(this._dao);

  @override
  Stream<WeightAnalytics> watchWeightAnalytics() => _dao.watchWeightAnalytics();

  @override
  Stream<HealthAnalytics> watchHealthAnalytics() => _dao.watchHealthAnalytics();

  @override
  Stream<List<WeightDataPoint>> watchWeightTimeSeries() =>
      _dao.watchWeightTimeSeries();

  @override
  Stream<List<HealthClassBar>> watchHealthClassBars() =>
      _dao.watchHealthClassBars();
}
