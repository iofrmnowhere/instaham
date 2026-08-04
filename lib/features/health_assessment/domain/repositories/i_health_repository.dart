abstract interface class IHealthRepository {
  Future<List<Map<String, dynamic>>> getHistory();
}
