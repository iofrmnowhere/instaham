// Service for running the XGBoost weight regression model.
// Feature order is FIXED: [RA, LC, BL, BW, E]. Never reorder.
abstract interface class IWeightRegressionService {
  Future<void> loadModel();
  Future<double> predict(WeightFeatures features);
}

class WeightFeatures {
  final double ra; // Relative area (dimensionless)
  final double lc; // Contour perimeter in cm
  final double bl; // Body length in cm
  final double bw; // Body width in cm
  final double e; // Eccentricity (dimensionless)

  const WeightFeatures({
    required this.ra,
    required this.lc,
    required this.bl,
    required this.bw,
    required this.e,
  });

  /// Returns features in the FIXED training order [RA, LC, BL, BW, E].
  List<double> toOrderedList() => [ra, lc, bl, bw, e];
}
