import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/weight_estimation/domain/use_cases/weight_eligibility_checker.dart';

void main() {
  group('WeightEligibilityChecker §7 checks tests', () {
    const checker = WeightEligibilityChecker();

    WeightEligibilityInput createValidInput() {
      return const WeightEligibilityInput(
        pigCount: 1,
        maskTouchesBoundary: false,
        segmentationConfidence: 0.92,
        minSegmentationConfidence: 0.50,
        postureIsDorsal: true,
        referenceAvailable: true,
        referenceLengthCm: 100.0,
        referencePixelLength: 431.2,
        referenceIsCoplanar: true,
        ra: 0.21,
        lc: 246.8,
        bl: 121.3,
        bw: 44.1,
        eccentricity: 0.87,
      );
    }

    test('Check 1: pigCount == 0 fails with no_pig', () {
      final input = WeightEligibilityInput(
        pigCount: 0,
        referenceLengthCm: 100,
        referencePixelLength: 400,
        bl: 120,
        bw: 40,
        eccentricity: 0.8,
      );
      final result = checker.check(input);

      expect(result.eligible, isFalse);
      expect(result.failureReason, 'no_pig');
    });

    test('Check 1: pigCount > 1 fails with multiple_pigs', () {
      final input = WeightEligibilityInput(
        pigCount: 2,
        referenceLengthCm: 100,
        referencePixelLength: 400,
        bl: 120,
        bw: 40,
        eccentricity: 0.8,
      );
      final result = checker.check(input);

      expect(result.eligible, isFalse);
      expect(result.failureReason, 'multiple_pigs');
    });

    test('Check 2: maskTouchesBoundary == true fails with pig_truncated', () {
      final input = WeightEligibilityInput(
        pigCount: 1,
        maskTouchesBoundary: true,
        referenceLengthCm: 100,
        referencePixelLength: 400,
        bl: 120,
        bw: 40,
        eccentricity: 0.8,
      );
      final result = checker.check(input);

      expect(result.eligible, isFalse);
      expect(result.failureReason, 'pig_truncated');
    });

    test('Check 3: low segmentation confidence fails with pig_occluded', () {
      final input = WeightEligibilityInput(
        pigCount: 1,
        segmentationConfidence: 0.40,
        minSegmentationConfidence: 0.50,
        referenceLengthCm: 100,
        referencePixelLength: 400,
        bl: 120,
        bw: 40,
        eccentricity: 0.8,
      );
      final result = checker.check(input);

      expect(result.eligible, isFalse);
      expect(result.failureReason, 'pig_occluded');
    });

    test(
      'Check 4: unsuitable dorsal posture fails with unsuitable_posture',
      () {
        final input = WeightEligibilityInput(
          pigCount: 1,
          postureIsDorsal: false,
          referenceLengthCm: 100,
          referencePixelLength: 400,
          bl: 120,
          bw: 40,
          eccentricity: 0.8,
        );
        final result = checker.check(input);

        expect(result.eligible, isFalse);
        expect(result.failureReason, 'unsuitable_posture');
      },
    );

    test('Check 5: missing reference object fails with no_reference', () {
      final input = WeightEligibilityInput(
        pigCount: 1,
        referenceAvailable: false,
        referenceLengthCm: null,
        referencePixelLength: null,
        bl: 120,
        bw: 40,
        eccentricity: 0.8,
      );
      final result = checker.check(input);

      expect(result.eligible, isFalse);
      expect(result.failureReason, 'no_reference');
    });

    test(
      'Check 6: zero or negative reference length fails with invalid_reference_length',
      () {
        final inputZero = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 0.0,
          referencePixelLength: 400,
          bl: 120,
          bw: 40,
          eccentricity: 0.8,
        );
        expect(
          checker.check(inputZero).failureReason,
          'invalid_reference_length',
        );

        final inputNegative = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: -10.0,
          referencePixelLength: 400,
          bl: 120,
          bw: 40,
          eccentricity: 0.8,
        );
        expect(
          checker.check(inputNegative).failureReason,
          'invalid_reference_length',
        );
      },
    );

    test(
      'Check 7: non-positive reference pixel length fails with endpoints_too_close',
      () {
        final inputZeroPx = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: 0,
          bl: 120,
          bw: 40,
          eccentricity: 0.8,
        );
        expect(checker.check(inputZeroPx).failureReason, 'endpoints_too_close');

        final inputNullPx = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: null,
          bl: 120,
          bw: 40,
          eccentricity: 0.8,
        );
        expect(checker.check(inputNullPx).failureReason, 'endpoints_too_close');
      },
    );

    test(
      'Check 8: reference not coplanar fails with reference_not_coplanar',
      () {
        final input = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: 400,
          referenceIsCoplanar: false,
          bl: 120,
          bw: 40,
          eccentricity: 0.8,
        );
        final result = checker.check(input);

        expect(result.eligible, isFalse);
        expect(result.failureReason, 'reference_not_coplanar');
      },
    );

    test(
      'Check 9: zero or negative BL/BW fails with feature_extraction_failure',
      () {
        final inputZeroBL = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: 400,
          bl: 0,
          bw: 40,
          eccentricity: 0.8,
        );
        expect(
          checker.check(inputZeroBL).failureReason,
          'feature_extraction_failure',
        );

        final inputZeroBW = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: 400,
          bl: 120,
          bw: 0,
          eccentricity: 0.8,
        );
        expect(
          checker.check(inputZeroBW).failureReason,
          'feature_extraction_failure',
        );
      },
    );

    test(
      'Check 9: eccentricity out of [0, 1) range fails with feature_extraction_failure',
      () {
        final inputEccentricity1 = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: 400,
          bl: 120,
          bw: 40,
          eccentricity: 1.0,
        );
        expect(
          checker.check(inputEccentricity1).failureReason,
          'feature_extraction_failure',
        );

        final inputEccentricityNegative = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: 400,
          bl: 120,
          bw: 40,
          eccentricity: -0.1,
        );
        expect(
          checker.check(inputEccentricityNegative).failureReason,
          'feature_extraction_failure',
        );
      },
    );

    test(
      'Check 9: non-finite feature values fail with feature_extraction_failure',
      () {
        final inputNaN = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: 400,
          bl: double.nan,
          bw: 40,
          eccentricity: 0.8,
        );
        expect(
          checker.check(inputNaN).failureReason,
          'feature_extraction_failure',
        );

        final inputInf = WeightEligibilityInput(
          pigCount: 1,
          referenceLengthCm: 100,
          referencePixelLength: 400,
          bl: 120,
          bw: double.infinity,
          eccentricity: 0.8,
        );
        expect(
          checker.check(inputInf).failureReason,
          'feature_extraction_failure',
        );
      },
    );

    test('All checks pass -> eligible is true and failureReason is null', () {
      final input = createValidInput();
      final result = checker.check(input);

      expect(result.eligible, isTrue);
      expect(result.failureReason, isNull);
    });
  });
}
