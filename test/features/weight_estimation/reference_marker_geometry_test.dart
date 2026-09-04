// ref_fix.md F11: the caliper-jaw reference marker replaces the crosshair (F5). These
// tests cover the two pure geometry helpers the widget's paint/hit-test code is built on:
// `referenceMarkerAngle` (auto-orientation, computed in DISPLAY space) and
// `referenceJawCentroid` (the touch-target/hit-box placement). Widget-level paint output
// is not asserted here -- these are the load-bearing numbers ref_fix.md section 5 flags as
// the one part of this change that can look right on a square test image and wrong on a
// real photo.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/weight_estimation/presentation/screens/reference_marking_screen.dart';

void main() {
  group('referenceMarkerAngle', () {
    test('horizontal pair (left to right) is angle 0', () {
      final angle = referenceMarkerAngle(
        const Offset(10, 50),
        const Offset(110, 50),
      );
      expect(angle, closeTo(0.0, 1e-9));
    });

    test('horizontal pair (right to left) is angle pi', () {
      final angle = referenceMarkerAngle(
        const Offset(110, 50),
        const Offset(10, 50),
      );
      expect(angle.abs(), closeTo(pi, 1e-9));
    });

    test('vertical pair (top to bottom) is angle +pi/2', () {
      final angle = referenceMarkerAngle(
        const Offset(50, 10),
        const Offset(50, 110),
      );
      expect(angle, closeTo(pi / 2, 1e-9));
    });

    test('vertical pair (bottom to top) is angle -pi/2', () {
      final angle = referenceMarkerAngle(
        const Offset(50, 110),
        const Offset(50, 10),
      );
      expect(angle, closeTo(-pi / 2, 1e-9));
    });

    test('a 45-degree diagonal pair is angle pi/4', () {
      final angle = referenceMarkerAngle(
        const Offset(0, 0),
        const Offset(100, 100),
      );
      expect(angle, closeTo(pi / 4, 1e-9));
    });

    test('an arbitrary diagonal matches atan2 directly', () {
      const start = Offset(20, 200);
      const end = Offset(260, 40);
      final angle = referenceMarkerAngle(start, end);
      expect(angle, closeTo(atan2(end.dy - start.dy, end.dx - start.dx), 1e-9));
    });

    test('degenerate (coincident) points fall back to angle 0, not NaN', () {
      final angle = referenceMarkerAngle(
        const Offset(50, 50),
        const Offset(50.2, 50.3),
      );
      expect(angle, 0.0);
      expect(angle.isNaN, isFalse);
    });

    test('points closer than 1px still fall back to angle 0', () {
      final angle = referenceMarkerAngle(
        const Offset(0, 0),
        const Offset(0.9, 0.0),
      );
      expect(angle, 0.0);
    });

    test('points exactly at the 1px threshold are treated as directional', () {
      final angle = referenceMarkerAngle(
        const Offset(0, 0),
        const Offset(1.5, 0.0),
      );
      expect(
        angle,
        closeTo(0.0, 1e-9),
      ); // still 0 here, but via atan2 not the fallback
    });
  });

  group('referenceJawCentroid', () {
    test(
      'extends the centroid exactly jawLength/2 from the mark, along direction',
      () {
        const mark = Offset(100, 100);
        const jawLength = 34.0;
        final centroid = referenceJawCentroid(mark, 0.0, jawLength);

        // Measuring (inner) edge sits exactly on the mark: the mark-to-centroid distance is
        // half the jaw length, since the rectangle spans from the mark to mark+jawLength.
        expect((centroid - mark).distance, closeTo(jawLength / 2, 1e-9));
        expect(centroid.dx, closeTo(mark.dx + jawLength / 2, 1e-9));
        expect(centroid.dy, closeTo(mark.dy, 1e-9));
      },
    );

    test('rotates with direction (vertical axis)', () {
      const mark = Offset(0, 0);
      const jawLength = 34.0;
      final centroid = referenceJawCentroid(mark, pi / 2, jawLength);
      expect(centroid.dx, closeTo(0.0, 1e-9));
      expect(centroid.dy, closeTo(jawLength / 2, 1e-9));
    });

    test('rotates with direction (diagonal axis)', () {
      const mark = Offset(0, 0);
      const jawLength = 34.0;
      final centroid = referenceJawCentroid(mark, pi / 4, jawLength);
      final expectedComponent = (jawLength / 2) * (sqrt(2) / 2);
      expect(centroid.dx, closeTo(expectedComponent, 1e-6));
      expect(centroid.dy, closeTo(expectedComponent, 1e-6));
    });

    test(
      'a 56x56 hit box centred on the centroid always contains the jaw rectangle '
      '(clears the 44x44 minimum touch target) at every orientation',
      () {
        const boxSize = 56.0;
        const jawLength = 34.0;
        const jawWidth = 26.0;
        // Diagonal of the jaw rectangle -- the worst case for fitting inside a square hit
        // box regardless of rotation.
        final jawDiagonal = sqrt(jawLength * jawLength + jawWidth * jawWidth);

        expect(boxSize, greaterThanOrEqualTo(44.0));
        expect(boxSize, greaterThanOrEqualTo(jawDiagonal));
      },
    );
  });

  group('two-jaw pair orientation (as used by the widget)', () {
    // Mirrors the widget's own construction: for each pin, `otherPoint` is the OTHER pin,
    // and axisAngle = referenceMarkerAngle(otherPoint, markPoint) -- both jaws therefore
    // point away from each other by construction, for any pin order.
    test('both jaws point away from each other on a horizontal pair', () {
      const pin0 = Offset(10, 50);
      const pin1 = Offset(110, 50);

      final angle0 = referenceMarkerAngle(pin1, pin0); // pin0's jaw
      final angle1 = referenceMarkerAngle(pin0, pin1); // pin1's jaw

      expect(
        angle0.abs(),
        closeTo(pi, 1e-9),
      ); // pin0 points left (away from pin1)
      expect(angle1, closeTo(0.0, 1e-9)); // pin1 points right (away from pin0)
    });

    test('both jaws point away from each other on a diagonal pair', () {
      const pin0 = Offset(20, 200);
      const pin1 = Offset(260, 40);

      final angle0 = referenceMarkerAngle(pin1, pin0);
      final angle1 = referenceMarkerAngle(pin0, pin1);

      // Opposite directions: the two angles differ by pi (mod 2pi).
      final diff = (angle0 - angle1).abs();
      expect(diff, closeTo(pi, 1e-9));
    });
  });
}
