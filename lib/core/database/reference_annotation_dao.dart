import 'app_database.dart';

/// TASKS.md W2: reads back the reference-object annotation `reference_marking_screen.dart`
/// (weight_estimation feature) persists via `AppDatabase.saveReferenceAnnotation`. Nothing
/// read this table before -- `cmPerPixel` was computed, stored, and never looked at again.
///
/// Lives in `core/database/` rather than under a feature's `data/` directory because its
/// only caller, `RunAndPersistPipelineUseCase`, is in the `inference_pipeline` feature:
/// AGENTS.md's "features must not import other feature modules directly" rules out a
/// `weight_estimation`-owned DAO here, and this class touches only `AppDatabase`'s own
/// table getter (no new `@DriftAccessor` mixin, so no `build_runner` generation needed).
class ReferenceAnnotationDao {
  final AppDatabase _db;

  const ReferenceAnnotationDao(this._db);

  /// Returns the confirmed reference annotation for `scanId`, or null if the user never
  /// marked one (or it predates this feature). `ReferenceAnnotations.scanId` is the
  /// primary key (app_database.dart), so this is at most one row.
  Future<ReferenceAnnotation?> getReferenceAnnotation(String scanId) {
    return (_db.select(
      _db.referenceAnnotations,
    )..where((row) => row.scanId.equals(scanId))).getSingleOrNull();
  }
}
