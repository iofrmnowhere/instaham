import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/models/scan_flow.dart';

void main() {
  group('ReferenceSelection model tests', () {
    test('1-meter stick preset has correct name and length', () {
      expect(ReferenceSelection.meterStick.type, 'meter_stick');
      expect(ReferenceSelection.meterStick.name, '1-meter stick');
      expect(ReferenceSelection.meterStick.lengthCm, 100);
    });

    test('Porac stick preset has correct name and length', () {
      expect(ReferenceSelection.poracStick.type, 'porac_stick');
      expect(ReferenceSelection.poracStick.name, 'Porac stick');
      expect(ReferenceSelection.poracStick.lengthCm, 131);
    });

    test('Custom reference with positive length succeeds', () {
      const custom = ReferenceSelection(
        type: 'custom',
        name: 'Custom Ruler',
        lengthCm: 50.5,
      );
      expect(custom.name, 'Custom Ruler');
      expect(custom.lengthCm, 50.5);
    });

    test(
      'Custom reference with zero or negative length throws AssertionError',
      () {
        expect(
          () => ReferenceSelection(
            type: 'custom',
            name: 'Zero Length',
            lengthCm: 0,
          ),
          throwsA(isA<AssertionError>()),
        );

        expect(
          () => ReferenceSelection(
            type: 'custom',
            name: 'Negative Length',
            lengthCm: -15,
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });
}
