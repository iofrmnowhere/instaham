// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'records_dao.dart';

// ignore_for_file: type=lint
mixin _$RecordsDaoMixin on DatabaseAccessor<AppDatabase> {
  $PigFoldersTable get pigFolders => attachedDatabase.pigFolders;
  $PigsTable get pigs => attachedDatabase.pigs;
  $ScanRecordsTable get scanRecords => attachedDatabase.scanRecords;
  $ReferenceAnnotationsTable get referenceAnnotations =>
      attachedDatabase.referenceAnnotations;
  $WeightResultsTable get weightResults => attachedDatabase.weightResults;
  $HealthResultsTable get healthResults => attachedDatabase.healthResults;
  RecordsDaoManager get managers => RecordsDaoManager(this);
}

class RecordsDaoManager {
  final _$RecordsDaoMixin _db;
  RecordsDaoManager(this._db);
  $$PigFoldersTableTableManager get pigFolders =>
      $$PigFoldersTableTableManager(_db.attachedDatabase, _db.pigFolders);
  $$PigsTableTableManager get pigs =>
      $$PigsTableTableManager(_db.attachedDatabase, _db.pigs);
  $$ScanRecordsTableTableManager get scanRecords =>
      $$ScanRecordsTableTableManager(_db.attachedDatabase, _db.scanRecords);
  $$ReferenceAnnotationsTableTableManager get referenceAnnotations =>
      $$ReferenceAnnotationsTableTableManager(
        _db.attachedDatabase,
        _db.referenceAnnotations,
      );
  $$WeightResultsTableTableManager get weightResults =>
      $$WeightResultsTableTableManager(_db.attachedDatabase, _db.weightResults);
  $$HealthResultsTableTableManager get healthResults =>
      $$HealthResultsTableTableManager(_db.attachedDatabase, _db.healthResults);
}
