import 'weight_features.dart';

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

  Map<String, dynamic> toJson() => {
    'eligible': eligible,
    if (valueKg != null) 'value_kg': valueKg,
    if (referenceLengthCm != null) 'reference_length_cm': referenceLengthCm,
    if (referencePixelLength != null)
      'reference_pixel_length': referencePixelLength,
    if (cmPerPixel != null) 'cm_per_pixel': cmPerPixel,
    if (features != null) 'features': features!.toJson(),
    'failure_reason': failureReason,
  };

  factory WeightResultEntity.fromJson(Map<String, dynamic> json) =>
      WeightResultEntity(
        eligible: json['eligible'] as bool? ?? false,
        valueKg: (json['value_kg'] as num?)?.toDouble(),
        referenceLengthCm: (json['reference_length_cm'] as num?)?.toDouble(),
        referencePixelLength: (json['reference_pixel_length'] as num?)
            ?.toDouble(),
        cmPerPixel: (json['cm_per_pixel'] as num?)?.toDouble(),
        features: json['features'] != null
            ? WeightFeatures.fromJson(json['features'] as Map<String, dynamic>)
            : null,
        failureReason: json['failure_reason'] as String?,
      );
}
