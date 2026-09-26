import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/services/photo_cleanup_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('instaham_photo_cleanup');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // docs/fix-7.md F72.
  test(
    'deletes app captures, camera raw shots, and picker cache copies',
    () async {
      await File(
        '${tempDir.path}/instaham_cap_123.jpg',
      ).writeAsBytes([1, 2, 3]);
      await File('${tempDir.path}/CAP_2026_09_26.jpg').writeAsBytes([1, 2, 3]);
      final pickerCacheDir = Directory('${tempDir.path}/image_picker_cache')
        ..createSync();
      await File(
        '${pickerCacheDir.path}/scaled_1000012345.png',
      ).writeAsBytes([1, 2, 3]);
      final keep = File('${tempDir.path}/not_an_image.txt');
      await keep.writeAsString('keep me');

      final deleted = await PhotoCleanupService.deleteAllCapturedPhotos(
        directory: tempDir,
      );

      expect(deleted, 3);
      expect(await keep.exists(), isTrue);
    },
  );

  test('returns 0 and does not throw for a missing directory', () async {
    final missing = Directory('${tempDir.path}/does_not_exist');
    final deleted = await PhotoCleanupService.deleteAllCapturedPhotos(
      directory: missing,
    );
    expect(deleted, 0);
  });

  test('an empty directory yields no deletions', () async {
    final deleted = await PhotoCleanupService.deleteAllCapturedPhotos(
      directory: tempDir,
    );
    expect(deleted, 0);
  });
}
