import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/models/scan_display_status.dart';
import 'package:instaham/core/models/scan_flow.dart';

void main() {
  group('displayScanStatus', () {
    // docs/fix-7.md F73.
    test(
      'blocked with no weight value but an eligible health result is Health only',
      () {
        expect(
          displayScanStatus(
            storedStatus: ScanStatuses.blocked,
            hasWeightValue: false,
            hasEligibleHealth: true,
          ),
          ScanDisplayStatuses.healthOnly,
        );
      },
    );

    test(
      'blocked with neither a weight value nor an eligible health result stays Blocked',
      () {
        expect(
          displayScanStatus(
            storedStatus: ScanStatuses.blocked,
            hasWeightValue: false,
            hasEligibleHealth: false,
          ),
          ScanStatuses.blocked,
        );
      },
    );

    test('non-blocked stored statuses are returned unchanged', () {
      for (final status in [
        ScanStatuses.draft,
        ScanStatuses.captured,
        ScanStatuses.referenceReview,
        ScanStatuses.analyzing,
        ScanStatuses.completed,
        ScanStatuses.rejected,
        ScanStatuses.cancelled,
      ]) {
        expect(
          displayScanStatus(
            storedStatus: status,
            hasWeightValue: false,
            hasEligibleHealth: true,
          ),
          status,
        );
      }
    });

    test(
      'blocked with a weight value is left as Blocked (should not occur in practice, '
      'since weightEligible drives completed instead)',
      () {
        expect(
          displayScanStatus(
            storedStatus: ScanStatuses.blocked,
            hasWeightValue: true,
            hasEligibleHealth: true,
          ),
          ScanStatuses.blocked,
        );
      },
    );
  });
}
