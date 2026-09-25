#ifndef INSTAHAM_ML_STAGES_VIEW_ROUTE_H
#define INSTAHAM_ML_STAGES_VIEW_ROUTE_H

#include <string>

namespace instaham_ml {
namespace stages {

// docs/fix-phase-6/1-native-route-override.md (F68): the route decision pipeline.cpp acts
// on, pulled out of run_pipeline() into a pure, model-free function so it is unit-testable
// (test_view_route.cpp) without ORT -- the same pattern as invariants.h/canvas_scale.h/
// mask_geometry.h. `stopped` means the pipeline reports view_rejected and runs nothing else
// (the pre-round-9 behaviour); `unresolved` means the view label is missing/unrecognised and
// every downstream stage is reported skipped (AGENTS.md rule 8, fail closed).
enum class ViewRoute { kDorsal, kHealthOnly, kStopped, kUnresolved };

// `override_route` is "" (none), "dorsal_valid", or "health_only" -- any other string is
// treated as "" by the caller before this function ever sees it (request parsing lives in
// instaham_ml.cpp, not here). See the table in fix-phase-6/1-native-route-override.md:
// an override never downgrades a clean dorsal_valid verdict, and a `reject` with no override
// still stops exactly as before round 10.
inline ViewRoute resolve_view_route(const std::string& view_label,
                                     const std::string& override_route) {
  if (view_label == "dorsal_valid") return ViewRoute::kDorsal;
  if (view_label == "health_only") {
    if (override_route == "dorsal_valid") return ViewRoute::kDorsal;
    return ViewRoute::kHealthOnly;
  }
  if (view_label == "reject") {
    if (override_route == "dorsal_valid") return ViewRoute::kDorsal;
    if (override_route == "health_only") return ViewRoute::kHealthOnly;
    return ViewRoute::kStopped;
  }
  return ViewRoute::kUnresolved;
}

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_VIEW_ROUTE_H
