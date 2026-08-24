import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Model-Parity Tests (§14)', () {
    // Tolerances specified in §14
    const viewConfidenceTolerance = 0.01;
    const healthConfidenceTolerance = 0.01;
    const featureRelativeTolerance = 0.005; // ±0.5%
    const weightAbsoluteToleranceKg = 0.5;

    // TODO(ml-service): un-skip once concrete ML services and test fixtures are merged.
    // Milestone: when concrete ML service is merged.
    test(
      'View suitability model output parity against Python reference',
      () async {
        // Placeholder comparing view probabilities against Python ground truth
        expect(viewConfidenceTolerance, 0.01);
      },
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Health classification model output parity against Python reference',
      () async {
        // Placeholder comparing health probabilities against Python ground truth
        expect(healthConfidenceTolerance, 0.01);
      },
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Feature extraction parity for [RA, LC, BL, BW, E] against Python reference',
      () async {
        // Placeholder verifying feature extraction numerical tolerance
        expect(featureRelativeTolerance, 0.005);
      },
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'XGBoost weight prediction parity against Python reference',
      () async {
        // Placeholder verifying end-to-end weight estimation parity
        expect(weightAbsoluteToleranceKg, 0.5);
      },
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );
  });
}
