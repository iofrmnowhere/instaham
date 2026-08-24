import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/health_assessment/domain/entities/health_result_entity.dart';

void main() {
  group('HealthResultEntity logic and serialization tests', () {
    test('ineligible health result has null class and failure reason', () {
      const entity = HealthResultEntity(
        eligible: false,
        failureReason: 'unusable_image',
      );

      expect(entity.eligible, isFalse);
      expect(entity.className, isNull);
      expect(entity.confidence, isNull);
      expect(entity.uncertain, isFalse);
      expect(entity.failureReason, 'unusable_image');
    });

    test('uncertain result flag is set when confidence is below threshold', () {
      const entity = HealthResultEntity(
        eligible: true,
        className: 'Lesion',
        confidence: 0.52,
        uncertain: true,
      );

      expect(entity.eligible, isTrue);
      expect(entity.className, 'Lesion');
      expect(entity.confidence, 0.52);
      expect(entity.uncertain, isTrue);
    });

    test('high confidence result is marked certain (uncertain == false)', () {
      const entity = HealthResultEntity(
        eligible: true,
        className: 'Healthy',
        confidence: 0.95,
        uncertain: false,
      );

      expect(entity.eligible, isTrue);
      expect(entity.className, 'Healthy');
      expect(entity.uncertain, isFalse);
    });

    test('toJson and fromJson preserve all fields (§13 schema)', () {
      const entity = HealthResultEntity(
        eligible: true,
        className: 'Healthy',
        confidence: 0.74,
        uncertain: false,
      );

      final json = entity.toJson();
      expect(json['eligible'], isTrue);
      expect(json['class_name'], 'Healthy');
      expect(json['confidence'], 0.74);
      expect(json['uncertain'], isFalse);

      final reconstructed = HealthResultEntity.fromJson(json);
      expect(reconstructed.eligible, entity.eligible);
      expect(reconstructed.className, entity.className);
      expect(reconstructed.confidence, entity.confidence);
      expect(reconstructed.uncertain, entity.uncertain);
    });
  });
}
