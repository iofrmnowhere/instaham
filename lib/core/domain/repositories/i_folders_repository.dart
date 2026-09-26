import '../../database/app_database.dart';
import '../../models/folder_pig.dart';
import '../../models/folder_summary.dart';

/// docs/plan-6.md (round 6, pig folders). Lives in lib/core/ so both the records feature
/// (folder screens) and the results feature (folder picker) can depend on it without
/// importing each other.
abstract interface class IFoldersRepository {
  Stream<List<FolderSummary>> watchFolders();
  Stream<List<FolderPig>> watchFolderPigs(String folderId);
  Stream<List<Pig>> watchUngroupedPigs();
  Stream<String?> watchPigFolderId(String pigId);
  Future<String> createFolder(String name);
  Future<void> renameFolder(String id, String name);
  Future<void> setPigFolder(String pigId, String? folderId);
  Future<void> deleteFolder(String id, {required bool includeRecords});
}
