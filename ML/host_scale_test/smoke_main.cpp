// docs/test-plan-phase/1-host-toolchain.md smoke test: proves the standalone host build
// links OpenCV, the app's stage sources, the vendor V176/V144 cutter+feature sources, and
// the host-generated onnxruntime.lib import library, and that OnnxRunner can actually load
// a real graph (not just link) -- this is what confirms the ORT DLL wiring works end to
// end rather than merely compiling.
//
// Replaced by weight_branch_cli.cpp in phase 2.

#include <cstdio>
#include <string>

#include "manifest.h"
#include "onnx_runner.h"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: %s <repo_root>\n", argv[0]);
    return 2;
  }
  const std::string repo_root = argv[1];
  const std::string manifest_path = repo_root + "/assets/ml/manifest.json";

  instaham_ml::Manifest manifest;
  std::string error;
  int error_code = 0;
  if (!instaham_ml::load_manifest(manifest_path, &manifest, &error, &error_code)) {
    std::fprintf(stderr, "load_manifest failed: %s (code %d)\n", error.c_str(), error_code);
    return 1;
  }
  std::printf("manifest loaded ok. weight.available=%d cm_per_px_target=%.6f\n",
              manifest.weight.available, manifest.weight.cm_per_px_target);

  instaham_ml::OnnxRunner runner;
  std::string ort_error;
  if (!runner.load(manifest.weight.model_path, &ort_error)) {
    std::fprintf(stderr, "OnnxRunner::load failed: %s\n", ort_error.c_str());
    return 1;
  }
  std::printf("onnxruntime session loaded ok: %s\n", manifest.weight.model_path.c_str());
  return 0;
}
