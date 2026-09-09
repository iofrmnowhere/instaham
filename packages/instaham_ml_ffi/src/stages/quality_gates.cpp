#include "stages/quality_gates.h"

#include <opencv2/core.hpp>

#include "vendor/instaham_v176/include/instaham/features/BodyCurve.hpp"
#include "vendor/instaham_v176/quality_gates/posture_gate/PostureGate.hpp"
#include "vendor/instaham_v176/quality_gates/truncation_gate/EdgeTruncationDetector.hpp"

namespace instaham_ml {
namespace stages {

TruncationGateResult run_truncation_gate(const MaskView& whole_mask) {
  TruncationGateResult out;
  out.ran = true;
  if (!whole_mask.valid()) {
    out.reject = true;  // fail closed, matching the vendor's own convention
    out.candidate_strength = "Error";
    return out;
  }

  cv::Mat mask(whole_mask.height, whole_mask.width, CV_8UC1,
               const_cast<uint8_t*>(whole_mask.data));
  instaham::EdgeTruncationDetector detector;
  instaham::TruncationResult result = detector.analyze(mask);

  out.valid = result.valid;
  out.reject = result.reject;  // vendor: analysis failure -> reject == true, fail closed
  out.candidate_strength = instaham::candidateStrengthName(result.candidateStrength);
  return out;
}

PostureGateResult run_posture_gate(const MaskView& whole_mask, double max_bend_deg) {
  PostureGateResult out;
  out.ran = true;
  if (!whole_mask.valid()) {
    out.reject = true;  // fail closed
    return out;
  }

  cv::Mat mask(whole_mask.height, whole_mask.width, CV_8UC1,
               const_cast<uint8_t*>(whole_mask.data));
  // Independent invocation of the same computeBodyCurve() the Chen16 feature vector later
  // calls again on the FINAL CUT mask -- never the same value, never cached across the two
  // (docs/plan-phase/2-native-cutter-chen16.md, "Two body-curve calls, not one").
  const double body_curve = instaham::computeBodyCurve(mask);
  out.body_curve_deg = body_curve;

  instaham::PostureConfig config;
  config.maxBendDegree = max_bend_deg;
  instaham::PostureGate gate(config);
  instaham::PostureResult result = gate.analyze(body_curve);

  out.valid = result.valid;
  out.reject = result.reject;  // vendor: invalid geometry also fails closed (reject == true)
  out.bend_deg = result.bendDegree;
  return out;
}

}  // namespace stages
}  // namespace instaham_ml
