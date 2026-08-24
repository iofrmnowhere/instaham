import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/inference_pipeline/domain/use_cases/run_inference_pipeline_use_case.dart';
import 'package:instaham/features/weight_estimation/domain/entities/weight_features.dart';
import 'package:instaham/services/ml/health_model_service.dart';
import 'package:instaham/services/ml/segmentation_service.dart';
import 'package:instaham/services/ml/view_model_service.dart';

import '../../helpers/mock_ml_services.dart';

void main() {
  group(
    'RunInferencePipelineUseCase routing logic tests (§4 & AGENTS.md rule 4)',
    () {
      late MockViewModelService mockViewModel;
      late MockHealthModelService mockHealthModel;
      late MockSegmentationService mockSegmentation;
      late MockWeightRegressionService mockWeightRegression;
      late RunInferencePipelineUseCase useCase;

      setUp(() {
        mockViewModel = MockViewModelService();
        mockHealthModel = MockHealthModelService();
        mockSegmentation = MockSegmentationService();
        mockWeightRegression = MockWeightRegressionService();

        useCase = RunInferencePipelineUseCase(
          viewModelService: mockViewModel,
          healthModelService: mockHealthModel,
          segmentationService: mockSegmentation,
          weightRegressionService: mockWeightRegression,
        );
      });

      test(
        'reject view result stops pipeline without attempting health or weight',
        () async {
          mockViewModel.result = const ViewClassificationResult(
            label: 'reject',
            confidence: 0.96,
          );

          final result = await useCase.execute(
            const PipelineInput(
              imagePath: '/test/unusable.jpg',
              referenceLengthCm: 100,
              referencePixelLength: 400,
            ),
          );

          expect(result.view.isReject, isTrue);
          expect(result.health, isNull);
          expect(result.weight, isNull);
          expect(result.segmentation, isNull);
          expect(mockHealthModel.classifyCallCount, 0);
          expect(mockSegmentation.segmentCallCount, 0);
          expect(mockWeightRegression.predictCallCount, 0);
        },
      );

      test(
        'dorsal_valid view executes both health and weight branches',
        () async {
          mockViewModel.result = const ViewClassificationResult(
            label: 'dorsal_valid',
            confidence: 0.94,
          );
          mockHealthModel.result = const HealthClassificationResult(
            className: 'Healthy',
            confidence: 0.88,
            probabilities: {'Healthy': 0.88, 'Lesion': 0.12},
          );
          mockSegmentation.result = const SegmentationResult(
            pigCount: 1,
            confidence: 0.91,
            maskAvailable: true,
          );
          mockWeightRegression.predictedWeight = 84.2;

          final result = await useCase.execute(
            const PipelineInput(
              imagePath: '/test/dorsal.jpg',
              referenceLengthCm: 100.0,
              referencePixelLength: 431.2,
              simulatedFeatures: WeightFeatures(
                ra: 0.21,
                lc: 246.8,
                bl: 121.3,
                bw: 44.1,
                e: 0.87,
              ),
            ),
          );

          expect(result.view.isDorsalValid, isTrue);
          expect(result.health, isNotNull);
          expect(result.health!.eligible, isTrue);
          expect(result.health!.className, 'Healthy');
          expect(result.health!.uncertain, isFalse);

          expect(result.weight, isNotNull);
          expect(result.weight!.eligible, isTrue);
          expect(result.weight!.valueKg, 84.2);
          expect(result.weight!.cmPerPixel, closeTo(0.2319, 0.0001));

          expect(mockHealthModel.classifyCallCount, 1);
          expect(mockSegmentation.segmentCallCount, 1);
          expect(mockWeightRegression.predictCallCount, 1);
        },
      );

      test(
        'failed weight branch does NOT block health assessment (AGENTS.md rule 4)',
        () async {
          mockViewModel.result = const ViewClassificationResult(
            label: 'dorsal_valid',
            confidence: 0.90,
          );
          mockHealthModel.result = const HealthClassificationResult(
            className: 'Healthy',
            confidence: 0.85,
            probabilities: {'Healthy': 0.85, 'Lesion': 0.15},
          );
          // Multiple pigs detected -> weight eligibility fails with multiple_pigs
          mockSegmentation.result = const SegmentationResult(
            pigCount: 3,
            confidence: 0.90,
            maskAvailable: true,
          );

          final result = await useCase.execute(
            const PipelineInput(
              imagePath: '/test/multi_pig.jpg',
              referenceLengthCm: 100,
              referencePixelLength: 400,
            ),
          );

          // Health result MUST still succeed
          expect(result.health, isNotNull);
          expect(result.health!.eligible, isTrue);
          expect(result.health!.className, 'Healthy');

          // Weight branch is blocked with failure reason
          expect(result.weight, isNotNull);
          expect(result.weight!.eligible, isFalse);
          expect(result.weight!.failureReason, 'multiple_pigs');
          expect(result.weight!.valueKg, isNull);
          expect(mockWeightRegression.predictCallCount, 0);
        },
      );

      test(
        'low-confidence view result is routed as reject and stops pipeline',
        () async {
          // Confidence 0.50 is below viewConfidenceThreshold (0.70)
          mockViewModel.result = const ViewClassificationResult(
            label: 'dorsal_valid',
            confidence: 0.50,
          );

          final result = await useCase.execute(
            const PipelineInput(
              imagePath: '/test/low_confidence.jpg',
              viewConfidenceThreshold: 0.70,
              referenceLengthCm: 100,
              referencePixelLength: 400,
            ),
          );

          expect(result.view.isReject, isTrue);
          expect(result.health, isNull);
          expect(result.weight, isNull);
          expect(mockHealthModel.classifyCallCount, 0);
          expect(mockSegmentation.segmentCallCount, 0);
        },
      );
    },
  );
}
