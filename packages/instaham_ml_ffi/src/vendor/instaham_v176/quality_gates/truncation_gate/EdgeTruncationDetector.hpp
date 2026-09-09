#pragma once

#include <opencv2/core.hpp>

#include <string>

namespace instaham {

struct TruncationConfig {
    // V56 thresholds copied from 06V3_56_STRICTER_EDGE_TRUNCATION_EXCLUSION_REVIEW.
    double nearFrameFraction = 0.010;
    double veryNearFrameFraction = 0.0025;
    double minEndFrameAlignment = 0.55;

    double axialEndBandFraction = 0.06;
    double capDepthFraction = 0.08;
    int capBins = 25;

    double minBroadCapSpanRatio = 0.40;
    double maxFlatCapRatio = 0.16;
    double minTerminalRadiusRatio = 0.50;
};

enum class FrameSide : int {
    None = 0,
    Left = 1,
    Right = 2,
    Top = 3,
    Bottom = 4,
};

enum class CandidateStrength : int {
    Clear = 0,
    Review = 1,
    Strong = 2,
    Error = 3,
};

struct EndMetrics {
    cv::Point2d axisPoint{};
    FrameSide frameSide = FrameSide::None;

    double frameAlignment = 0.0;
    double frameMarginPx = 0.0;
    double frameMarginFraction = 0.0;
    double terminalRadiusRatio = 0.0;
    double capSpanRatio = 0.0;
    double capFlatnessRatio = 0.0;
    bool capFlatnessValid = false;

    bool veryNear = false;
    bool near = false;
    bool broad = false;
    bool flat = false;
    bool thick = false;
    bool candidate = false;
    bool strongCandidate = false;
};

struct TruncationResult {
    bool valid = false;

    // For the current InstaHAM app policy, reject == truncationCandidate.
    // Analysis failures also fail closed and return reject=true.
    bool reject = true;
    bool truncationCandidate = true;

    int imageHeightPx = 0;
    int imageWidthPx = 0;
    cv::Point2d pcaCenter{};
    cv::Vec2d majorAxis{0.0, 0.0};
    double axialLengthPx = 0.0;
    double maxRadiusPx = 0.0;

    EndMetrics low;
    EndMetrics high;

    // Bit mask: bit 0 = low end, bit 1 = high end.
    int candidateEndMask = 0;
    CandidateStrength candidateStrength = CandidateStrength::Error;

    std::string error;
};

class EdgeTruncationDetector {
public:
    explicit EdgeTruncationDetector(TruncationConfig config = {});

    // mask must be a single-channel binary segmentation mask in the same
    // coordinate frame as the captured image. Nonzero pixels are foreground.
    // Do not pass a letterboxed model-space mask with padding still present.
    TruncationResult analyze(const cv::Mat& mask) const;

    const TruncationConfig& config() const noexcept { return config_; }

private:
    TruncationConfig config_;
};

const char* frameSideName(FrameSide side) noexcept;
const char* candidateStrengthName(CandidateStrength strength) noexcept;

}  // namespace instaham
