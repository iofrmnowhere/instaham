import '../../../health_assessment/domain/entities/health_result_entity.dart';
import '../../../segmentation/domain/entities/segmentation_result_entity.dart';
import '../../../view_suitability/domain/entities/view_result_entity.dart';
import '../../../weight_estimation/domain/entities/weight_result_entity.dart';

/// Top-level result representing the complete output of the inference pipeline.
/// Matches the JSON schema specified in §13.
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

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'model_version': modelVersion,
    'view': view.toJson(),
    if (segmentation != null) 'segmentation': segmentation!.toJson(),
    if (weight != null) 'weight': weight!.toJson(),
    if (health != null) 'health': health!.toJson(),
  };

  factory PipelineResultEntity.fromJson(
    Map<String, dynamic> json,
  ) => PipelineResultEntity(
    requestId: json['request_id'] as String,
    modelVersion: json['model_version'] as String,
    view: ViewResultEntity.fromJson(json['view'] as Map<String, dynamic>),
    segmentation: json['segmentation'] != null
        ? SegmentationResultEntity.fromJson(
            json['segmentation'] as Map<String, dynamic>,
          )
        : null,
    weight: json['weight'] != null
        ? WeightResultEntity.fromJson(json['weight'] as Map<String, dynamic>)
        : null,
    health: json['health'] != null
        ? HealthResultEntity.fromJson(json['health'] as Map<String, dynamic>)
        : null,
  );
}
