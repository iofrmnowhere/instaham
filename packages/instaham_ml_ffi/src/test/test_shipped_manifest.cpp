// docs/metrics-plan.md phase 4 task 3: pins the live, shipped values behind the §7
// eligibility-check audit table, so a future manifest edit that silently flips a gate or
// drops a domain key fails this test instead of only being caught by re-reading the audit
// prose. Loads the REAL assets/ml/manifest.json (INSTAHAM_SHIPPED_MANIFEST_PATH, set by
// CMakeLists.txt), not a synthetic fixture like test_feature_domain.cpp uses -- the point
// here is "what does the app actually ship", not "does the parser handle this shape".
//
// Pure JSON parsing (manifest.cpp), no OpenCV/ORT, so this builds and runs unconditionally
// like test_feature_domain.cpp.
//
// What this does NOT cover: whether these values actually gate the pipeline at runtime
// (pipeline.cpp's stage wiring, exercised end-to-end only by the phase 2 native harness /
// phase 4 Tier B tests) and whether WeightEligibilityChecker (lib/, Dart) is ever called --
// grep-confirmed unreferenced outside its own definition and test file as of this task; that
// fact is architectural, not something a native unit test can pin.

#include "manifest.h"

#include <cassert>
#include <cstdio>

using instaham_ml::load_manifest;
using instaham_ml::Manifest;

int main() {
#ifndef INSTAHAM_SHIPPED_MANIFEST_PATH
#error "INSTAHAM_SHIPPED_MANIFEST_PATH not defined -- see CMakeLists.txt"
#endif

  Manifest manifest;
  std::string error;
  int error_code = 0;
  const bool loaded =
      load_manifest(INSTAHAM_SHIPPED_MANIFEST_PATH, &manifest, &error, &error_code);
  if (!loaded) {
    std::fprintf(stderr, "load_manifest(%s) failed: %s\n", INSTAHAM_SHIPPED_MANIFEST_PATH,
                 error.c_str());
  }
  assert(loaded);

  // §7 checks 2 and 4: the truncation and posture quality gates are OFF as shipped. Checks
  // 2/3/4 have no live enforcement until one of these flips true.
  assert(manifest.weight.quality_gate_truncation == false);
  assert(manifest.weight.quality_gate_posture == false);
  assert(manifest.weight.quality_gate_posture_max_bend_deg == 40.0);

  // §7 check 9: the shipped family is chen16_noheight (16 features), not baseline5 --
  // AGENTS.md rule 2 / docs/adr/007-manifest-declared-feature-family.md. A test asserting
  // WeightEligibilityChecker's bl/bw/e/ra/lc sanity checks would be testing quantities this
  // family never produces (see this task's audit note in docs/metrics-plan.md).
  assert(manifest.weight.feature_family == "chen16_noheight");
  assert(manifest.weight.feature_order.size() == 16);

  // §7 check 9's live mechanism: min_mask_diagonal_fraction and per-feature domain gates,
  // not the dead WeightEligibilityChecker sanity checks.
  assert(manifest.weight.min_mask_diagonal_fraction == 0.35);
  assert(manifest.weight.feature_domain.count("mask_area") == 1);
  assert(manifest.weight.feature_domain.count("body_curve") == 1);

  // docs/plan-4.md / docs/plan-phase-4/1-native-cascade.md: the shipped two-stage cascade.
  // healthy_label must have resolved against health/classes.json (manifest.cpp checks it
  // after loading class_names), so this also pins that "Healthy" is a real class name.
  assert(manifest.health.health_cascade_enabled == true);
  assert(manifest.health.health_healthy_label == "Healthy");
  assert(manifest.health.health_second_stage_protocol == "segmentation_masked");
  assert(manifest.health.health_cascade_disabled_reason.empty());

  std::puts("test_shipped_manifest: all assertions passed");
  return 0;
}
