import 'dart:typed_data';

/// Value object representing an image captured by the camera or picker,
/// with EXIF orientation correction baked in.
class CapturedImageResult {
  final Uint8List bytes;
  final int widthPx;
  final int heightPx;
  final String? localPath;

  const CapturedImageResult({
    required this.bytes,
    required this.widthPx,
    required this.heightPx,
    this.localPath,
  });
}
