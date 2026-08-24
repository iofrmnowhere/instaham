import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/weight_estimation/domain/use_cases/compute_scale_use_case.dart';

void main() {
  group('ComputeScaleUseCase scale calculation tests', () {
    const useCase = ComputeScaleUseCase();

    test('100 cm / 431.2 px computes correct ratio (§13 example)', () {
      final scale = useCase.execute(
        referenceLengthCm: 100.0,
        referencePixelLength: 431.2,
      );

      expect(scale, closeTo(0.2319, 0.0001));
    });

    test('131 cm / 800 px computes correct ratio for Porac reference', () {
      final scale = useCase.execute(
        referenceLengthCm: 131.0,
        referencePixelLength: 800.0,
      );

      expect(scale, closeTo(0.16375, 0.00001));
    });

    test('custom positive reference length calculates accurate scale', () {
      final scale = useCase.execute(
        referenceLengthCm: 50.0,
        referencePixelLength: 200.0,
      );

      expect(scale, 0.25);
    });

    test('referenceLengthCm <= 0 throws ArgumentError (§8 validation)', () {
      expect(
        () => useCase.execute(
          referenceLengthCm: 0.0,
          referencePixelLength: 400.0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => useCase.execute(
          referenceLengthCm: -10.0,
          referencePixelLength: 400.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('referencePixelLength <= 0 throws ArgumentError (§7 check 7)', () {
      expect(
        () => useCase.execute(
          referenceLengthCm: 100.0,
          referencePixelLength: 0.0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => useCase.execute(
          referenceLengthCm: 100.0,
          referencePixelLength: -50.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
