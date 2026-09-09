#include "PostureGate.hpp"

#include <cmath>

namespace instaham {

PostureGate::PostureGate(PostureConfig config) : config_(config) {}

PostureResult PostureGate::analyze(double bodyCurve) const noexcept {
    PostureResult result;
    result.bodyCurve = bodyCurve;
    result.maxBendDegree = config_.maxBendDegree;

    // Preserve the original fail-closed behavior for invalid geometry.
    if (!std::isfinite(bodyCurve)) {
        return result;
    }

    // Preserve the original research logic exactly:
    // straight pig ~= 180° body curve; bend = 180 - bodyCurve.
    result.bendDegree = config_.straightReferenceDegree - bodyCurve;
    result.valid = true;
    result.accepted = result.bendDegree <= config_.maxBendDegree;
    result.reject = !result.accepted;
    return result;
}

}  // namespace instaham
