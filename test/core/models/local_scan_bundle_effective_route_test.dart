// docs/fix-phase-6/2-dialog-and-routing.md (F70): LocalScanBundle.effectiveRoute is what
// ResultsScreen's _weightCard/_healthCard now read instead of the raw stored verdict, so
// that an overridden `reject`/`health_only` scan whose weight branch then genuinely fails
// reads "Unavailable", not "Skipped". This is a direct unit test of that getter -- no
// widget pump, no disk file -- since a widget-level rendering of the fix was found to
// depend on decoding a real image file through `Image.file`, which is exercised end to end
// by the app's existing photo-preview tests instead of duplicated here.
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/local_scan_bundle.dart';

void main() {
  ScanRecord scanFixture() => ScanRecord(
    id: 'scan_1',
    pigId: null,
    goal: 'weight_and_health',
    status: 'analyzing',
    measurementMode: null,
    imagePath: null,
    captureOrientation: null,
    headOrientationAttested: false,
    cameraHeightCm: null,
    createdAt: DateTime(2026, 9, 25),
    updatedAt: DateTime(2026, 9, 25),
    syncState: 'local',
  );

  PipelineEvent viewEventFixture(String status) => PipelineEvent(
    id: 1,
    scanId: 'scan_1',
    stage: 'view',
    status: status,
    message: '0.9000',
    imageIdentity: null,
    createdAt: DateTime(2026, 9, 25),
  );

  test(
    'no override: effectiveRoute reads the stored verdict (reject stays reject)',
    () {
      final bundle = LocalScanBundle(
        scan: scanFixture(),
        viewEvent: viewEventFixture('reject'),
      );

      expect(bundle.effectiveRoute, 'reject');
    },
  );

  test(
    'reject overridden to dorsal_valid: effectiveRoute reads the override, not the '
    'stored verdict',
    () {
      final bundle = LocalScanBundle(
        scan: scanFixture(),
        viewEvent: viewEventFixture('reject'),
        viewRouteOverride: 'dorsal_valid',
      );

      expect(bundle.effectiveRoute, 'dorsal_valid');
    },
  );

  test(
    'reject overridden to health_only: effectiveRoute reads the override',
    () {
      final bundle = LocalScanBundle(
        scan: scanFixture(),
        viewEvent: viewEventFixture('reject'),
        viewRouteOverride: 'health_only',
      );

      expect(bundle.effectiveRoute, 'health_only');
    },
  );

  test(
    'health_only overridden to dorsal_valid: effectiveRoute reads the override, not the '
    'stored verdict',
    () {
      final bundle = LocalScanBundle(
        scan: scanFixture(),
        viewEvent: viewEventFixture('health_only'),
        viewRouteOverride: 'dorsal_valid',
      );

      expect(bundle.effectiveRoute, 'dorsal_valid');
    },
  );

  test('no view event and no override: effectiveRoute is null', () {
    final bundle = LocalScanBundle(scan: scanFixture());

    expect(bundle.effectiveRoute, isNull);
  });
}
