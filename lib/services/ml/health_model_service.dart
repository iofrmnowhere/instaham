// Service for loading and running the health classification model: GhostNetV3 1.0x, 10
// disease classes. Classes loaded from classes.json (AGENTS.md rule 1).
// Input protocol is manifest-declared (section 1.1(c) of ML_implementation_plan.md); the
// shipped checkpoint defaults to full_frame until slice -1 recovers the probe's test images.
import 'ml_runtime.dart';

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

/// Real implementation: delegates to the native ORT session via [MlRuntime].
class HealthModelServiceImpl implements IHealthModelService {
  const HealthModelServiceImpl();

  @override
  Future<void> loadModel() async {
    await MlRuntime.instance();
  }

  @override
  Future<HealthClassificationResult> classify(String imagePath) async {
    final runtime = await MlRuntime.instance();
    final (status, json) = runtime.classifyHealth(imagePath);
    if (status != MlStatus.ok) {
      throw StateError(
        'health classification unavailable: ${json['message'] ?? status}',
      );
    }
    final rawProbs =
        (json['probabilities'] as Map<String, dynamic>?) ?? const {};
    return HealthClassificationResult(
      className: json['label'] as String? ?? 'Unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      probabilities: rawProbs.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}
