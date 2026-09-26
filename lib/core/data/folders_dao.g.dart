// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folders_dao.dart';

// ignore_for_file: type=lint
mixin _$FoldersDaoMixin on DatabaseAccessor<AppDatabase> {
  $PigFoldersTable get pigFolders => attachedDatabase.pigFolders;
  $PigsTable get pigs => attachedDatabase.pigs;
  $ScanRecordsTable get scanRecords => attachedDatabase.scanRecords;
  $WeightResultsTable get weightResults => attachedDatabase.weightResults;
  FoldersDaoManager get managers => FoldersDaoManager(this);
}

class FoldersDaoManager {
  final _$FoldersDaoMixin _db;
  FoldersDaoManager(this._db);
  $$PigFoldersTableTableManager get pigFolders =>
      $$PigFoldersTableTableManager(_db.attachedDatabase, _db.pigFolders);
  $$PigsTableTableManager get pigs =>
      $$PigsTableTableManager(_db.attachedDatabase, _db.pigs);
  $$ScanRecordsTableTableManager get scanRecords =>
      $$ScanRecordsTableTableManager(_db.attachedDatabase, _db.scanRecords);
  $$WeightResultsTableTableManager get weightResults =>
      $$WeightResultsTableTableManager(_db.attachedDatabase, _db.weightResults);
}
