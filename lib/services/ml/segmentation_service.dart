// Service for running YOLO segmentation at 640x640 with letterboxing.
// Maps mask back to original image coordinates.
abstract interface class ISegmentationService {
  Future<void> loadModel();
  Future<SegmentationResult> segment(String imagePath);
}

class SegmentationResult {
  final int pigCount;
  final double confidence;
  final bool maskAvailable;
  // TODO: Add mask data (pixel map or polygon)

  const SegmentationResult({
    required this.pigCount,
    required this.confidence,
    required this.maskAvailable,
  });
}
