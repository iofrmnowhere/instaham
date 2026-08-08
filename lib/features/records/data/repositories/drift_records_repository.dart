import '../../../../core/models/local_scan_bundle.dart';
import '../../../../core/models/scan_with_pig.dart';
import '../../domain/repositories/i_records_repository.dart';
import '../records_dao.dart';

class DriftRecordsRepository implements IRecordsRepository {
  final RecordsDao _dao;

  DriftRecordsRepository(this._dao);

  @override
  Stream<List<ScanWithPig>> watchRecentScans({int limit = 100}) =>
      _dao.watchRecentScans(limit: limit);

  @override
  Future<LocalScanBundle?> loadScanBundle(String scanId) =>
      _dao.loadScanBundle(scanId);
}
