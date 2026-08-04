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
}
