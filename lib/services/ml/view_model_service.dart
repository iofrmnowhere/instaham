// Service for loading and running the view-suitability MobileNetV4-Conv-Small model
// (docs/plan.md, 2026-09; replaced GhostNetV3 1.0x).
// Classes are loaded from classes.json — never hardcoded (AGENTS.md rule 1).
// Input: 224x224 center-crop, ImageNet normalized. See ML_implementation_plan.md section 2.1.
import 'ml_runtime.dart';

abstract interface class IViewModelService {
  Future<void> loadModel();
  Future<ViewClassificationResult> classify(String imagePath);
}

class ViewClassificationResult {
  final String label; // 'dorsal_valid' | 'health_only' | 'reject'
  final double confidence;

  const ViewClassificationResult({
    required this.label,
    required this.confidence,
  });
}

/// Real implementation: delegates to the native ORT session via [MlRuntime]. `loadModel()`
/// is a no-op — the native context (and every available capability's session) is created
/// once, lazily, the first time any capability is used.
class ViewModelServiceImpl implements IViewModelService {
  const ViewModelServiceImpl();

  @override
  Future<void> loadModel() async {
    await MlRuntime.instance();
  }

  @override
  Future<ViewClassificationResult> classify(String imagePath) async {
    final runtime = await MlRuntime.instance();
    final (status, json) = runtime.classifyView(imagePath);
    if (status != MlStatus.ok) {
      // AGENTS.md rule 8: never force a prediction after a failed check. 'reject' routes
      // the pipeline to stop exactly as a genuine low-confidence classification would.
      return const ViewClassificationResult(label: 'reject', confidence: 0.0);
    }
    return ViewClassificationResult(
      label: json['label'] as String? ?? 'reject',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
