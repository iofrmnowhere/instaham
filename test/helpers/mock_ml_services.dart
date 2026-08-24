import 'package:instaham/features/weight_estimation/domain/entities/weight_features.dart';
import 'package:instaham/services/ml/health_model_service.dart';
import 'package:instaham/services/ml/segmentation_service.dart';
import 'package:instaham/services/ml/view_model_service.dart';
import 'package:instaham/services/ml/weight_regression_service.dart';

/// Mock implementation of [IViewModelService] for unit testing pipeline routing.
class MockViewModelService implements IViewModelService {
  ViewClassificationResult result;
  bool loadModelCalled = false;
  int classifyCallCount = 0;

  MockViewModelService({
    this.result = const ViewClassificationResult(
      label: 'dorsal_valid',
      confidence: 0.95,
    ),
  });

  @override
  Future<void> loadModel() async {
    loadModelCalled = true;
  }

  @override
  Future<ViewClassificationResult> classify(String imagePath) async {
    classifyCallCount++;
    return result;
  }
}

/// Mock implementation of [IHealthModelService] for unit testing health assessment.
class MockHealthModelService implements IHealthModelService {
  HealthClassificationResult result;
  bool loadModelCalled = false;
  int classifyCallCount = 0;

  MockHealthModelService({
    this.result = const HealthClassificationResult(
      className: 'Healthy',
      confidence: 0.85,
      probabilities: {'Healthy': 0.85, 'Lesion': 0.15},
    ),
  });

  @override
  Future<void> loadModel() async {
    loadModelCalled = true;
  }

  @override
  Future<HealthClassificationResult> classify(String imagePath) async {
    classifyCallCount++;
    return result;
  }
}

/// Mock implementation of [ISegmentationService] for unit testing pig segmentation.
class MockSegmentationService implements ISegmentationService {
  SegmentationResult result;
  bool loadModelCalled = false;
  int segmentCallCount = 0;

  MockSegmentationService({
    this.result = const SegmentationResult(
      pigCount: 1,
      confidence: 0.92,
      maskAvailable: true,
    ),
  });

  @override
  Future<void> loadModel() async {
    loadModelCalled = true;
  }

  @override
  Future<SegmentationResult> segment(String imagePath) async {
    segmentCallCount++;
    return result;
  }
}

/// Mock implementation of [IWeightRegressionService] for unit testing XGBoost regression.
class MockWeightRegressionService implements IWeightRegressionService {
  double predictedWeight;
  bool loadModelCalled = false;
  int predictCallCount = 0;
  WeightFeatures? lastFeatures;

  MockWeightRegressionService({this.predictedWeight = 85.5});

  @override
  Future<void> loadModel() async {
    loadModelCalled = true;
  }

  @override
  Future<double> predict(WeightFeatures features) async {
    predictCallCount++;
    lastFeatures = features;
    return predictedWeight;
  }
}
