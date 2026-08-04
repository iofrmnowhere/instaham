import '../../../../services/ml/weight_regression_service.dart';

/// Result from the weight estimation pipeline branch.
class WeightResultEntity {
  final bool eligible;
  final double? valueKg;
  final double? referenceLengthCm;
  final double? referencePixelLength;
  final double? cmPerPixel;
  final WeightFeatures? features;
  final String? failureReason;

  const WeightResultEntity({
    required this.eligible,
    this.valueKg,
    this.referenceLengthCm,
    this.referencePixelLength,
    this.cmPerPixel,
    this.features,
    this.failureReason,
  });
}
