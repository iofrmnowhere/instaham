import '../analytics_dao.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class DriftAnalyticsRepository implements IAnalyticsRepository {
  final AnalyticsDao _dao;

  DriftAnalyticsRepository(this._dao);

  @override
  Stream<WeightAnalytics> watchWeightAnalytics({
    DateTime? since,
    String? pigDisplayName,
  }) => _dao.watchWeightAnalytics(since: since, pigDisplayName: pigDisplayName);

  @override
  Stream<HealthAnalytics> watchHealthAnalytics({
    DateTime? since,
    String? pigDisplayName,
  }) => _dao.watchHealthAnalytics(since: since, pigDisplayName: pigDisplayName);

  @override
  Stream<List<WeightDataPoint>> watchWeightTimeSeries({
    DateTime? since,
    String? pigDisplayName,
  }) =>
      _dao.watchWeightTimeSeries(since: since, pigDisplayName: pigDisplayName);

  @override
  Stream<List<HealthClassBar>> watchHealthClassBars({
    DateTime? since,
    String? pigDisplayName,
  }) => _dao.watchHealthClassBars(since: since, pigDisplayName: pigDisplayName);

  @override
  Stream<int> watchTotalScanRecords({
    DateTime? since,
    String? pigDisplayName,
  }) =>
      _dao.watchTotalScanRecords(since: since, pigDisplayName: pigDisplayName);

  @override
  Stream<List<PigSuggestion>> watchPigSuggestions(String query) =>
      _dao.watchPigSuggestions(query);
}
