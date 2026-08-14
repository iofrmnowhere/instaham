import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'captured_image_result.dart';

abstract final class ImageService {
  static final ImagePicker _picker = ImagePicker();

  /// Processes a captured [XFile] (from CameraController or ImagePicker),
  /// bakes in the EXIF orientation, and saves it locally if not on web.
  static Future<CapturedImageResult> processCapture(XFile file) async {
    final rawBytes = await file.readAsBytes();
    return processRawBytes(rawBytes, originalPath: file.path);
  }

  /// Bakes orientation into raw image bytes, decodes dimensions, and writes to temp storage on native platforms.
  static Future<CapturedImageResult> processRawBytes(
    Uint8List rawBytes, {
    String? originalPath,
  }) async {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw Exception('Failed to decode captured image bytes.');
    }

    final oriented = img.bakeOrientation(decoded);
    final encodedBytes = Uint8List.fromList(
      img.encodeJpg(oriented, quality: 92),
    );

    String? savedPath;
    if (!kIsWeb) {
      try {
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${tempDir.path}/instaham_cap_$timestamp.jpg');
        await file.writeAsBytes(encodedBytes, flush: true);
        savedPath = file.path;
      } catch (e) {
        debugPrint('ImageService: Failed to save to temp directory: $e');
        savedPath = originalPath;
      }
    }

    return CapturedImageResult(
      bytes: encodedBytes,
      widthPx: oriented.width,
      heightPx: oriented.height,
      localPath: savedPath,
    );
  }

  /// Fallback picker from device camera (useful for web or when hardware controller isn't supported).
  static Future<CapturedImageResult?> pickFromCamera() async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 3000,
        maxHeight: 3000,
        imageQuality: 92,
      );
      if (xFile == null) return null;
      return await processCapture(xFile);
    } catch (e) {
      debugPrint('ImageService.pickFromCamera error: $e');
      return null;
    }
  }

  /// Picker from gallery as fallback / upload alternative.
  static Future<CapturedImageResult?> pickFromGallery() async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 3000,
        maxHeight: 3000,
        imageQuality: 92,
      );
      if (xFile == null) return null;
      return await processCapture(xFile);
    } catch (e) {
      debugPrint('ImageService.pickFromGallery error: $e');
      return null;
    }
  }
}
