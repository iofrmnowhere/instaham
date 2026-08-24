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
    this.weightEligible = true,
    this.failureReason,
  });

  Map<String, dynamic> toJson() => {
    'pig_count': pigCount,
    'confidence': confidence,
    'mask_available': maskAvailable,
    if (failureReason != null) 'failure_reason': failureReason,
  };

  factory SegmentationResultEntity.fromJson(Map<String, dynamic> json) =>
      SegmentationResultEntity(
        pigCount: json['pig_count'] as int? ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        maskAvailable: json['mask_available'] as bool? ?? false,
        failureReason: json['failure_reason'] as String?,
      );
}
