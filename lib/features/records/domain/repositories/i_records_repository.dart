import '../../../../core/database/app_database.dart';
import '../../../../core/models/local_scan_bundle.dart';

abstract interface class IRecordsRepository {
  Stream<List<ScanRecord>> watchRecentScans({int limit = 100});
  Future<LocalScanBundle?> loadScanBundle(String scanId);
}
