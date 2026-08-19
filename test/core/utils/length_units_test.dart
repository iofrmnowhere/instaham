import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/utils/length_units.dart';

void main() {
  group('LengthUnit conversions and formatting', () {
    test('cm unit conversions', () {
      expect(LengthUnit.cm.label, 'cm');
      expect(LengthUnit.cm.toCm(50), 50);
      expect(LengthUnit.cm.fromCm(50), 50);
      expect(LengthUnit.cm.format(50), '50');
      expect(LengthUnit.cm.format(50.5), '50.5');
    });

    test('inch unit conversions', () {
      expect(LengthUnit.inch.label, 'in');
      expect(LengthUnit.inch.toCm(10), closeTo(25.4, 0.001));
      expect(LengthUnit.inch.fromCm(25.4), closeTo(10, 0.001));
      expect(LengthUnit.inch.format(25.4), '10');
      expect(LengthUnit.inch.format(100), '39.4');
    });
  });
}
