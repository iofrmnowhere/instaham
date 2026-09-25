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
//
// `view_route_override` (docs/fix-phase-6/1-native-route-override.md, F68 -- supersedes the
// fix-phase-5/2-view-reject-override.md boolean): "" (none), "dorsal_valid", or
// "health_only". Routes the photo per stages::resolve_view_route() (stages/view_route.h)
// instead of the label alone deciding it: a "reject" can now run as either dorsal or
// health-only, and a "health_only" can be promoted to dorsal; a "dorsal_valid" verdict is
// never downgraded. The stored `view` label is untouched -- the envelope's `view` block
// gains `"override": true` plus `"override_route"` whenever the override actually changed
// the route (a no-op override, e.g. health_only -> health_only, leaves the block exactly as
// today). Does not weaken any other eligibility or quality check (truncation, posture,
// scale, feature-domain). Defaults to "" (none), matching every existing caller.
bool run_pipeline(const PipelineRunners& runners, const Manifest& manifest,
                   const std::string& image_path, const double* cm_per_px,
                   std::string* out_json, const std::string& view_route_override = "");

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_PIPELINE_H
