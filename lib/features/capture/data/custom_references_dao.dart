import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

part 'custom_references_dao.g.dart';

@DriftAccessor(tables: [CustomReferences])
class CustomReferencesDao extends DatabaseAccessor<AppDatabase>
    with _$CustomReferencesDaoMixin {
  CustomReferencesDao(super.db);

  Future<List<CustomReference>> getAllCustomReferences() => (select(
    customReferences,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Stream<List<CustomReference>> watchAllCustomReferences() => (select(
    customReferences,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Future<int> addCustomReference(CustomReferencesCompanion entry) =>
      into(customReferences).insert(entry);
}
