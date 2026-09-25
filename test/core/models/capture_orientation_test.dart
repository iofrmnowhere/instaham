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

  group('per-orientation prompt and attestation text', () {
    // docs/fix-phase-4/6-capture-orientation.md: the prompt and attestation text must switch
    // with orientation and must name the direction, not just "correct"/"incorrect".
    test('portrait names head-up in both the prompt and the attestation', () {
      expect(
        CaptureOrientation.portrait.headDirectionInstruction,
        contains('up'),
      );
      expect(
        CaptureOrientation.portrait.attestationLabel,
        contains('facing up'),
      );
    });

    test(
      'landscape names head-right in both the prompt and the attestation',
      () {
        expect(
          CaptureOrientation.landscape.headDirectionInstruction,
          contains('right'),
        );
        expect(
          CaptureOrientation.landscape.attestationLabel,
          contains('facing right'),
        );
      },
    );

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
