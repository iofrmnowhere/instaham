import '../../database/app_database.dart';
import '../../domain/repositories/i_folders_repository.dart';
import '../../models/folder_pig.dart';
import '../../models/folder_summary.dart';
import '../folders_dao.dart';

class DriftFoldersRepository implements IFoldersRepository {
  final FoldersDao _dao;

  DriftFoldersRepository(this._dao);

  @override
  Stream<List<FolderSummary>> watchFolders() => _dao.watchFolders();

  @override
  Stream<List<FolderPig>> watchFolderPigs(String folderId) =>
      _dao.watchFolderPigs(folderId);

  @override
  Stream<List<Pig>> watchUngroupedPigs() => _dao.watchUngroupedPigs();

  @override
  Stream<String?> watchPigFolderId(String pigId) =>
      _dao.watchPigFolderId(pigId);

  @override
  Future<String> createFolder(String name) => _dao.createFolder(name);

  @override
  Future<void> renameFolder(String id, String name) =>
      _dao.renameFolder(id, name);

  @override
  Future<void> setPigFolder(String pigId, String? folderId) =>
      _dao.setPigFolder(pigId, folderId);

  @override
  Future<void> deleteFolder(String id, {required bool includeRecords}) =>
      _dao.deleteFolder(id, includeRecords: includeRecords);
}
