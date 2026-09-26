// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analytics_dao.dart';

// ignore_for_file: type=lint
mixin _$AnalyticsDaoMixin on DatabaseAccessor<AppDatabase> {
  $PigFoldersTable get pigFolders => attachedDatabase.pigFolders;
  $PigsTable get pigs => attachedDatabase.pigs;
  $ScanRecordsTable get scanRecords => attachedDatabase.scanRecords;
  $WeightResultsTable get weightResults => attachedDatabase.weightResults;
  $HealthResultsTable get healthResults => attachedDatabase.healthResults;
  AnalyticsDaoManager get managers => AnalyticsDaoManager(this);
}

class AnalyticsDaoManager {
  final _$AnalyticsDaoMixin _db;
  AnalyticsDaoManager(this._db);
  $$PigFoldersTableTableManager get pigFolders =>
      $$PigFoldersTableTableManager(_db.attachedDatabase, _db.pigFolders);
  $$PigsTableTableManager get pigs =>
      $$PigsTableTableManager(_db.attachedDatabase, _db.pigs);
  $$ScanRecordsTableTableManager get scanRecords =>
      $$ScanRecordsTableTableManager(_db.attachedDatabase, _db.scanRecords);
  $$WeightResultsTableTableManager get weightResults =>
      $$WeightResultsTableTableManager(_db.attachedDatabase, _db.weightResults);
  $$HealthResultsTableTableManager get healthResults =>
      $$HealthResultsTableTableManager(_db.attachedDatabase, _db.healthResults);
}
