import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/weight_estimation/domain/entities/weight_features.dart';

void main() {
  group('WeightFeatures ordering contract tests (§9 & AGENTS.md rule 2)', () {
    test(
      'toOrderedList() returns exactly [RA, LC, BL, BW, E] in strict contract order',
      () {
        const features = WeightFeatures(
          ra: 0.21,
          lc: 246.8,
          bl: 121.3,
          bw: 44.1,
          e: 0.87,
        );

        final list = features.toOrderedList();

        expect(list.length, 5);
        expect(list[0], 0.21, reason: 'Index 0 must be RA (Relative Area)');
        expect(
          list[1],
          246.8,
          reason: 'Index 1 must be LC (Contour Perimeter)',
        );
        expect(list[2], 121.3, reason: 'Index 2 must be BL (Body Length)');
        expect(list[3], 44.1, reason: 'Index 3 must be BW (Body Width)');
        expect(list[4], 0.87, reason: 'Index 4 must be E (Eccentricity)');
      },
    );

    test('toJson and fromJson preserve feature names and values', () {
      const features = WeightFeatures(
        ra: 0.15,
        lc: 180.0,
        bl: 95.5,
        bw: 38.2,
        e: 0.72,
      );

      final json = features.toJson();
      expect(json['RA'], 0.15);
      expect(json['LC'], 180.0);
      expect(json['BL'], 95.5);
      expect(json['BW'], 38.2);
      expect(json['E'], 0.72);

      final reconstructed = WeightFeatures.fromJson(json);
      expect(reconstructed, features);
    });
  });
}
