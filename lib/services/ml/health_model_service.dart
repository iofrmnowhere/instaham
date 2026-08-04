// Service for loading and running the health classification model.
// Supports MobileNetV4-Conv-Small, ShuffleNetV2, or GhostNetV3.
// Classes loaded from classes.json.
abstract interface class IHealthModelService {
  Future<void> loadModel();
  Future<HealthClassificationResult> classify(String imagePath);
}

class HealthClassificationResult {
  final String className;
  final double confidence;
  final Map<String, double> probabilities;

  const HealthClassificationResult({
    required this.className,
    required this.confidence,
    required this.probabilities,
  });
}
