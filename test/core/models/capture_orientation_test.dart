import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/models/capture_orientation.dart';

void main() {
  group('CaptureOrientation.fromDimensions', () {
    test('taller-than-wide image is portrait', () {
      expect(
        CaptureOrientation.fromDimensions(1080, 1920),
        CaptureOrientation.portrait,
      );
    });

    test('wider-than-tall image is landscape', () {
      expect(
        CaptureOrientation.fromDimensions(1920, 1080),
        CaptureOrientation.landscape,
      );
    });

    test('square image falls back to landscape (not strictly taller)', () {
      expect(
        CaptureOrientation.fromDimensions(1000, 1000),
        CaptureOrientation.landscape,
      );
    });
  });

  group('per-orientation attestation text', () {
    // docs/fix-7.md F71: the live orientation prompt is removed, but the attestation text
    // must still switch with orientation and name the direction, not just "correct"/"incorrect".
    test('portrait attestation names head-up', () {
      expect(
        CaptureOrientation.portrait.attestationLabel,
        contains('facing up'),
      );
    });

    test('landscape attestation names head-right', () {
      expect(
        CaptureOrientation.landscape.attestationLabel,
        contains('facing right'),
      );
    });

    test('storage value round-trips through captureOrientationFromStorage', () {
      for (final orientation in CaptureOrientation.values) {
        expect(
          captureOrientationFromStorage(orientation.storageValue),
          orientation,
        );
      }
      expect(captureOrientationFromStorage(null), isNull);
      expect(captureOrientationFromStorage('unknown'), isNull);
    });
  });
}
