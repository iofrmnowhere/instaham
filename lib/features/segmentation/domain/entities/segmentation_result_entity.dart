/// Result from the YOLO segmentation model including eligibility check outcome.
class SegmentationResultEntity {
  final int pigCount;
  final double confidence;
  final bool maskAvailable;
  final bool weightEligible; // true only when all 9 checks pass
  final String? failureReason;
  // TODO: Add mask coordinate data

  const SegmentationResultEntity({
    required this.pigCount,
    required this.confidence,
    required this.maskAvailable,
    required this.weightEligible,
    this.failureReason,
  });
}
