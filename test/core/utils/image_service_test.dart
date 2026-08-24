import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:instaham/core/utils/image_service.dart';
import 'package:instaham/core/utils/image_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageService EXIF orientation and decoding tests', () {
    Uint8List createTestJpeg({
      required int width,
      required int height,
      int? exifOrientation,
    }) {
      final image = img.Image(width: width, height: height);
      // Fill with sample color
      img.fill(image, color: img.ColorRgb8(200, 100, 50));

      if (exifOrientation != null) {
        image.exif.imageIfd.orientation = exifOrientation;
      }

      return Uint8List.fromList(img.encodeJpg(image, quality: 90));
    }

    test(
      'processRawBytes decodes valid synthetic JPEG without EXIF rotation',
      () async {
        final bytes = createTestJpeg(width: 120, height: 80);
        final result = await ImageService.processRawBytes(bytes);

        expect(result.widthPx, 120);
        expect(result.heightPx, 80);
        expect(result.bytes.isNotEmpty, isTrue);
      },
    );

    test('processRawBytes corrects 90° CW EXIF orientation (tag 6)', () async {
      // Original 120x80 with orientation 6 (90° CW) -> should become 80x120 after baking
      final bytes = createTestJpeg(width: 120, height: 80, exifOrientation: 6);
      final result = await ImageService.processRawBytes(bytes);

      expect(result.widthPx, 80);
      expect(result.heightPx, 120);
    });

    test('processRawBytes corrects 180° EXIF orientation (tag 3)', () async {
      // 180° keeps width and height dimensions
      final bytes = createTestJpeg(width: 120, height: 80, exifOrientation: 3);
      final result = await ImageService.processRawBytes(bytes);

      expect(result.widthPx, 120);
      expect(result.heightPx, 80);
    });

    test('processRawBytes corrects 270° CW EXIF orientation (tag 8)', () async {
      // 270° swaps width and height
      final bytes = createTestJpeg(width: 120, height: 80, exifOrientation: 8);
      final result = await ImageService.processRawBytes(bytes);

      expect(result.widthPx, 80);
      expect(result.heightPx, 120);
    });

    test('processRawBytes throws Exception on corrupt image bytes', () async {
      final corruptBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);

      expect(
        () => ImageService.processRawBytes(corruptBytes),
        throwsA(isA<Exception>()),
      );
    });

    test('processed bytes round-trip as valid JPEG', () async {
      final bytes = createTestJpeg(width: 64, height: 64);
      final result = await ImageService.processRawBytes(bytes);

      final decoded = img.decodeImage(result.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 64);
    });
  });

  group('Coordinate transform tests (AGENTS.md rule 6)', () {
    const origWidth = 100;
    const origHeight = 60;
    const origX = 10.0;
    const origY = 20.0;

    test('90° rotation maps (x, y) to (y, origWidth - x)', () {
      final transformed = ImageUtils.transformCoordinates(
        x: origX,
        y: origY,
        origWidth: origWidth,
        origHeight: origHeight,
        rotationDegrees: 90,
      );

      expect(transformed.x, 20.0);
      expect(transformed.y, 90.0);
    });

    test('180° rotation maps (x, y) to (origWidth - x, origHeight - y)', () {
      final transformed = ImageUtils.transformCoordinates(
        x: origX,
        y: origY,
        origWidth: origWidth,
        origHeight: origHeight,
        rotationDegrees: 180,
      );

      expect(transformed.x, 90.0);
      expect(transformed.y, 40.0);
    });

    test('270° rotation maps (x, y) to (origHeight - y, x)', () {
      final transformed = ImageUtils.transformCoordinates(
        x: origX,
        y: origY,
        origWidth: origWidth,
        origHeight: origHeight,
        rotationDegrees: 270,
      );

      expect(transformed.x, 40.0);
      expect(transformed.y, 10.0);
    });

    test('0° / 360° rotation preserves original coordinates', () {
      final transformed = ImageUtils.transformCoordinates(
        x: origX,
        y: origY,
        origWidth: origWidth,
        origHeight: origHeight,
        rotationDegrees: 0,
      );

      expect(transformed.x, origX);
      expect(transformed.y, origY);
    });
  });
}
