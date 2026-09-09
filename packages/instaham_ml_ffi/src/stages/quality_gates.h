#ifndef INSTAHAM_ML_STAGES_QUALITY_GATES_H
#define INSTAHAM_ML_STAGES_QUALITY_GATES_H

#include <string>

#include "stages/cutter.h"  // MaskView

namespace instaham_ml {
namespace stages {

// TRUNCATION + POSTURE quality gates, ported in phase 2
// (vendor/instaham_v176/quality_gates/), wired here in phase 3 behind the manifest's
// weight.quality_gates switch (docs/plan-phase/3-manifest-pipeline.md, "The quality gates
// get a manifest switch"). Both gates run on the WHOLE YOLO mask in ORIGINAL CAPTURE
// COORDINATES, before Ji/Duan and before any scale-to-training-space resampling
// (vendor README_AI_INTEGRATION.md: the truncation gate "must receive the mask in
// original capture coordinates, not the letterboxed model frame"; vendor README.md/
// VALIDATION.md: both gates run pre-Ji/Duan). Status only, no user-facing strings --
// pipeline.cpp assigns the reason/user_message_key, matching README_AI_INTEGRATION.md's
// "gates must not call each other, and must return status only" and its own convention
// that a gate's own analysis failure fails closed (rejects) rather than passing through.

struct TruncationGateResult {
  bool ran = false;    // false when the manifest switch left this gate disabled
  bool valid = false;  // vendor analysis succeeded (fail-closed: false also rejects)
  bool reject = false;
  std::string candidate_strength;  // "Clear" | "Review" | "Strong" | "Error"
};

TruncationGateResult run_truncation_gate(const MaskView& whole_mask);

struct PostureGateResult {
  bool ran = false;
  bool valid = false;
  bool reject = false;
  double body_curve_deg = 0.0;  // "postureBodyCurve" -- see the note below
  double bend_deg = 0.0;        // 180 - body_curve_deg
};

// `body_curve_deg` here is computed independently of the Chen16 `body_curve` feature
// computed later (phase 2) on the final cut mask -- docs/plan-phase/2-native-cutter-
// chen16.md, "Two body-curve calls, not one": same underlying algorithm
// (instaham::computeBodyCurve), two separate invocations on two different masks, and the
// numeric result must never be cached and reused across them.
PostureGateResult run_posture_gate(const MaskView& whole_mask, double max_bend_deg);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_QUALITY_GATES_H
