import '../../domain/repositories/i_analytics_repository.dart';

class MockAnalyticsRepository implements IAnalyticsRepository {
  @override
  Future<Map<String, dynamic>> getAnalytics() async {
    return {};
  }
}
