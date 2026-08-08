import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/analytics/data/analytics_dao.dart';
import '../models/scan_flow.dart';

part 'app_database.g.dart';

class Pigs extends Table {
  TextColumn get id => text()();
  TextColumn get tag => text().nullable().unique()();
  TextColumn get displayName => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ScanRecords extends Table {
  TextColumn get id => text()();
  TextColumn get pigId => text().nullable().references(Pigs, #id)();
  TextColumn get goal => text()();
  TextColumn get status =>
      text().withDefault(const Constant(ScanStatuses.draft))();
  TextColumn get imagePath => text().nullable()();
  TextColumn get failureCode => text().nullable()();
  TextColumn get failureMessage => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  TextColumn get remoteId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ReferenceAnnotations extends Table {
  TextColumn get scanId => text().references(ScanRecords, #id)();
  TextColumn get objectType => text()();
  TextColumn get objectName => text()();
  RealColumn get lengthCm => real()();
  RealColumn get startX => real().nullable()();
  RealColumn get startY => real().nullable()();
  RealColumn get endX => real().nullable()();
  RealColumn get endY => real().nullable()();
  RealColumn get pixelLength => real().nullable()();
  RealColumn get cmPerPixel => real().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  RealColumn get detectorConfidence => real().nullable()();
  BoolColumn get userConfirmed =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get sameFloorPlaneConfirmed =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {scanId};
}

class WeightResults extends Table {
  TextColumn get scanId => text().references(ScanRecords, #id)();
  BoolColumn get eligible => boolean()();
  RealColumn get valueKg => real().nullable()();
  RealColumn get referenceLengthCm => real().nullable()();
  RealColumn get referencePixelLength => real().nullable()();
  RealColumn get cmPerPixel => real().nullable()();
  RealColumn get featureRa => real().nullable()();
  RealColumn get featureLc => real().nullable()();
  RealColumn get featureBl => real().nullable()();
  RealColumn get featureBw => real().nullable()();
  RealColumn get featureE => real().nullable()();
  TextColumn get failureReason => text().nullable()();
  TextColumn get modelVersion => text().nullable()();
  TextColumn get preprocessingVersion => text().nullable()();
  TextColumn get thresholdVersion => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {scanId};
}

class HealthResults extends Table {
  TextColumn get scanId => text().references(ScanRecords, #id)();
  BoolColumn get eligible => boolean()();
  TextColumn get className => text().nullable()();
  RealColumn get confidence => real().nullable()();
  BoolColumn get uncertain => boolean().withDefault(const Constant(false))();
  TextColumn get failureReason => text().nullable()();
  TextColumn get modelVersion => text().nullable()();
  TextColumn get preprocessingVersion => text().nullable()();
  TextColumn get thresholdVersion => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {scanId};
}

class PipelineEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get scanId => text().references(ScanRecords, #id)();
  TextColumn get stage => text()();
  TextColumn get status => text()();
  TextColumn get message => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class PrivacyPreferences extends Table {
  IntColumn get id => integer()();
  BoolColumn get researchImageSharing =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get usageAnalytics =>
      boolean().withDefault(const Constant(false))();
  TextColumn get inferenceMode =>
      text().withDefault(const Constant('undecided'))();
  IntColumn get retentionDays => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncOutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class LocalScanBundle {
  final ScanRecord scan;
  final Pig? pig;
  final ReferenceAnnotation? reference;
  final WeightResult? weight;
  final HealthResult? health;

  const LocalScanBundle({
    required this.scan,
    this.pig,
    this.reference,
    this.weight,
    this.health,
  });
}

@DriftDatabase(
  tables: [
    Pigs,
    ScanRecords,
    ReferenceAnnotations,
    WeightResults,
    HealthResults,
    PipelineEvents,
    PrivacyPreferences,
    SyncOutboxEntries,
  ],
  daos: [AnalyticsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static final Random _random = Random.secure();

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await ensurePrivacyDefaults();
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'instaham',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.dart.js'),
      ),
    );
  }

  static String newLocalId(String prefix) {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = _random.nextInt(0x7fffffff).toRadixString(36);
    return '${prefix}_${timestamp}_$entropy';
  }

  Future<void> ensurePrivacyDefaults() async {
    final existing = await (select(
      privacyPreferences,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    if (existing == null) {
      await into(privacyPreferences).insert(
        PrivacyPreferencesCompanion(
          id: const Value(1),
          researchImageSharing: const Value(false),
          usageAnalytics: const Value(false),
          inferenceMode: const Value('undecided'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<String> createDraftScan({
    required ScanGoal goal,
    String? pigId,
  }) async {
    final id = newLocalId('scan');
    final now = DateTime.now();
    await into(scanRecords).insert(
      ScanRecordsCompanion(
        id: Value(id),
        pigId: Value(pigId),
        goal: Value(goal.storageValue),
        status: const Value(ScanStatuses.draft),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await addPipelineEvent(id, 'capture', 'started');
    return id;
  }

  Future<void> updateScanGoal(String scanId, ScanGoal goal) {
    return (update(scanRecords)..where((row) => row.id.equals(scanId))).write(
      ScanRecordsCompanion(
        goal: Value(goal.storageValue),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markCaptured(String scanId, {String? imagePath}) async {
    final now = DateTime.now();
    await (update(scanRecords)..where((row) => row.id.equals(scanId))).write(
      ScanRecordsCompanion(
        status: const Value(ScanStatuses.captured),
        imagePath: Value(imagePath),
        capturedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await addPipelineEvent(scanId, 'capture', 'completed');
  }

  Future<void> updateScanStatus(
    String scanId,
    String status, {
    String? failureCode,
    String? failureMessage,
  }) async {
    await (update(scanRecords)..where((row) => row.id.equals(scanId))).write(
      ScanRecordsCompanion(
        status: Value(status),
        failureCode: Value(failureCode),
        failureMessage: Value(failureMessage),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> saveReferenceAnnotation({
    required String scanId,
    required ReferenceSelection reference,
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    double? pixelLength,
    double? cmPerPixel,
    required String source,
    double? detectorConfidence,
    required bool sameFloorPlaneConfirmed,
  }) async {
    await into(referenceAnnotations).insertOnConflictUpdate(
      ReferenceAnnotationsCompanion(
        scanId: Value(scanId),
        objectType: Value(reference.type),
        objectName: Value(reference.name),
        lengthCm: Value(reference.lengthCm),
        startX: Value(startX),
        startY: Value(startY),
        endX: Value(endX),
        endY: Value(endY),
        pixelLength: Value(pixelLength),
        cmPerPixel: Value(cmPerPixel),
        source: Value(source),
        detectorConfidence: Value(detectorConfidence),
        userConfirmed: const Value(true),
        sameFloorPlaneConfirmed: Value(sameFloorPlaneConfirmed),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await updateScanStatus(scanId, ScanStatuses.analyzing);
    await addPipelineEvent(scanId, 'reference_review', 'completed');
  }

  Future<void> addPipelineEvent(
    String scanId,
    String stage,
    String status, {
    String? message,
  }) {
    return into(pipelineEvents).insert(
      PipelineEventsCompanion(
        scanId: Value(scanId),
        stage: Value(stage),
        status: Value(status),
        message: Value(message),
      ),
    );
  }

  Future<String> assignPig({
    required String scanId,
    required String tag,
    String? displayName,
  }) async {
    final normalizedTag = tag.trim();
    final existing = await (select(
      pigs,
    )..where((row) => row.tag.equals(normalizedTag))).getSingleOrNull();
    final pigId = existing?.id ?? newLocalId('pig');
    final now = DateTime.now();
    await into(pigs).insertOnConflictUpdate(
      PigsCompanion(
        id: Value(pigId),
        tag: Value(normalizedTag),
        displayName: Value(
          displayName?.trim().isEmpty == true ? null : displayName?.trim(),
        ),
        createdAt: Value(existing?.createdAt ?? now),
        updatedAt: Value(now),
      ),
    );
    await (update(scanRecords)..where((row) => row.id.equals(scanId))).write(
      ScanRecordsCompanion(pigId: Value(pigId), updatedAt: Value(now)),
    );
    return pigId;
  }

  Future<void> saveWeightResult({
    required String scanId,
    required bool eligible,
    double? valueKg,
    double? referenceLengthCm,
    double? referencePixelLength,
    double? cmPerPixel,
    double? ra,
    double? lc,
    double? bl,
    double? bw,
    double? e,
    String? failureReason,
    String? modelVersion,
    String? preprocessingVersion,
    String? thresholdVersion,
  }) async {
    await into(weightResults).insertOnConflictUpdate(
      WeightResultsCompanion(
        scanId: Value(scanId),
        eligible: Value(eligible),
        valueKg: Value(valueKg),
        referenceLengthCm: Value(referenceLengthCm),
        referencePixelLength: Value(referencePixelLength),
        cmPerPixel: Value(cmPerPixel),
        featureRa: Value(ra),
        featureLc: Value(lc),
        featureBl: Value(bl),
        featureBw: Value(bw),
        featureE: Value(e),
        failureReason: Value(failureReason),
        modelVersion: Value(modelVersion),
        preprocessingVersion: Value(preprocessingVersion),
        thresholdVersion: Value(thresholdVersion),
      ),
    );
    await addPipelineEvent(
      scanId,
      'weight',
      eligible ? 'completed' : 'blocked',
      message: failureReason,
    );
  }

  Future<void> saveHealthResult({
    required String scanId,
    required bool eligible,
    String? className,
    double? confidence,
    bool uncertain = false,
    String? failureReason,
    String? modelVersion,
    String? preprocessingVersion,
    String? thresholdVersion,
  }) async {
    await into(healthResults).insertOnConflictUpdate(
      HealthResultsCompanion(
        scanId: Value(scanId),
        eligible: Value(eligible),
        className: Value(className),
        confidence: Value(confidence),
        uncertain: Value(uncertain),
        failureReason: Value(failureReason),
        modelVersion: Value(modelVersion),
        preprocessingVersion: Value(preprocessingVersion),
        thresholdVersion: Value(thresholdVersion),
      ),
    );
    await addPipelineEvent(
      scanId,
      'health',
      eligible ? (uncertain ? 'uncertain' : 'completed') : 'blocked',
      message: failureReason,
    );
  }

  Future<String> insertSampleRecord() async {
    final scanId = await createDraftScan(goal: ScanGoal.weightAndHealth);
    await markCaptured(scanId, imagePath: null);
    await saveReferenceAnnotation(
      scanId: scanId,
      reference: ReferenceSelection.meterStick,
      startX: 0.1,
      startY: 0.25,
      endX: 0.9,
      endY: 0.25,
      pixelLength: 800,
      cmPerPixel: 0.125,
      source: 'manual',
      detectorConfidence: 0.95,
      sameFloorPlaneConfirmed: true,
    );
    await saveWeightResult(
      scanId: scanId,
      eligible: true,
      valueKg: 85.5,
      referenceLengthCm: 100.0,
      referencePixelLength: 800.0,
      cmPerPixel: 0.125,
      ra: 0.45,
      lc: 1.10,
      bl: 0.85,
      bw: 0.42,
      e: 0.78,
      modelVersion: 'xgb-weight-v1',
    );
    await saveHealthResult(
      scanId: scanId,
      eligible: true,
      className: 'Healthy',
      confidence: 0.94,
      modelVersion: 'mobilenet-health-v1',
    );
    await assignPig(
      scanId: scanId,
      tag: 'TAG-101',
      displayName: 'Sample Pig #101',
    );
    await updateScanStatus(scanId, ScanStatuses.completed);
    return scanId;
  }

  Stream<List<ScanRecord>> watchRecentScans({int limit = 100}) {
    final query = select(scanRecords)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
      ..limit(limit);
    return query.watch();
  }

  Future<LocalScanBundle?> loadScanBundle(String scanId) async {
    final scan = await (select(
      scanRecords,
    )..where((row) => row.id.equals(scanId))).getSingleOrNull();
    if (scan == null) return null;

    final pig = scan.pigId == null
        ? null
        : await (select(
            pigs,
          )..where((row) => row.id.equals(scan.pigId!))).getSingleOrNull();
    final reference = await (select(
      referenceAnnotations,
    )..where((row) => row.scanId.equals(scanId))).getSingleOrNull();
    final weight = await (select(
      weightResults,
    )..where((row) => row.scanId.equals(scanId))).getSingleOrNull();
    final health = await (select(
      healthResults,
    )..where((row) => row.scanId.equals(scanId))).getSingleOrNull();

    return LocalScanBundle(
      scan: scan,
      pig: pig,
      reference: reference,
      weight: weight,
      health: health,
    );
  }

  Future<PrivacyPreference> getPrivacyPreferences() async {
    await ensurePrivacyDefaults();
    return (select(
      privacyPreferences,
    )..where((row) => row.id.equals(1))).getSingle();
  }

  Future<void> savePrivacyPreferences({
    required bool researchImageSharing,
    required bool usageAnalytics,
    required String inferenceMode,
    int? retentionDays,
  }) {
    return into(privacyPreferences).insertOnConflictUpdate(
      PrivacyPreferencesCompanion(
        id: const Value(1),
        researchImageSharing: Value(researchImageSharing),
        usageAnalytics: Value(usageAnalytics),
        inferenceMode: Value(inferenceMode),
        retentionDays: Value(retentionDays),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteAllUserRecords() async {
    await transaction(() async {
      await delete(syncOutboxEntries).go();
      await delete(pipelineEvents).go();
      await delete(weightResults).go();
      await delete(healthResults).go();
      await delete(referenceAnnotations).go();
      await delete(scanRecords).go();
      await delete(pigs).go();
    });
  }

  Future<int> enqueueSync({
    required String entityType,
    required String entityId,
    required String operation,
    required String payloadJson,
  }) {
    return into(syncOutboxEntries).insert(
      SyncOutboxEntriesCompanion(
        entityType: Value(entityType),
        entityId: Value(entityId),
        operation: Value(operation),
        payloadJson: Value(payloadJson),
      ),
    );
  }
}
