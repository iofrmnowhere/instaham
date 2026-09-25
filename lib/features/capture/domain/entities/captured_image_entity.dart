import '../../../../core/models/capture_orientation.dart';

/// Represents a captured and orientation-corrected image ready for inference.
class CapturedImageEntity {
  final String path;
  final int widthPx;
  final int heightPx;

  /// The orientation this capture reaches the segmenter in, and whether the user attested to
  /// the pig's head facing the direction that orientation requires
  /// (docs/fix-phase-4/6-capture-orientation.md).
  final CaptureOrientation orientation;
  final bool headOrientationAttested;

  const CapturedImageEntity({
    required this.path,
    required this.widthPx,
    required this.heightPx,
    required this.orientation,
    this.headOrientationAttested = false,
  });
}
