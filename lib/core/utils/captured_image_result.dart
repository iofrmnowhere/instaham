import 'dart:typed_data';

import '../models/capture_orientation.dart';

/// Value object representing an image captured by the camera or picker,
/// with EXIF orientation correction baked in.
class CapturedImageResult {
  final Uint8List bytes;
  final int widthPx;
  final int heightPx;
  final String? localPath;

  /// The orientation this capture reaches the segmenter in, derived from [widthPx]/[heightPx]
  /// (docs/fix-phase-4/6-capture-orientation.md). Drives which head-direction instruction and
  /// attestation the review step shows.
  final CaptureOrientation orientation;

  /// Whether the user has attested that the pig's head faces the direction
  /// [orientation] requires. Defaults to false -- attestation happens on the review step, after
  /// the image itself is produced, and must never be pre-ticked.
  final bool headOrientationAttested;

  const CapturedImageResult({
    required this.bytes,
    required this.widthPx,
    required this.heightPx,
    required this.orientation,
    this.localPath,
    this.headOrientationAttested = false,
  });

  CapturedImageResult copyWith({bool? headOrientationAttested}) {
    return CapturedImageResult(
      bytes: bytes,
      widthPx: widthPx,
      heightPx: heightPx,
      orientation: orientation,
      localPath: localPath,
      headOrientationAttested:
          headOrientationAttested ?? this.headOrientationAttested,
    );
  }
}
