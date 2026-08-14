import 'dart:io';
import 'package:flutter/foundation.dart';
import 'image_service.dart';

/// Utility functions for image preprocessing and EXIF orientation correction.
class ImageUtils {
  /// Corrects EXIF orientation and returns a normalized image file path.
  static Future<String> correctExifOrientation(String imagePath) async {
    if (kIsWeb) return imagePath;

    final file = File(imagePath);
    if (!file.existsSync()) return imagePath;

    final bytes = await file.readAsBytes();
    final result = await ImageService.processRawBytes(
      bytes,
      originalPath: imagePath,
    );
    return result.localPath ?? imagePath;
  }
}
