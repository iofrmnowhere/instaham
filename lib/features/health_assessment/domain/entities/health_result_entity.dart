/// Result from the health classification model.
class HealthResultEntity {
  final bool eligible;
  final String? className;
  final double? confidence;
  final bool uncertain;
  final String? failureReason;

  const HealthResultEntity({
    required this.eligible,
    this.className,
    this.confidence,
    this.uncertain = false,
    this.failureReason,
  });

  Map<String, dynamic> toJson() => {
    'eligible': eligible,
    if (className != null) 'class_name': className,
    if (confidence != null) 'confidence': confidence,
    'uncertain': uncertain,
    if (failureReason != null) 'failure_reason': failureReason,
  };

  factory HealthResultEntity.fromJson(Map<String, dynamic> json) =>
      HealthResultEntity(
        eligible: json['eligible'] as bool? ?? false,
        className: json['class_name'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
        uncertain: json['uncertain'] as bool? ?? false,
        failureReason: json['failure_reason'] as String?,
      );
}
