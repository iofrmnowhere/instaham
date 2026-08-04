/// Represents a captured and orientation-corrected image ready for inference.
class CapturedImageEntity {
  final String path;
  final int widthPx;
  final int heightPx;

  const CapturedImageEntity({
    required this.path,
    required this.widthPx,
    required this.heightPx,
  });
}
