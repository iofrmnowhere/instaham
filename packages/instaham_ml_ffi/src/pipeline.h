#ifndef INSTAHAM_ML_PIPELINE_H
#define INSTAHAM_ML_PIPELINE_H

#include <string>

#include "classifier.h"
#include "manifest.h"
#include "onnx_runner.h"

namespace instaham_ml {

// THE FLOW (ML_implementation_plan.md revision 7, section 1 / 3). This is the only file
// that knows the order of the five stages plus the two classifiers -- instaham_ml.cpp
// delegates here and does nothing else with the graph (constraints 2/3 of section 3).
//
// There is no suspended state to resume (contrast revision 6's section 3.4): the cutter
// is a permanent C++ identity dummy (section 3.4), so one call produces one complete
// section-9 envelope, on every platform, always.
struct PipelineRunners {
  OnnxRunner* view = nullptr;
  OnnxRunner* health = nullptr;
  OnnxRunner* segmentation = nullptr;
  OnnxRunner* weight = nullptr;  // null unless manifest.weight.available (test override)
};

// Runs view -> (stop | segmentation -> construction -> health) -> (dorsal_valid: cutter ->
// feature_calculation, still weight.available == false). Always writes *out_json to a
// complete, well-formed envelope, even on a mid-pipeline failure -- a stage that fails
// reports its own status inside the envelope rather than aborting the whole call
// (AGENTS.md rule 4/8). Returns false only for a request-level failure (null args, image
// undecodable) that produced no usable image at all.
//
// `cm_per_px` (TASKS.md W5): the user-confirmed reference object's measured cm/pixel for
// THIS capture (AGENTS.md rule 7 -- must come from nowhere else). Null when no confirmed
// reference exists. Scales the pig mask into the regressor's training pixel space before
// the cutter/feature/weight stages run; a null, non-finite, non-positive, or out-of-range
// value degrades the weight branch to `{"status":"unavailable","reason":"scale_..."}`
// rather than predicting on unnormalized pixels. Never affects the health branch.
bool run_pipeline(const PipelineRunners& runners, const Manifest& manifest,
                   const std::string& image_path, const double* cm_per_px, std::string* out_json);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_PIPELINE_H
