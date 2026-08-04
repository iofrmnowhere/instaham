import '../../domain/repositories/i_health_repository.dart';

class MockHealthRepository implements IHealthRepository {
  @override
  Future<List<Map<String, dynamic>>> getHistory() async {
    // Empty list to display the empty state from app/health/page.tsx
    return [];
  }
}
