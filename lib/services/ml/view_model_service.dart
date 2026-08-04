// Service for loading and running the view-suitability MobileNetV4 model.
// Classes are loaded from classes.json — never hardcoded.
// Input: 224x224 center-crop, ImageNet normalized.
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
