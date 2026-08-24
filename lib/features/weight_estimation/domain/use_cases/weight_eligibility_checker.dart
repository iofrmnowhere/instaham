/// Input parameters for evaluating weight estimation eligibility.
class WeightEligibilityInput {
  final int pigCount;
  final bool maskTouchesBoundary;
  final double segmentationConfidence;
  final double minSegmentationConfidence;
  final bool postureIsDorsal;
  final bool referenceAvailable;
  final double? referenceLengthCm;
  final double? referencePixelLength;
  final bool referenceIsCoplanar;
  final double? ra;
  final double? lc;
  final double? bl;
  final double? bw;
  final double? eccentricity;

  const WeightEligibilityInput({
    required this.pigCount,
    this.maskTouchesBoundary = false,
    this.segmentationConfidence = 1.0,
    this.minSegmentationConfidence = 0.5,
    this.postureIsDorsal = true,
    this.referenceAvailable = true,
    this.referenceLengthCm,
    this.referencePixelLength,
    this.referenceIsCoplanar = true,
    this.ra,
    this.lc,
    this.bl,
    this.bw,
    this.eccentricity,
  });
}

/// Result of evaluating weight estimation eligibility against the 9 §7 checks.
class WeightEligibilityResult {
  final bool eligible;
  final String? failureReason;

  const WeightEligibilityResult({required this.eligible, this.failureReason});

  static const pass = WeightEligibilityResult(
    eligible: true,
    failureReason: null,
  );

  factory WeightEligibilityResult.fail(String reason) =>
      WeightEligibilityResult(eligible: false, failureReason: reason);
}

/// Pure domain use-case that enforces the 9 weight-eligibility rules from §7.
class WeightEligibilityChecker {
  const WeightEligibilityChecker();

  WeightEligibilityResult check(WeightEligibilityInput input) {
    // Check 1: Exactly one usable pig instance detected
    if (input.pigCount == 0) {
      return WeightEligibilityResult.fail('no_pig');
    }
    if (input.pigCount > 1) {
      return WeightEligibilityResult.fail('multiple_pigs');
    }

    // Check 2: Full pig body inside frame (mask must not touch boundaries)
    if (input.maskTouchesBoundary) {
      return WeightEligibilityResult.fail('pig_truncated');
    }

    // Check 3: No severe occlusion / low segmentation confidence
    if (input.segmentationConfidence < input.minSegmentationConfidence) {
      return WeightEligibilityResult.fail('pig_occluded');
    }

    // Check 4: Suitable dorsal posture
    if (!input.postureIsDorsal) {
      return WeightEligibilityResult.fail('unsuitable_posture');
    }

    // Check 5: Valid reference object available
    if (!input.referenceAvailable) {
      return WeightEligibilityResult.fail('no_reference');
    }

    // Check 6: Reference object has known positive real-world length
    if (input.referenceLengthCm == null || input.referenceLengthCm! <= 0) {
      return WeightEligibilityResult.fail('invalid_reference_length');
    }

    // Check 7: Reference endpoints valid and sufficiently far apart in pixels
    if (input.referencePixelLength == null ||
        input.referencePixelLength! <= 0) {
      return WeightEligibilityResult.fail('endpoints_too_close');
    }

    // Check 8: Reference object is approximately coplanar with the pig
    if (!input.referenceIsCoplanar) {
      return WeightEligibilityResult.fail('reference_not_coplanar');
    }

    // Check 9: Mask and features pass sanity ranges
    final bl = input.bl;
    final bw = input.bw;
    final e = input.eccentricity;
    final ra = input.ra;
    final lc = input.lc;

    if (bl == null || bl <= 0 || !bl.isFinite) {
      return WeightEligibilityResult.fail('feature_extraction_failure');
    }
    if (bw == null || bw <= 0 || !bw.isFinite) {
      return WeightEligibilityResult.fail('feature_extraction_failure');
    }
    if (e == null || e < 0 || e >= 1.0 || !e.isFinite) {
      return WeightEligibilityResult.fail('feature_extraction_failure');
    }
    if (ra != null && !ra.isFinite) {
      return WeightEligibilityResult.fail('feature_extraction_failure');
    }
    if (lc != null && !lc.isFinite) {
      return WeightEligibilityResult.fail('feature_extraction_failure');
    }

    return WeightEligibilityResult.pass;
  }
}
