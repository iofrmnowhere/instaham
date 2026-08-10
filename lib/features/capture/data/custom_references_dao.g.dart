// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_references_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomReferencesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CustomReferencesTable get customReferences =>
      attachedDatabase.customReferences;
  CustomReferencesDaoManager get managers => CustomReferencesDaoManager(this);
}

class CustomReferencesDaoManager {
  final _$CustomReferencesDaoMixin _db;
  CustomReferencesDaoManager(this._db);
  $$CustomReferencesTableTableManager get customReferences =>
      $$CustomReferencesTableTableManager(
        _db.attachedDatabase,
        _db.customReferences,
      );
}
