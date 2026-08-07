import '../../../../core/database/app_database.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class DriftAnalyticsRepository implements IAnalyticsRepository {
  final AppDatabase _db;

  DriftAnalyticsRepository(this._db);

  @override
  Stream<WeightAnalytics> watchWeightAnalytics() => _db.watchWeightAnalytics();

  @override
  Stream<HealthAnalytics> watchHealthAnalytics() => _db.watchHealthAnalytics();

  @override
  Stream<List<WeightDataPoint>> watchWeightTimeSeries() =>
      _db.watchWeightTimeSeries();

  @override
  Stream<List<HealthClassBar>> watchHealthClassBars() =>
      _db.watchHealthClassBars();
}
