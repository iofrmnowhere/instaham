import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// docs/fix-7.md F72: deletes every photo copy the app or its plugins wrote into the app's
/// own temporary/cache directory as part of "Delete all local records" --
/// - the app's processed capture, `instaham_cap_*.jpg` (`ImageService.processRawBytes`);
/// - the camera plugin's raw shot from `CameraController.takePicture()`, which the plugin
///   writes to the cache and the app never deletes on its own;
/// - the image picker's cached copy of a camera or gallery pick.
///
/// Files outside this directory -- for example a gallery pick's original photo -- are never
/// touched. Searches recursively by extension rather than by filename prefix, since the
/// camera plugin and image picker choose their own names.
abstract final class PhotoCleanupService {
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};

  /// Deletes every image file found under [directory] (defaults to the app's own
  /// `getTemporaryDirectory()`), searched recursively. Returns the number of files deleted.
  /// A file that fails to delete (already gone, locked) is skipped rather than thrown --
  /// the rest of the wipe must not be blocked by one stray file.
  static Future<int> deleteAllCapturedPhotos({Directory? directory}) async {
    final root = directory ?? await getTemporaryDirectory();
    if (!await root.exists()) return 0;

    var deleted = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!_imageExtensions.contains(_extensionOf(entity.path))) continue;
      try {
        await entity.delete();
        deleted++;
      } catch (_) {
        // Best-effort: see doc comment above.
      }
    }
    return deleted;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }
}
