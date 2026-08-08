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
    final scanId = await database.createDraftScan(goal: ScanGoal.healthOnly);

    await database.deleteAllUserRecords();

    expect(await database.loadScanBundle(scanId), isNull);
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
      ra: 1,
      lc: 2,
      bl: 3,
      bw: 4,
      e: 5,
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

    final bundle = await database.loadScanBundle(scanId);

    expect(bundle, isNotNull);
    expect(bundle!.scan.status, ScanStatuses.analyzing);
    expect(bundle.reference!.userConfirmed, isTrue);
    expect(bundle.reference!.cmPerPixel, 0.125);
    expect(bundle.weight!.eligible, isFalse);
    expect(bundle.weight!.featureRa, 1);
    expect(bundle.weight!.featureLc, 2);
    expect(bundle.weight!.featureBl, 3);
    expect(bundle.weight!.featureBw, 4);
    expect(bundle.weight!.featureE, 5);
    expect(bundle.health!.eligible, isTrue);
    expect(bundle.health!.className, 'healthy');
    expect(bundle.pig!.tag, 'P-001');
  });

  test('inserts complete sample scan record', () async {
    final scanId = await database.insertSampleRecord();
    final bundle = await database.loadScanBundle(scanId);

    expect(bundle, isNotNull);
    expect(bundle!.scan.status, ScanStatuses.completed);
    expect(bundle.pig?.tag, 'TAG-101');
    expect(bundle.weight?.valueKg, 85.5);
    expect(bundle.health?.className, 'Healthy');
  });
}
