import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/view_suitability/domain/entities/view_result_entity.dart';

void main() {
  group('ViewResultEntity routing and getters tests', () {
    test('dorsal_valid label sets isDorsalValid true and isReject false', () {
      const entity = ViewResultEntity(label: 'dorsal_valid', confidence: 0.94);

      expect(entity.isDorsalValid, isTrue);
      expect(entity.isReject, isFalse);
      expect(entity.confidence, 0.94);
    });

    test('reject label sets isReject true and isDorsalValid false', () {
      const entity = ViewResultEntity(label: 'reject', confidence: 0.88);

      expect(entity.isReject, isTrue);
      expect(entity.isDorsalValid, isFalse);
      expect(entity.confidence, 0.88);
    });

    test('other label (e.g. unknown) does not evaluate to dorsal_valid', () {
      const entity = ViewResultEntity(label: 'health_only', confidence: 0.75);

      expect(entity.isDorsalValid, isFalse);
    });

    test('toJson and fromJson round-trip correctly', () {
      const entity = ViewResultEntity(label: 'dorsal_valid', confidence: 0.92);
      final json = entity.toJson();

      expect(json['label'], 'dorsal_valid');
      expect(json['confidence'], 0.92);

      final reconstructed = ViewResultEntity.fromJson(json);
      expect(reconstructed.label, entity.label);
      expect(reconstructed.confidence, entity.confidence);
    });
  });
}
