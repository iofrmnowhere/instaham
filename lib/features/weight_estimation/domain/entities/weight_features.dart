/// Domain entity holding extracted dorsal morphological features for weight regression.
/// Feature order is strictly contract-fixed: [RA, LC, BL, BW, E].
class WeightFeatures {
  /// Relative area (pig dorsal-core area / image area, dimensionless).
  final double ra;

  /// Dorsal-core contour perimeter in centimeters.
  final double lc;

  /// Body length (longer side of minimum-area bounding box) in centimeters.
  final double bl;

  /// Body width (shorter side of minimum-area bounding box) in centimeters.
  final double bw;

  /// Fitted-ellipse eccentricity (dimensionless, in [0, 1)).
  final double e;

  const WeightFeatures({
    required this.ra,
    required this.lc,
    required this.bl,
    required this.bw,
    required this.e,
  });

  /// Returns features in the contract-fixed training order: [RA, LC, BL, BW, E].
  List<double> toOrderedList() => [ra, lc, bl, bw, e];

  Map<String, dynamic> toJson() => {
    'RA': ra,
    'LC': lc,
    'BL': bl,
    'BW': bw,
    'E': e,
  };

  factory WeightFeatures.fromJson(Map<String, dynamic> json) => WeightFeatures(
    ra: (json['RA'] as num).toDouble(),
    lc: (json['LC'] as num).toDouble(),
    bl: (json['BL'] as num).toDouble(),
    bw: (json['BW'] as num).toDouble(),
    e: (json['E'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeightFeatures &&
          runtimeType == other.runtimeType &&
          ra == other.ra &&
          lc == other.lc &&
          bl == other.bl &&
          bw == other.bw &&
          e == other.e;

  @override
  int get hashCode => Object.hash(ra, lc, bl, bw, e);
}
