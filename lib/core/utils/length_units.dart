enum LengthUnit { cm, inch }

extension LengthUnitX on LengthUnit {
  String get label => this == LengthUnit.cm ? 'cm' : 'in';

  double toCm(double value) => this == LengthUnit.cm ? value : value * 2.54;

  double fromCm(double cm) => this == LengthUnit.cm ? cm : cm / 2.54;

  String format(double cm, {int decimals = 1}) {
    final val = fromCm(cm);
    if (val == val.roundToDouble()) {
      return val.toStringAsFixed(0);
    }
    return val.toStringAsFixed(decimals);
  }
}
