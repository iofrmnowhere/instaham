import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/scan_flow.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('weight_results migrates schemaVersion 3 -> 4: blob/telemetry columns added, '
      'existing rows and their deprecated feature values are kept', () async {
    final dir = await Directory.systemTemp.createTemp('instaham_mig');
    final file = File('${dir.path}/mig.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    // Open once at the current schema, then reshape the file to look like a v3
    // database: drop the four columns schemaVersion 4 adds and roll user_version
    // back. weight_results otherwise keeps its full v3 column set.
    var db = AppDatabase(NativeDatabase(file));
    await db.customStatement('SELECT 1');
    for (final col in const [
      'feature_vector',
      'feature_family',
      'cutter_kept_fraction',
      'cutter_status',
    ]) {
      await db.customStatement('ALTER TABLE weight_results DROP COLUMN $col');
    }
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement(
      "INSERT INTO weight_results "
      "(scan_id, eligible, feature_ra, feature_lc, feature_bl, feature_bw, "
      "feature_e, created_at) VALUES "
      "('legacy-scan', 0, 0.31, 42.0, 30.0, 12.0, 0.9, 0)",
    );
    await db.customStatement('PRAGMA user_version = 3');
    await db.close();

    // Reopen: drift sees user_version 3 < 4 and runs the from < 4 step.
    db = AppDatabase(NativeDatabase(file));
    final legacy = await db
        .customSelect(
          "SELECT * FROM weight_results WHERE scan_id = 'legacy-scan'",
        )
        .getSingle();
    expect(legacy.data['feature_ra'], 0.31);
    expect(legacy.data['feature_lc'], 42.0);
    expect(legacy.data['feature_vector'], isNull);
    expect(legacy.data['feature_family'], isNull);
    expect(legacy.data['cutter_kept_fraction'], isNull);
    expect(legacy.data['cutter_status'], isNull);
    await db.close();
  });

  test('privacy sharing is opt-in and survives record deletion', () async {
    final defaults = await database.getPrivacyPreferences();
    expect(defaults.researchImageSharing, isFalse);
    expect(defaults.usageAnalytics, isFalse);
    expect(defaults.inferenceMode, 'undecided');

    await database.savePrivacyPreferences(
      researchImageSharing: true,
      usageAnalytics: false,
      inferenceMode: 'on_device',
    );
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );

    await database.deleteAllUserRecords();

    expect(await database.recordsDao.loadScanBundle(scanId), isNull);
    final retained = await database.getPrivacyPreferences();
    expect(retained.researchImageSharing, isTrue);
    expect(retained.inferenceMode, 'on_device');
  });

  test('persists a user-confirmed reference and independent results', () async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    await database.markCaptured(scanId, imagePath: 'scan.jpg');
    await database.saveReferenceAnnotation(
      scanId: scanId,
      reference: ReferenceSelection.meterStick,
      startX: 0.1,
      startY: 0.25,
      endX: 0.9,
      endY: 0.25,
      pixelLength: 800,
      cmPerPixel: 0.125,
      source: 'automatic_adjusted',
      detectorConfidence: 0.88,
      sameFloorPlaneConfirmed: true,
    );
    await database.saveWeightResult(
      scanId: scanId,
      eligible: false,
      failureReason: 'One or more weight eligibility checks failed.',
      features: {'RA': 1, 'LC': 2, 'BL': 3, 'BW': 4, 'E': 5},
      featureFamily: 'baseline5',
      cutterKeptFraction: 0.95,
      cutterStatus: 'cut_applied',
    );
    await database.saveHealthResult(
      scanId: scanId,
      eligible: true,
      className: 'healthy',
      confidence: 0.91,
      modelVersion: 'health-test',
    );
    await database.assignPig(
      scanId: scanId,
      tag: 'P-001',
      displayName: 'Test pig',
    );

    final bundle = await database.recordsDao.loadScanBundle(scanId);

    expect(bundle, isNotNull);
    expect(bundle!.scan.status, ScanStatuses.analyzing);
    expect(bundle.reference!.userConfirmed, isTrue);
    expect(bundle.reference!.cmPerPixel, 0.125);
    expect(bundle.weight!.eligible, isFalse);
    expect(bundle.weight!.featureFamily, 'baseline5');
    expect(bundle.weight!.cutterKeptFraction, 0.95);
    expect(bundle.weight!.cutterStatus, 'cut_applied');
    final vector =
        jsonDecode(bundle.weight!.featureVector!) as Map<String, dynamic>;
    expect(vector['family'], 'baseline5');
    expect((vector['values'] as Map)['RA'], 1);
    expect((vector['values'] as Map)['E'], 5);
    // Deprecated columns are no longer written.
    expect(bundle.weight!.featureRa, isNull);
    expect(bundle.health!.eligible, isTrue);
    expect(bundle.health!.className, 'healthy');
    expect(bundle.pig!.tag, 'P-001');
  });

  test('inserts complete sample scan record', () async {
    final scanId = await database.insertSampleRecord();
    final bundle = await database.recordsDao.loadScanBundle(scanId);

    expect(bundle, isNotNull);
    expect(
      bundle!.scan.status,
      isIn([ScanStatuses.completed, ScanStatuses.blocked]),
    );
    expect(bundle.pig?.tag, startsWith('TAG-'));
    expect(bundle.health?.className, isNotNull);
  });
}
