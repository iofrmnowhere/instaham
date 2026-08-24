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

  /// Transforms 2D point coordinates `(x, y)` from original image dimensions
  /// `(origWidth, origHeight)` to transformed image dimensions after rotation.
  static ({double x, double y}) transformCoordinates({
    required double x,
    required double y,
    required int origWidth,
    required int origHeight,
    required int rotationDegrees,
  }) {
    final normalizedDegrees = (rotationDegrees % 360 + 360) % 360;
    switch (normalizedDegrees) {
      case 90:
        return (x: y, y: origWidth - x);
      case 180:
        return (x: origWidth - x, y: origHeight - y);
      case 270:
        return (x: origHeight - y, y: x);
      case 0:
      default:
        return (x: x, y: y);
    }
  }
}
