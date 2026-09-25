// docs/plan-phase-4/1-native-cascade.md: manifest.cpp's parsing of
// capabilities.health.cascade. Pure JSON parsing, no OpenCV/ORT -- same wiring as
// test_feature_domain.cpp -- so this builds and runs unconditionally.
//
// decide_health_second_stage() itself (health_input.cpp) is covered by test_health_input.cpp
// group 7; this file only covers turning the manifest's cascade block into
// ClassifierCapability::health_cascade_* fields.

#include "manifest.h"

#include <cassert>
#include <cstdio>
#include <fstream>
#include <string>

using instaham_ml::load_manifest;
using instaham_ml::Manifest;

namespace {

// Writes a minimal health-available manifest with classes.json alongside it, and
// `cascade_json` spliced in verbatim as capabilities.health.cascade (empty string omits the
// key entirely). Model/classes sha256 fields are left empty -- manifest.cpp's verify_hash()
// treats an empty `expected` as "not referenced" and always passes, so this fixture needs no
// real .onnx file on disk.
void write_fixture_manifest(const std::string& manifest_path, const std::string& classes_path,
                             const std::string& cascade_json) {
  {
    std::ofstream f(classes_path);
    f << R"({"Healthy": 0, "Sunburn": 1, "Ringworm": 2})";
  }
  std::ofstream f(manifest_path);
  f << R"({
    "schema_version": 1,
    "capabilities": {
      "health": {
        "available": true,
        "model": {"path": "health/model.onnx", "sha256": "", "architecture": "ghostnetv3_100",
                  "opset": 17, "input": {"size": [224, 224]}},
        "class_map": {"path": ")"
    << classes_path << R"(", "sha256": ""},
        "preprocessing": {},
        "protocol_version": "health_v1")"
    << (cascade_json.empty() ? "" : (",\n        \"cascade\": " + cascade_json)) << R"(
      }
    }
  })";
}

}  // namespace

int main() {
  const std::string manifest_path = "test_health_cascade_manifest.json";
  const std::string classes_path = "test_health_cascade_classes.json";

  // ---- block absent: cascade stays disabled, no reason recorded ----
  {
    write_fixture_manifest(manifest_path, classes_path, "");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(manifest_path, &manifest, &error, &error_code));
    assert(manifest.health.health_cascade_enabled == false);
    assert(manifest.health.health_cascade_disabled_reason.empty());
  }

  // ---- explicitly disabled ----
  {
    write_fixture_manifest(manifest_path, classes_path,
                           R"({"enabled": false, "healthy_label": "Healthy",
                                "second_stage_protocol": "segmentation_masked"})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(manifest_path, &manifest, &error, &error_code));
    assert(manifest.health.health_cascade_enabled == false);
  }

  // ---- enabled, valid: healthy_label resolves against classes.json ----
  {
    write_fixture_manifest(manifest_path, classes_path,
                           R"({"enabled": true, "healthy_label": "Healthy",
                                "second_stage_protocol": "segmentation_masked"})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(manifest_path, &manifest, &error, &error_code));
    assert(manifest.health.health_cascade_enabled == true);
    assert(manifest.health.health_healthy_label == "Healthy");
    assert(manifest.health.health_second_stage_protocol == "segmentation_masked");
    assert(manifest.health.health_cascade_disabled_reason.empty());
  }

  // ---- enabled, unknown second_stage_protocol: disables, does not fail the load ----
  {
    write_fixture_manifest(manifest_path, classes_path,
                           R"({"enabled": true, "healthy_label": "Healthy",
                                "second_stage_protocol": "abnormality_crop"})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(manifest_path, &manifest, &error, &error_code));
    assert(manifest.health.health_cascade_enabled == false);
    assert(!manifest.health.health_cascade_disabled_reason.empty());
  }

  // ---- enabled, healthy_label missing from classes.json: disables, does not fail the load
  // (AGENTS.md rule 4 -- a health-input problem never blocks the health branch) ----
  {
    write_fixture_manifest(manifest_path, classes_path,
                           R"({"enabled": true, "healthy_label": "NoSuchClass",
                                "second_stage_protocol": "segmentation_masked"})");
    Manifest manifest;
    std::string error;
    int error_code = 0;
    assert(load_manifest(manifest_path, &manifest, &error, &error_code));
    assert(manifest.health.health_cascade_enabled == false);
    assert(!manifest.health.health_cascade_disabled_reason.empty());
  }

  std::puts("test_health_cascade_manifest: all assertions passed");
  return 0;
}
