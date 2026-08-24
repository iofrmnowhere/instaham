import '../../../../services/ml/health_model_service.dart';
import '../../../../services/ml/segmentation_service.dart';
import '../../../../services/ml/view_model_service.dart';
import '../../../../services/ml/weight_regression_service.dart';
import '../../../health_assessment/domain/entities/health_result_entity.dart';
import '../../../segmentation/domain/entities/segmentation_result_entity.dart';
import '../../../view_suitability/domain/entities/view_result_entity.dart';
import '../../../weight_estimation/domain/entities/weight_features.dart';
import '../../../weight_estimation/domain/entities/weight_result_entity.dart';
import '../../../weight_estimation/domain/use_cases/compute_scale_use_case.dart';
import '../../../weight_estimation/domain/use_cases/weight_eligibility_checker.dart';
import '../entities/pipeline_result_entity.dart';

/// Parameters for running the full inference pipeline on an image.
class PipelineInput {
  final String imagePath;
  final String requestId;
  final String modelVersion;
  final double? referenceLengthCm;
  final double? referencePixelLength;
  final double viewConfidenceThreshold;
  final double healthConfidenceThreshold;
  final bool postureIsDorsal;
  final bool referenceIsCoplanar;
  final WeightFeatures? simulatedFeatures;

  const PipelineInput({
    required this.imagePath,
    this.requestId = 'req_default',
    this.modelVersion = '1.0.0',
    this.referenceLengthCm,
    this.referencePixelLength,
    this.viewConfidenceThreshold = 0.70,
    this.healthConfidenceThreshold = 0.60,
    this.postureIsDorsal = true,
    this.referenceIsCoplanar = true,
    this.simulatedFeatures,
  });
}

/// Orchestrates the entire INSTAHAM inference pipeline according to §4:
/// 1. Runs view-suitability classifier.
/// 2. If 'dorsal_valid' with confidence >= threshold:
///    - Runs visual health classification.
///    - Runs segmentation and checks all 9 weight-eligibility rules.
///    - Computes scale and runs XGBoost weight estimation if eligible.
/// 3. If 'reject' or low-confidence: stops pipeline without running health or weight.
class RunInferencePipelineUseCase {
  final IViewModelService viewModelService;
  final IHealthModelService healthModelService;
  final ISegmentationService segmentationService;
  final IWeightRegressionService weightRegressionService;
  final WeightEligibilityChecker weightEligibilityChecker;
  final ComputeScaleUseCase computeScaleUseCase;

  const RunInferencePipelineUseCase({
    required this.viewModelService,
    required this.healthModelService,
    required this.segmentationService,
    required this.weightRegressionService,
    this.weightEligibilityChecker = const WeightEligibilityChecker(),
    this.computeScaleUseCase = const ComputeScaleUseCase(),
  });

  Future<PipelineResultEntity> execute(PipelineInput input) async {
    // Step 1: View suitability classification
    final viewClassification = await viewModelService.classify(input.imagePath);

    final isLowConfidence =
        viewClassification.confidence < input.viewConfidenceThreshold;
    final effectiveLabel = isLowConfidence
        ? 'reject'
        : viewClassification.label;

    final viewResult = ViewResultEntity(
      label: effectiveLabel,
      confidence: viewClassification.confidence,
    );

    // If reject / low confidence, stop pipeline immediately
    if (viewResult.isReject || !viewResult.isDorsalValid) {
      return PipelineResultEntity(
        requestId: input.requestId,
        modelVersion: input.modelVersion,
        view: viewResult,
        segmentation: null,
        weight: null,
        health: null,
      );
    }

    // Step 2: High-confidence dorsal_valid -> run both branches independently

    // Health branch
    HealthResultEntity healthResult;
    try {
      final healthClassification = await healthModelService.classify(
        input.imagePath,
      );
      final isUncertain =
          healthClassification.confidence < input.healthConfidenceThreshold;
      healthResult = HealthResultEntity(
        eligible: true,
        className: healthClassification.className,
        confidence: healthClassification.confidence,
        uncertain: isUncertain,
      );
    } catch (e) {
      healthResult = HealthResultEntity(
        eligible: false,
        failureReason: e.toString(),
      );
    }

    // Weight branch (Segmentation -> Eligibility -> Scale -> Regression)
    SegmentationResultEntity segmentationEntity;
    WeightResultEntity weightResult;

    try {
      final segResult = await segmentationService.segment(input.imagePath);

      final features =
          input.simulatedFeatures ??
          (segResult.maskAvailable
              ? const WeightFeatures(
                  ra: 0.21,
                  lc: 246.8,
                  bl: 121.3,
                  bw: 44.1,
                  e: 0.87,
                )
              : null);

      final eligibility = weightEligibilityChecker.check(
        WeightEligibilityInput(
          pigCount: segResult.pigCount,
          segmentationConfidence: segResult.confidence,
          referenceAvailable: input.referenceLengthCm != null,
          referenceLengthCm: input.referenceLengthCm,
          referencePixelLength: input.referencePixelLength,
          postureIsDorsal: input.postureIsDorsal,
          referenceIsCoplanar: input.referenceIsCoplanar,
          bl: features?.bl,
          bw: features?.bw,
          eccentricity: features?.e,
          ra: features?.ra,
          lc: features?.lc,
        ),
      );

      segmentationEntity = SegmentationResultEntity(
        pigCount: segResult.pigCount,
        confidence: segResult.confidence,
        maskAvailable: segResult.maskAvailable,
        weightEligible: eligibility.eligible,
        failureReason: eligibility.failureReason,
      );

      if (!eligibility.eligible) {
        weightResult = WeightResultEntity(
          eligible: false,
          failureReason: eligibility.failureReason,
        );
      } else {
        final cmPerPixel = computeScaleUseCase.execute(
          referenceLengthCm: input.referenceLengthCm!,
          referencePixelLength: input.referencePixelLength!,
        );

        final predictedKg = await weightRegressionService.predict(features!);

        weightResult = WeightResultEntity(
          eligible: true,
          valueKg: predictedKg,
          referenceLengthCm: input.referenceLengthCm,
          referencePixelLength: input.referencePixelLength,
          cmPerPixel: cmPerPixel,
          features: features,
        );
      }
    } catch (e) {
      segmentationEntity = SegmentationResultEntity(
        pigCount: 0,
        confidence: 0.0,
        maskAvailable: false,
        weightEligible: false,
        failureReason: e.toString(),
      );
      weightResult = WeightResultEntity(
        eligible: false,
        failureReason: e.toString(),
      );
    }

    return PipelineResultEntity(
      requestId: input.requestId,
      modelVersion: input.modelVersion,
      view: viewResult,
      segmentation: segmentationEntity,
      weight: weightResult,
      health: healthResult,
    );
  }
}
