/// Use case for calculating the physical scale (cm per pixel) from reference object endpoints.
/// Formula: cm_per_pixel = reference_length_cm / reference_pixels
class ComputeScaleUseCase {
  const ComputeScaleUseCase();

  double execute({
    required double referenceLengthCm,
    required double referencePixelLength,
  }) {
    if (referenceLengthCm <= 0) {
      throw ArgumentError.value(
        referenceLengthCm,
        'referenceLengthCm',
        'Reference real-world length must be strictly positive.',
      );
    }
    if (referencePixelLength <= 0) {
      throw ArgumentError.value(
        referencePixelLength,
        'referencePixelLength',
        'Reference pixel distance must be strictly positive.',
      );
    }

    return referenceLengthCm / referencePixelLength;
  }
}
