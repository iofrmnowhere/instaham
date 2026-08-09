import '../analytics_dao.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class DriftAnalyticsRepository implements IAnalyticsRepository {
  final AnalyticsDao _dao;

  DriftAnalyticsRepository(this._dao);

  @override
  Stream<WeightAnalytics> watchWeightAnalytics({
    DateTime? since,
    String? pigId,
  }) => _dao.watchWeightAnalytics(since: since, pigId: pigId);

  @override
  Stream<HealthAnalytics> watchHealthAnalytics({
    DateTime? since,
    String? pigId,
  }) => _dao.watchHealthAnalytics(since: since, pigId: pigId);

  @override
  Stream<List<WeightDataPoint>> watchWeightTimeSeries({
    DateTime? since,
    String? pigId,
  }) => _dao.watchWeightTimeSeries(since: since, pigId: pigId);

  @override
  Stream<List<HealthClassBar>> watchHealthClassBars({
    DateTime? since,
    String? pigId,
  }) => _dao.watchHealthClassBars(since: since, pigId: pigId);

  @override
  Stream<int> watchTotalScanRecords({DateTime? since, String? pigId}) =>
      _dao.watchTotalScanRecords(since: since, pigId: pigId);

  @override
  Stream<List<PigSuggestion>> watchPigSuggestions(String query) =>
      _dao.watchPigSuggestions(query);
}
