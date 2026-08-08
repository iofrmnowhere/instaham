import '../../../../core/models/local_scan_bundle.dart';
import '../../../../core/models/scan_with_pig.dart';

abstract interface class IRecordsRepository {
  Stream<List<ScanWithPig>> watchRecentScans({int limit = 100});
  Future<LocalScanBundle?> loadScanBundle(String scanId);
}
