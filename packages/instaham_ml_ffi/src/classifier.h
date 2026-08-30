#ifndef INSTAHAM_ML_CLASSIFIER_H
#define INSTAHAM_ML_CLASSIFIER_H

#include <string>

#include "health_input.h"
#include "manifest.h"
#include "onnx_runner.h"

namespace instaham_ml {

// Health-only: which input protocol the manifest asked for, and the pig region if the
// segmenter produced one. Pass nullptr for the view classifier, which always runs on the
// raw photo (section 1.1(a)). While health_input.cpp's region protocols are stubs this
// changes nothing about the pixels -- see health_input.h.
struct HealthInputOptions {
  HealthInputProtocol protocol = HealthInputProtocol::kFullFrame;
  const PigRegion* region = nullptr;  // optional, not owned
};

// Runs one GhostNetV3 classifier (view | health) end-to-end: decode -> resize-shorter-side
// -> center-crop -> normalize -> ORT session -> softmax -> label lookup. Returns a
// ready-to-serialize JSON envelope matching instaham_ml.h's classify_*_json doc comment.
// On any failure, `out_json` is still set to a well-formed error envelope and this
// returns false (caller maps that to the appropriate InstahamMlStatus).
bool run_classifier(OnnxRunner* runner, const ClassifierCapability& cap,
                     const std::string& image_path, std::string* out_json, int* error_code_out,
                     const HealthInputOptions* health_input = nullptr);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_CLASSIFIER_H
