#pragma once

namespace instaham {

struct PostureConfig {
    // Preserve the research decision currently used by InstaHAM.
    double maxBendDegree = 40.0;
    double straightReferenceDegree = 180.0;
};

struct PostureResult {
    bool valid = false;

    // Current app policy: reject invalid geometry and bends over threshold.
    bool reject = true;
    bool accepted = false;

    double bodyCurve = 0.0;
    double bendDegree = 0.0;
    double maxBendDegree = 40.0;
};

class PostureGate {
public:
    explicit PostureGate(PostureConfig config = {});

    // bodyCurve is the body-curve angle produced by the existing
    // post-segmentation morphology step. A straight pig is treated as ~180°.
    PostureResult analyze(double bodyCurve) const noexcept;

    const PostureConfig& config() const noexcept { return config_; }

private:
    PostureConfig config_;
};

}  // namespace instaham
