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

// docs/plan-4.md / docs/plan-phase-4/1-native-cascade.md: runs the health classifier once,
// then -- only when `cap.health_cascade_enabled` and the first label is not
// `cap.health_healthy_label` and `region` gives a usable mask -- runs it a second time with
// `cap.health_second_stage_protocol`, and reports that second result as the final one.
// `region` is the same PigRegion the caller already built for the first pass; pass nullptr
// when there is none (e.g. the health_only route). The single-pass envelope (`label`,
// `confidence`, `probabilities`, `input_protocol_*`, `region_source`) is unchanged by this
// function, at the same keys, so an existing reader does not need to change; a `cascade`
// object is added alongside it -- see the header comment on HealthInputOptions and
// docs/plan-phase-4/1-native-cascade.md for its shape. With the cascade disabled by the
// manifest, the output is byte-for-byte run_classifier()'s own output (no `cascade` key).
//
// On the first pass's failure, this returns exactly what run_classifier() would return.
// A failing or degraded second pass never discards the first pass's result (AGENTS.md rule
// 4: a health-input problem must never block the health branch) -- it is recorded in
// `cascade.second_stage` and the first pass's envelope is kept as final.
bool run_health_cascade(OnnxRunner* runner, const ClassifierCapability& cap,
                        const std::string& image_path, const PigRegion* region,
                        std::string* out_json, int* error_code_out);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_CLASSIFIER_H
