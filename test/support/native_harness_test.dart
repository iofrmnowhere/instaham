// docs/metrics-plan.md phase 2 deliverable: smoke test for test/support/native_harness.dart.
//
// Gated on INSTAHAM_NATIVE_TESTS=1 and a loadable instaham_ml.dll (see native_harness.dart);
// on a machine without either, this reports a skip with the harness's own precise reason
// instead of failing, matching the two-tier convention the phase 4 scenario tests will use.
import 'package:flutter_test/flutter_test.dart';

import 'native_harness.dart';

void main() {
  test(
    'native harness loads the on-disk manifest and reports its feature family',
    () {
      final load = NativeHarness.load();
      switch (load) {
        case NativeHarnessSkip(:final reason):
          markTestSkipped(reason);
          return;
        case NativeHarnessReady(:final harness):
          addTearDown(harness.dispose);
          expect(harness.manifestPath, endsWith('assets/ml/manifest.json'));
          // AGENTS.md rule 2: the feature family comes from the manifest, never hardcoded --
          // assert only that the harness surfaced *some* manifest-declared value, not a
          // specific family name, so this test does not itself hardcode the family.
          expect(harness.featureFamily, isNotNull);
          expect(harness.featureFamily, isNotEmpty);
      }
    },
  );
}
