#ifndef INSTAHAM_ML_CLASSIFIER_H
#define INSTAHAM_ML_CLASSIFIER_H

#include <string>

#include "manifest.h"
#include "onnx_runner.h"

namespace instaham_ml {

// Runs one GhostNetV3 classifier (view | health) end-to-end: decode -> resize-shorter-side
// -> center-crop -> normalize -> ORT session -> softmax -> label lookup. Returns a
// ready-to-serialize JSON envelope matching instaham_ml.h's classify_*_json doc comment.
// On any failure, `out_json` is still set to a well-formed error envelope and this
// returns false (caller maps that to the appropriate InstahamMlStatus).
bool run_classifier(OnnxRunner* runner, const ClassifierCapability& cap,
                     const std::string& image_path, std::string* out_json, int* error_code_out);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_CLASSIFIER_H
