import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/analytics/data/analytics_dao.dart';
import '../../features/capture/data/custom_references_dao.dart';
import '../../features/records/data/records_dao.dart';
import '../data/folders_dao.dart';
import '../models/capture_orientation.dart';
import '../models/measurement_mode.dart';
import '../models/scan_flow.dart';

part 'app_database.g.dart';

class Pigs extends Table {
  TextColumn get id => text()();
  TextColumn get tag => text().nullable().unique()();
  TextColumn get displayName => text().nullable()();
  // docs/plan-6.md (round 6, pig folders): null means the pig is ungrouped. No sync
  // behaviour is added by this column.
  TextColumn get folderId => text().nullable().references(PigFolders, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// docs/plan-6.md (round 6, pig folders): user-created groupings of pigs. The app never
// creates one on its own. `remoteId` is nullable per the "stable local IDs, separate
// remote IDs" rule, though no sync behaviour is added here.
class PigFolders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get remoteId => text().nullable()();

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
  TextColumn get measurementMode => text().nullable()();
  RealColumn get cameraHeightCm => real().nullable()();
  // docs/fix-phase-4/6-capture-orientation.md: 'portrait' | 'landscape', the orientation the
  // capture reached the segmenter in, and whether the user attested to the pig's head facing
  // the direction that orientation requires. The app cannot verify head direction itself (no
  // head detector; README §4 forbids adding one at preprocessing), so this is instruction and
  // attestation, recorded here so a wrong-looking mask can be checked against what the user
  // declared.
  TextColumn get captureOrientation => text().nullable()();
  BoolColumn get headOrientationAttested =>
      boolean().withDefault(const Constant(false))();
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
  // DEPRECATED (docs/plan-phase/4-dart-persistence-ui.md): the weight regressor moved from
  // the 5-feature baseline5 family to the 16-feature chen16_noheight family. These five
  // columns are no longer written -- the feature vector now lands in [featureVector] as a
  // family-tagged JSON blob so a future feature-family change needs no migration. They are
  // KEPT, not dropped, because they still hold real field measurements from scans taken
  // before schemaVersion 4 (the history docs/fix-phase/6-device-telemetry-findings.md was
  // built from).
  RealColumn get featureRa => real().nullable()();
  RealColumn get featureLc => real().nullable()();
  RealColumn get featureBl => real().nullable()();
  RealColumn get featureBw => real().nullable()();
  RealColumn get featureE => real().nullable()();
  // Whole envelope `features` block verbatim: {"family": "...", "values": {name: value}}.
  TextColumn get featureVector => text().nullable()();
  // Queryable discriminator ("baseline5" | "chen16_noheight") so an export/analytics query
  // can filter by family without parsing every blob.
  TextColumn get featureFamily => text().nullable()();
  // Cutter telemetry (docs/plan-phase/3-manifest-pipeline.md): post-cut / pre-cut mask area
  // ratio, median ~0.95 on training rows. TELEMETRY ONLY -- nothing in the Dart layer may
  // branch on it and it must not reach the UI.
  RealColumn get cutterKeptFraction => real().nullable()();
  TextColumn get cutterStatus => text().nullable()();
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
  // docs/fix-phase-5/1-view-verdict-cache.md (F66): sha256 of the image bytes this event
  // classified, so a cached 'view' event can be checked against the image it is about to
  // be reused for, instead of being trusted for any image the scan happens to hold at
  // read time. Null for events written before this column existed, and for stages that
  // are not per-image (resolveViewGate treats a null identity as a mismatch, never as a
  // wildcard).
  TextColumn get imageIdentity => text().nullable()();
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

class CustomReferences extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get lengthCm => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Pigs,
    PigFolders,
    ScanRecords,
    ReferenceAnnotations,
    WeightResults,
    HealthResults,
    PipelineEvents,
    PrivacyPreferences,
    SyncOutboxEntries,
    CustomReferences,
  ],
  daos: [AnalyticsDao, RecordsDao, CustomReferencesDao, FoldersDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static final Random _random = Random.secure();

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(customReferences);
      }
      if (from < 3) {
        await migrator.addColumn(scanRecords, scanRecords.measurementMode);
        await migrator.addColumn(scanRecords, scanRecords.cameraHeightCm);
      }
      if (from < 4) {
        // docs/plan-phase/4-dart-persistence-ui.md: 16-feature weight vector as a JSON
        // blob plus a queryable family discriminator, and two cutter-telemetry columns.
        // All nullable additions -- no backfill; featureRa..featureE keep their old values.
        await migrator.addColumn(weightResults, weightResults.featureVector);
        await migrator.addColumn(weightResults, weightResults.featureFamily);
        await migrator.addColumn(
          weightResults,
          weightResults.cutterKeptFraction,
        );
        await migrator.addColumn(weightResults, weightResults.cutterStatus);
      }
      if (from < 5) {
        // docs/fix-phase-4/6-capture-orientation.md: nullable/defaulted additions -- no
        // backfill; scans captured before this phase keep no orientation/attestation.
        await migrator.addColumn(scanRecords, scanRecords.captureOrientation);
        await migrator.addColumn(
          scanRecords,
          scanRecords.headOrientationAttested,
        );
      }
      if (from < 6) {
        // docs/fix-phase-5/1-view-verdict-cache.md (F66): nullable addition -- no
        // backfill. Events written before this column existed carry no image identity,
        // so resolveViewGate treats them as a mismatch and re-classifies rather than
        // trusting a verdict it cannot attribute to an image.
        await migrator.addColumn(pipelineEvents, pipelineEvents.imageIdentity);
      }
      if (from < 7) {
        // docs/plan-6.md (round 6, pig folders): new table plus a nullable FK column on
        // pigs. No backfill -- every existing pig starts ungrouped.
        await migrator.createTable(pigFolders);
        await migrator.addColumn(pigs, pigs.folderId);
      }
      if (from < 8) {
        // docs/fix-8.md F74: no structural change (no new table/column) -- every scan gets
        // its own pig from here on, so this step only reshapes existing data: give every
        // pigless scan a new auto-ID pig, then split any pig still shared by more than one
        // scan so each scan ends up with exactly one pig.
        await _splitPigsOneScanEach();
      }
    },
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
    // docs/fix-8.md F74: a scan is its own pig -- callers no longer type a tag, so one is
    // generated here unless the caller already gave an existing pig to attach to (as the
    // pig-folders "add pigs" flow does).
    if (pigId == null) {
      await _createPigAndAssign(scanId: id, createdAt: now);
    }
    await addPipelineEvent(id, 'capture', 'started');
    return id;
  }

  /// docs/fix-8.md F74: the next unused `PIG-####` number, scanning every pig's tag
  /// (including soft-deleted ones, which are never filtered out here) so a number already
  /// on a row is never reused.
  Future<int> _nextPigNumber() async {
    final rows = await (select(
      pigs,
    )..where((row) => row.tag.like('PIG-%'))).get();
    var maxNumber = 0;
    final pattern = RegExp(r'^PIG-(\d+)$');
    for (final row in rows) {
      final match = pattern.firstMatch(row.tag ?? '');
      if (match == null) continue;
      final number = int.tryParse(match.group(1)!) ?? 0;
      if (number > maxNumber) maxNumber = number;
    }
    return maxNumber + 1;
  }

  Future<String> _generatePigTag() async {
    final number = await _nextPigNumber();
    return 'PIG-${number.toString().padLeft(4, '0')}';
  }

  /// docs/fix-8.md F74: creates a new pig with an auto-generated tag and attaches it to
  /// `scanId`. `displayName`/`folderId` let the v7->v8 migration carry over an existing
  /// pig's name and folder when it splits that pig across its other scans.
  Future<String> _createPigAndAssign({
    required String scanId,
    String? displayName,
    String? folderId,
    DateTime? createdAt,
  }) async {
    final pigId = newLocalId('pig');
    final tag = await _generatePigTag();
    final now = createdAt ?? DateTime.now();
    await into(pigs).insert(
      PigsCompanion.insert(
        id: pigId,
        tag: Value(tag),
        displayName: Value(displayName),
        folderId: Value(folderId),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await (update(scanRecords)..where((row) => row.id.equals(scanId))).write(
      ScanRecordsCompanion(pigId: Value(pigId)),
    );
    return pigId;
  }

  /// docs/fix-8.md F74, schemaVersion 7 -> 8 data step: every scan ends up with its own
  /// pig. First, every scan with no pig gets a new one. Then, for every pig still shared by
  /// more than one scan, its oldest scan (by `capturedAt`, falling back to `createdAt` --
  /// same rule plan-6.md uses for "latest eligible weight") keeps the pig, and every other
  /// scan of that pig gets a new pig that copies its display name and folder, so folder
  /// membership survives the split.
  Future<void> _splitPigsOneScanEach() async {
    final pigless = await (select(
      scanRecords,
    )..where((row) => row.pigId.isNull())).get();
    for (final scan in pigless) {
      await _createPigAndAssign(scanId: scan.id, createdAt: scan.createdAt);
    }

    final allPigs = await select(pigs).get();
    for (final pig in allPigs) {
      final scansForPig =
          await (select(
              scanRecords,
            )..where((row) => row.pigId.equals(pig.id))).get()
            ..sort((a, b) {
              final aTime = a.capturedAt ?? a.createdAt;
              final bTime = b.capturedAt ?? b.createdAt;
              return aTime.compareTo(bTime);
            });
      if (scansForPig.length <= 1) continue;
      for (final scan in scansForPig.skip(1)) {
        await _createPigAndAssign(
          scanId: scan.id,
          displayName: pig.displayName,
          folderId: pig.folderId,
          createdAt: scan.createdAt,
        );
      }
    }
  }

  Future<void> markCaptured(
    String scanId, {
    String? imagePath,
    MeasurementMode? measurementMode,
    double? cameraHeightCm,
    CaptureOrientation? captureOrientation,
    bool headOrientationAttested = false,
  }) async {
    final now = DateTime.now();
    await (update(scanRecords)..where((row) => row.id.equals(scanId))).write(
      ScanRecordsCompanion(
        status: const Value(ScanStatuses.captured),
        imagePath: Value(imagePath),
        measurementMode: Value(measurementMode?.name),
        cameraHeightCm: Value(cameraHeightCm),
        captureOrientation: Value(captureOrientation?.storageValue),
        headOrientationAttested: Value(headOrientationAttested),
        capturedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await addPipelineEvent(scanId, 'capture', 'completed');
  }

  /// Records the user's head-direction attestation for an already-captured scan
  /// (docs/fix-phase-4/6-capture-orientation.md point 4). Called once the confirm step on the
  /// review screen is checked, since attestation happens after the image itself is produced.
  Future<void> recordOrientationAttestation(
    String scanId, {
    required CaptureOrientation orientation,
    required bool attested,
  }) async {
    await (update(scanRecords)..where((row) => row.id.equals(scanId))).write(
      ScanRecordsCompanion(
        captureOrientation: Value(orientation.storageValue),
        headOrientationAttested: Value(attested),
        updatedAt: Value(DateTime.now()),
      ),
    );
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
    String? imageIdentity,
  }) {
    return into(pipelineEvents).insert(
      PipelineEventsCompanion(
        scanId: Value(scanId),
        stage: Value(stage),
        status: Value(status),
        message: Value(message),
        imageIdentity: Value(imageIdentity),
      ),
    );
  }

  /// docs/fix-8.md F74: renames the pig already attached to `scanId` (every scan has one
  /// from [createDraftScan] onward). The pig's tag is not editable here -- it is the
  /// auto-generated ID. An empty/blank name clears the display name, falling back to the
  /// tag wherever the UI shows the pig.
  Future<String> renamePigForScan({
    required String scanId,
    String? displayName,
  }) async {
    final scan = await (select(
      scanRecords,
    )..where((row) => row.id.equals(scanId))).getSingleOrNull();
    final pigId = scan?.pigId;
    if (pigId == null) {
      throw StateError('Scan $scanId has no pig to rename.');
    }
    final resolvedName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : null;
    await (update(pigs)..where((row) => row.id.equals(pigId))).write(
      PigsCompanion(
        displayName: Value(resolvedName),
        updatedAt: Value(DateTime.now()),
      ),
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
    Map<String, double>? features,
    String? featureFamily,
    double? cutterKeptFraction,
    String? cutterStatus,
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
        featureVector: Value(
          features == null
              ? null
              : jsonEncode({'family': featureFamily, 'values': features}),
        ),
        featureFamily: Value(featureFamily),
        cutterKeptFraction: Value(cutterKeptFraction),
        cutterStatus: Value(cutterStatus),
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
    const goal = ScanGoal.weightAndHealth;

    final scanId = await createDraftScan(goal: goal);
    await markCaptured(scanId, imagePath: null);

    final isWeightEligible = _random.nextDouble() >= 0.2;

    final isMeterStick = _random.nextBool();
    final reference = isMeterStick
        ? ReferenceSelection.meterStick
        : ReferenceSelection.poracStick;
    final pixelLength = 600.0 + _random.nextInt(401);
    final cmPerPixel = reference.lengthCm / pixelLength;

    await saveReferenceAnnotation(
      scanId: scanId,
      reference: reference,
      startX: 0.1,
      startY: 0.25,
      endX: 0.9,
      endY: 0.25,
      pixelLength: pixelLength,
      cmPerPixel: cmPerPixel,
      source: 'manual',
      detectorConfidence: 0.95,
      sameFloorPlaneConfirmed: true,
    );

    if (isWeightEligible) {
      final valueKg = double.parse(
        (40.0 + _random.nextDouble() * 90.0).toStringAsFixed(1),
      );

      // docs/plan-phase/4-dart-persistence-ui.md: the seed helper no longer fabricates a
      // feature vector. Inventing sixteen plausible Chen16 values (signed Hu moments
      // included) would be fabricated model output, which the UI contract forbids
      // surfacing. valueKg stays synthetic -- it is only ever the demo record's headline.
      await saveWeightResult(
        scanId: scanId,
        eligible: true,
        valueKg: valueKg,
        referenceLengthCm: reference.lengthCm,
        referencePixelLength: pixelLength,
        cmPerPixel: cmPerPixel,
        modelVersion: 'xgb-weight-v1',
      );
    } else {
      await saveWeightResult(
        scanId: scanId,
        eligible: false,
        failureReason: 'Pig mask truncated at image border.',
        modelVersion: 'xgb-weight-v1',
      );
    }

    final healthClasses = [
      'Healthy',
      'Suspected ASF',
      'Skin Lesion',
      'Poor Body Condition',
    ];
    final className = healthClasses[_random.nextInt(healthClasses.length)];
    final confidence = double.parse(
      (0.55 + _random.nextDouble() * 0.43).toStringAsFixed(2),
    );
    final uncertain = confidence < 0.70;

    await saveHealthResult(
      scanId: scanId,
      eligible: true,
      className: className,
      confidence: confidence,
      uncertain: uncertain,
      modelVersion: 'mobilenet-health-v1',
    );

    final tagNum = 100 + _random.nextInt(900);
    await renamePigForScan(scanId: scanId, displayName: 'Sample Pig #$tagNum');

    final finalStatus = isWeightEligible
        ? ScanStatuses.completed
        : ScanStatuses.blocked;

    await updateScanStatus(scanId, finalStatus);
    return scanId;
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

  /// docs/fix-7.md F72: wipes every user record table, then reclaims the freed pages with
  /// `VACUUM` so deleted rows do not stay readable in the SQLite file's free pages. `VACUUM`
  /// cannot run inside a transaction, so it runs after the delete transaction commits.
  /// `CustomReferences` and `PrivacyPreferences` are untouched by design -- the user keeps
  /// both. Captured photos on disk are a separate concern; see `PhotoCleanupService`.
  Future<void> deleteAllUserRecords() async {
    await transaction(() async {
      await delete(syncOutboxEntries).go();
      await delete(pipelineEvents).go();
      await delete(weightResults).go();
      await delete(healthResults).go();
      await delete(referenceAnnotations).go();
      await delete(scanRecords).go();
      await delete(pigs).go();
      await delete(pigFolders).go();
    });
    await customStatement('VACUUM');
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
