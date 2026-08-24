import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Functional Scenarios Tests (§14)', () {
    // TODO(ml-service): un-skip once IViewModelService has a concrete implementation.
    // Milestone: when concrete ML service is merged.

    test(
      'Scenario 1: Valid dorsal image with 100 cm reference stick',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 2: Valid dorsal image with 131 cm Porac stick reference',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 3: Valid dorsal image with custom positive reference length',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 4: Dorsal image without reference -> weight blocked, health assessed',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 5: Side-view image -> weight blocked, visual health classified',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 6: Close-up lesion image -> visual health classified with confidence',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 7: Multiple-pig image -> multiple_pigs failure reason, weight blocked',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 8: Blurry image -> low-confidence/reject state, prompts retake',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 9: Partially cropped pig -> pig_truncated failure reason',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 10: Partially hidden reference -> endpoints_too_close or invalid length',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );

    test(
      'Scenario 11: HEIC / JPEG / PNG inputs supported and processed accurately',
      () async {},
      skip:
          'Needs concrete ML service — see AGENTS.md §Critical inference rules',
    );
  });
}
