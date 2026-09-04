// ref_fix.md F8/F9: manifest.cpp's parsing of WeightCapability::FeatureDomain's
// lower_multiplier and WeightCapability::cm_per_px_target_uncertainty. Needs no OpenCV/ORT
// (manifest.cpp is pure JSON parsing), so -- unlike test_scale_normalization.cpp -- this
// builds and runs on every host, matching test_abi.cpp's / test_cutter_identity.cpp's
// unconditional wiring in CMakeLists.txt.
//
// pipeline.cpp's per-feature widening (RA by uncertainty^2, LC/BL/BW by uncertainty^1, E
// untouched) and its classify_domain_violation() reason selection are NOT covered here --
// both live in pipeline.cpp's anonymous namespace and depend on the OpenCV-gated stages/
// pipeline (segmentation/construction/cutter/feature_calculation), so they can only be
// exercised end-to-end on a device build, same limitation test_scale_normalization.cpp
// already documents for the rest of the OpenCV-gated pipeline.

#include "manifest.h"

#include <cassert>
#include <cstdio>
#include <fstream>
#include <string>

using instaham_ml::load_manifest;
using instaham_ml::Manifest;

namespace {

// Writes a minimal weight-available manifest to `path`. `feature_domain_json` is spliced
// in verbatim so each test can vary just that block. Regressor/model sha256 fields are
// left empty -- manifest.cpp's verify_hash() treats an empty `expected` as "not
// referenced" and always passes, so this fixture needs no real .onnx file on disk.
void write_fixture_manifest(const std::string& path, const std::string& capture_contract_extra,
                             const std::string& feature_domain_json) {
  std::ofstream f(path);
  f << R"({
    "schema_version": 1,
    "capabilities": {
      "weight": {
        "available": true,
        "regressor": {"path": "weight/xgboost.onnx", "sha256": ""},
        "feature_extractor": {"names": ["RA", "LC", "BL", "BW", "E"]},
        "capture_contract": {
          "training_camera_height_m": 1.88,
          "camera_height_is_xgboost_feature": false,
          "cm_per_px_target": 0.26,
          "training_frame_px": [720, 720])"
    << capture_contract_extra << R"(
        },
        "feature_domain": )"
    << feature_domain_json << R"(
      }
    }
  })";
}

}  // namespace

int main() {
  const std::string path = "test_feature_domain_manifest.json";

  // ---- lower_multiplier: explicit value is parsed ----
  {
    write_fixture_manifest(
        path, "",
        R"({"RA": {"min": 0.076, "max": 0.2042, "upper_multiplier": 1.0, "lower_multiplier": 0.9}})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(path, &manifest, &error, &error_code));
    assert(manifest.weight.domain_ra.lower_multiplier == 0.9);
    assert(manifest.weight.domain_ra.min == 0.076);
    assert(manifest.weight.domain_ra.max == 0.2042);
  }

  // ---- lower_multiplier: absent key defaults to 1.0 (backward compatible with a
  // pre-F8 manifest fragment that never wrote this field) ----
  {
    write_fixture_manifest(path, "", R"({"RA": {"min": 0.076, "max": 0.2042}})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(path, &manifest, &error, &error_code));
    assert(manifest.weight.domain_ra.lower_multiplier == 1.0);
  }

  // ---- cm_per_px_target_uncertainty: explicit value >= 1.0 is parsed as-is ----
  {
    write_fixture_manifest(path, R"(, "cm_per_px_target_uncertainty": 1.15)",
                            R"({"RA": {"min": 0.076, "max": 0.2042}})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(path, &manifest, &error, &error_code));
    assert(manifest.weight.cm_per_px_target_uncertainty == 1.15);
  }

  // ---- cm_per_px_target_uncertainty: absent key defaults to 1.0 (no widening) ----
  {
    write_fixture_manifest(path, "", R"({"RA": {"min": 0.076, "max": 0.2042}})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(path, &manifest, &error, &error_code));
    assert(manifest.weight.cm_per_px_target_uncertainty == 1.0);
  }

  // ---- cm_per_px_target_uncertainty: a value below 1.0 is clamped UP to 1.0, never
  // allowed to tighten a bound (AGENTS.md rule 8 -- this field may only ever widen) ----
  {
    write_fixture_manifest(path, R"(, "cm_per_px_target_uncertainty": 0.5)",
                            R"({"RA": {"min": 0.076, "max": 0.2042}})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(path, &manifest, &error, &error_code));
    assert(manifest.weight.cm_per_px_target_uncertainty == 1.0);
  }

  std::remove(path.c_str());
  std::puts("test_feature_domain: all assertions passed");
  return 0;
}
