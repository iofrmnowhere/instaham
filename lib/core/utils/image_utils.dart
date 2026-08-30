/// Utility functions for image preprocessing.
///
/// EXIF orientation correction (AGENTS.md rule 5) happens once, at capture time, in
/// [ImageService.processRawBytes] (`img.bakeOrientation` -- lib/core/utils/image_service.dart).
/// This class used to also carry a `correctExifOrientation` method, but nothing called it and
/// it duplicated that same normalization; removed rather than left as a second, unused path a
/// future reader could mistake for where the guarantee actually lives
/// (ML_implementation_plan.md revision 7, section 12.6).
class ImageUtils {
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
