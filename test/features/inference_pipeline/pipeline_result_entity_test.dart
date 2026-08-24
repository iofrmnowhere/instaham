import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/health_assessment/domain/entities/health_result_entity.dart';
import 'package:instaham/features/inference_pipeline/domain/entities/pipeline_result_entity.dart';
import 'package:instaham/features/segmentation/domain/entities/segmentation_result_entity.dart';
import 'package:instaham/features/view_suitability/domain/entities/view_result_entity.dart';
import 'package:instaham/features/weight_estimation/domain/entities/weight_features.dart';
import 'package:instaham/features/weight_estimation/domain/entities/weight_result_entity.dart';

void main() {
  group('PipelineResultEntity §13 schema serialization tests', () {
    test('complete pipeline result round-trips correctly to and from JSON', () {
      const entity = PipelineResultEntity(
        requestId: 'req_12345',
        modelVersion: '1.0.0',
        view: ViewResultEntity(label: 'dorsal_valid', confidence: 0.91),
        segmentation: SegmentationResultEntity(
          pigCount: 1,
          confidence: 0.94,
          maskAvailable: true,
          weightEligible: true,
        ),
        weight: WeightResultEntity(
          eligible: true,
          valueKg: 82.4,
          referenceLengthCm: 100.0,
          referencePixelLength: 431.2,
          cmPerPixel: 0.2319,
          features: WeightFeatures(
            ra: 0.21,
            lc: 246.8,
            bl: 121.3,
            bw: 44.1,
            e: 0.87,
          ),
          failureReason: null,
        ),
        health: HealthResultEntity(
          eligible: true,
          className: 'Healthy',
          confidence: 0.74,
          uncertain: false,
        ),
      );

      final json = entity.toJson();

      expect(json['request_id'], 'req_12345');
      expect(json['model_version'], '1.0.0');
      expect(json['view']['label'], 'dorsal_valid');
      expect(json['view']['confidence'], 0.91);
      expect(json['segmentation']['pig_count'], 1);
      expect(json['weight']['value_kg'], 82.4);
      expect(json['weight']['features']['RA'], 0.21);
      expect(json['health']['class_name'], 'Healthy');

      final reconstructed = PipelineResultEntity.fromJson(json);

      expect(reconstructed.requestId, entity.requestId);
      expect(reconstructed.modelVersion, entity.modelVersion);
      expect(reconstructed.view.label, 'dorsal_valid');
      expect(reconstructed.segmentation?.pigCount, 1);
      expect(reconstructed.weight?.valueKg, 82.4);
      expect(reconstructed.health?.className, 'Healthy');
    });

    test('blocked weight branch omits value_kg in JSON (§13 contract)', () {
      const entity = PipelineResultEntity(
        requestId: 'req_blocked',
        modelVersion: '1.0.0',
        view: ViewResultEntity(label: 'dorsal_valid', confidence: 0.85),
        weight: WeightResultEntity(
          eligible: false,
          failureReason: 'pig_truncated',
        ),
        health: HealthResultEntity(
          eligible: true,
          className: 'Healthy',
          confidence: 0.80,
        ),
      );

      final json = entity.toJson();

      expect(json['weight']['eligible'], isFalse);
      expect(json['weight']['value_kg'], isNull);
      expect(json['weight'].containsKey('value_kg'), isFalse);
      expect(json['weight']['failure_reason'], 'pig_truncated');
    });

    test('rejected view result contains only view fields', () {
      const entity = PipelineResultEntity(
        requestId: 'req_rejected',
        modelVersion: '1.0.0',
        view: ViewResultEntity(label: 'reject', confidence: 0.95),
      );

      final json = entity.toJson();

      expect(json['view']['label'], 'reject');
      expect(json.containsKey('segmentation'), isFalse);
      expect(json.containsKey('weight'), isFalse);
      expect(json.containsKey('health'), isFalse);

      final reconstructed = PipelineResultEntity.fromJson(json);
      expect(reconstructed.view.isReject, isTrue);
      expect(reconstructed.segmentation, isNull);
      expect(reconstructed.weight, isNull);
      expect(reconstructed.health, isNull);
    });
  });
}
