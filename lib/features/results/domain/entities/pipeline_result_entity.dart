import '../../../view_suitability/domain/entities/view_result_entity.dart';
import '../../../health_assessment/domain/entities/health_result_entity.dart';
import '../../../segmentation/domain/entities/segmentation_result_entity.dart';
import '../../../weight_estimation/domain/entities/weight_result_entity.dart';

/// The combined output of the full INSTAHAM inference pipeline.
/// Matches the result schema in Section 13 of the requirements.
class PipelineResultEntity {
  final String requestId;
  final String modelVersion;
  final ViewResultEntity view;
  final SegmentationResultEntity? segmentation;
  final WeightResultEntity? weight;
  final HealthResultEntity? health;

  const PipelineResultEntity({
    required this.requestId,
    required this.modelVersion,
    required this.view,
    this.segmentation,
    this.weight,
    this.health,
  });
}
