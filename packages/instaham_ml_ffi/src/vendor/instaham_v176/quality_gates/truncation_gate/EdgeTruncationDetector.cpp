#include "EdgeTruncationDetector.hpp"

#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <utility>
#include <vector>

namespace instaham {
namespace {

constexpr double kEps = 1e-9;

struct PcaGeometry {
    cv::Mat binaryMask;
    std::vector<cv::Point> points;
    std::vector<double> t;
    std::vector<double> s;

    cv::Point2d center{};
    cv::Vec2d major{0.0, 0.0};
    cv::Vec2d minor{0.0, 0.0};

    double tMin = 0.0;
    double tMax = 0.0;
    double sMin = 0.0;
    double sMax = 0.0;
};

struct FrameChoice {
    FrameSide side = FrameSide::None;
    double alignment = 0.0;
    double marginPx = 0.0;
    double marginFraction = 0.0;
};

struct CapShape {
    double spanRatio = 0.0;
    double flatnessRatio = std::numeric_limits<double>::quiet_NaN();
    int profileBins = 0;
};

cv::Vec2d normalized(const cv::Vec2d& v) {
    const double n = std::sqrt(v[0] * v[0] + v[1] * v[1]);
    if (n <= kEps) {
        throw std::runtime_error("Degenerate PCA major axis.");
    }
    return cv::Vec2d(v[0] / n, v[1] / n);
}

double dot(const cv::Vec2d& a, const cv::Vec2d& b) {
    return a[0] * b[0] + a[1] * b[1];
}

cv::Point2d addScaled(const cv::Point2d& p, const cv::Vec2d& v, double scale) {
    return cv::Point2d(p.x + v[0] * scale, p.y + v[1] * scale);
}

PcaGeometry computePcaGeometry(const cv::Mat& inputMask) {
    if (inputMask.empty()) {
        throw std::runtime_error("Mask is empty.");
    }
    if (inputMask.channels() != 1) {
        throw std::runtime_error("Mask must be single-channel.");
    }

    PcaGeometry g;
    cv::compare(inputMask, 0, g.binaryMask, cv::CMP_GT);  // 0 or 255, CV_8U.
    cv::findNonZero(g.binaryMask, g.points);

    if (g.points.size() < 20) {
        throw std::runtime_error("Too few foreground pixels.");
    }

    double sumX = 0.0;
    double sumY = 0.0;
    for (const auto& p : g.points) {
        sumX += static_cast<double>(p.x);
        sumY += static_cast<double>(p.y);
    }

    const double n = static_cast<double>(g.points.size());
    g.center = cv::Point2d(sumX / n, sumY / n);

    double cxx = 0.0;
    double cxy = 0.0;
    double cyy = 0.0;
    for (const auto& p : g.points) {
        const double dx = static_cast<double>(p.x) - g.center.x;
        const double dy = static_cast<double>(p.y) - g.center.y;
        cxx += dx * dx;
        cxy += dx * dy;
        cyy += dy * dy;
    }
    cxx /= n;
    cxy /= n;
    cyy /= n;

    cv::Mat covariance = (cv::Mat_<double>(2, 2) << cxx, cxy, cxy, cyy);
    cv::Mat eigenValues;
    cv::Mat eigenVectors;
    if (!cv::eigen(covariance, eigenValues, eigenVectors)) {
        throw std::runtime_error("PCA eigen decomposition failed.");
    }

    // cv::eigen returns eigenvectors as rows, descending by eigenvalue.
    g.major = normalized(cv::Vec2d(
        eigenVectors.at<double>(0, 0),
        eigenVectors.at<double>(0, 1)));

    // Match the notebook's deterministic sign convention exactly.
    if (std::abs(g.major[0]) >= std::abs(g.major[1])) {
        if (g.major[0] < 0.0) {
            g.major = -g.major;
        }
    } else {
        if (g.major[1] < 0.0) {
            g.major = -g.major;
        }
    }

    g.minor = cv::Vec2d(-g.major[1], g.major[0]);

    g.t.reserve(g.points.size());
    g.s.reserve(g.points.size());

    g.tMin = std::numeric_limits<double>::infinity();
    g.tMax = -std::numeric_limits<double>::infinity();
    g.sMin = std::numeric_limits<double>::infinity();
    g.sMax = -std::numeric_limits<double>::infinity();

    for (const auto& p : g.points) {
        const cv::Vec2d centered(
            static_cast<double>(p.x) - g.center.x,
            static_cast<double>(p.y) - g.center.y);

        const double t = dot(centered, g.major);
        const double s = dot(centered, g.minor);
        g.t.push_back(t);
        g.s.push_back(s);

        g.tMin = std::min(g.tMin, t);
        g.tMax = std::max(g.tMax, t);
        g.sMin = std::min(g.sMin, s);
        g.sMax = std::max(g.sMax, s);
    }

    return g;
}

std::pair<double, double> frameMarginForSide(
    const std::vector<cv::Point2d>& endPoints,
    FrameSide side,
    int width,
    int height) {

    if (endPoints.empty()) {
        throw std::runtime_error("Axial end contains no foreground pixels.");
    }

    double marginPx = std::numeric_limits<double>::infinity();

    switch (side) {
        case FrameSide::Left:
            for (const auto& p : endPoints) marginPx = std::min(marginPx, p.x);
            return {marginPx, marginPx / std::max(width, 1)};

        case FrameSide::Right:
            for (const auto& p : endPoints) {
                marginPx = std::min(marginPx, static_cast<double>((width - 1)) - p.x);
            }
            return {marginPx, marginPx / std::max(width, 1)};

        case FrameSide::Top:
            for (const auto& p : endPoints) marginPx = std::min(marginPx, p.y);
            return {marginPx, marginPx / std::max(height, 1)};

        case FrameSide::Bottom:
            for (const auto& p : endPoints) {
                marginPx = std::min(marginPx, static_cast<double>((height - 1)) - p.y);
            }
            return {marginPx, marginPx / std::max(height, 1)};

        default:
            throw std::runtime_error("Invalid frame side.");
    }
}

FrameChoice chooseAlignedFrame(
    const std::vector<cv::Point2d>& endPoints,
    const cv::Vec2d& endDirection,
    int width,
    int height,
    const TruncationConfig& cfg) {

    const std::array<std::pair<FrameSide, cv::Vec2d>, 4> normals = {{
        {FrameSide::Left, cv::Vec2d(-1.0, 0.0)},
        {FrameSide::Right, cv::Vec2d(1.0, 0.0)},
        {FrameSide::Top, cv::Vec2d(0.0, -1.0)},
        {FrameSide::Bottom, cv::Vec2d(0.0, 1.0)},
    }};

    std::vector<FrameChoice> options;
    for (const auto& item : normals) {
        const double alignment = dot(endDirection, item.second);
        if (alignment <= 0.0) {
            continue;
        }

        const auto [marginPx, marginFraction] =
            frameMarginForSide(endPoints, item.first, width, height);

        options.push_back(FrameChoice{
            item.first,
            alignment,
            marginPx,
            marginFraction,
        });
    }

    std::vector<FrameChoice> plausible;
    for (const auto& option : options) {
        if (option.alignment >= cfg.minEndFrameAlignment) {
            plausible.push_back(option);
        }
    }

    const auto& pool = plausible.empty() ? options : plausible;
    if (pool.empty()) {
        throw std::runtime_error("No aligned frame edge found.");
    }

    return *std::min_element(
        pool.begin(),
        pool.end(),
        [](const FrameChoice& a, const FrameChoice& b) {
            if (a.marginFraction != b.marginFraction) {
                return a.marginFraction < b.marginFraction;
            }
            return a.alignment > b.alignment;
        });
}

double percentileLinear(std::vector<double> values, double percentile) {
    if (values.empty()) {
        return std::numeric_limits<double>::quiet_NaN();
    }

    std::sort(values.begin(), values.end());
    if (values.size() == 1) {
        return values.front();
    }

    const double p = std::clamp(percentile, 0.0, 100.0) / 100.0;
    const double index = p * static_cast<double>(values.size() - 1);
    const auto lo = static_cast<std::size_t>(std::floor(index));
    const auto hi = static_cast<std::size_t>(std::ceil(index));
    const double alpha = index - static_cast<double>(lo);

    return values[lo] * (1.0 - alpha) + values[hi] * alpha;
}

CapShape computeCapShape(
    const std::vector<cv::Point>& contour,
    const PcaGeometry& g,
    bool lowEnd,
    const TruncationConfig& cfg) {

    const double axialLength = std::max(g.tMax - g.tMin, 1e-6);
    const double lateralWidth = std::max(g.sMax - g.sMin, 1e-6);
    const double capDepth = std::max(2.0, cfg.capDepthFraction * axialLength);

    if (cfg.capBins <= 0) {
        throw std::runtime_error("capBins must be positive.");
    }

    std::vector<double> contourT;
    std::vector<double> contourS;
    contourT.reserve(contour.size());
    contourS.reserve(contour.size());

    for (const auto& p : contour) {
        const cv::Vec2d centered(
            static_cast<double>(p.x) - g.center.x,
            static_cast<double>(p.y) - g.center.y);
        contourT.push_back(dot(centered, g.major));
        contourS.push_back(dot(centered, g.minor));
    }

    const double binWidth = lateralWidth / static_cast<double>(cfg.capBins);
    std::vector<double> profileS;
    std::vector<double> profileT;

    for (int i = 0; i < cfg.capBins; ++i) {
        const double lo = g.sMin + static_cast<double>(i) * binWidth;
        const double hi = (i == cfg.capBins - 1)
            ? g.sMax
            : g.sMin + static_cast<double>(i + 1) * binWidth;

        bool found = false;
        double extreme = lowEnd
            ? std::numeric_limits<double>::infinity()
            : -std::numeric_limits<double>::infinity();

        for (std::size_t j = 0; j < contourS.size(); ++j) {
            const double s = contourS[j];
            const bool inBin = (s >= lo) &&
                ((i == cfg.capBins - 1) ? (s <= hi) : (s < hi));
            if (!inBin) {
                continue;
            }

            found = true;
            if (lowEnd) {
                extreme = std::min(extreme, contourT[j]);
            } else {
                extreme = std::max(extreme, contourT[j]);
            }
        }

        if (!found) {
            continue;
        }

        const double depth = lowEnd ? (extreme - g.tMin) : (g.tMax - extreme);
        if (depth <= capDepth) {
            profileS.push_back(0.5 * (lo + hi));
            profileT.push_back(extreme);
        }
    }

    CapShape shape;
    shape.profileBins = static_cast<int>(profileS.size());

    if (profileS.size() < 2) {
        shape.spanRatio = 0.0;
        shape.flatnessRatio = std::numeric_limits<double>::quiet_NaN();
        return shape;
    }

    const auto [minSIt, maxSIt] = std::minmax_element(profileS.begin(), profileS.end());
    const double span = *maxSIt - *minSIt + binWidth;
    shape.spanRatio = span / lateralWidth;

    double axialSpread = 0.0;
    if (profileT.size() >= 4) {
        const double p10 = percentileLinear(profileT, 10.0);
        const double p90 = percentileLinear(profileT, 90.0);
        axialSpread = p90 - p10;
    } else {
        const auto [minTIt, maxTIt] = std::minmax_element(profileT.begin(), profileT.end());
        axialSpread = *maxTIt - *minTIt;
    }

    shape.flatnessRatio = axialSpread / std::max(span, 1e-6);
    return shape;
}

EndMetrics analyzeEnd(
    const PcaGeometry& g,
    const cv::Mat& distanceTransform,
    double maxRadius,
    const std::vector<cv::Point>& contour,
    bool lowEnd,
    int width,
    int height,
    const TruncationConfig& cfg) {

    const double axialLength = std::max(g.tMax - g.tMin, 1e-6);
    const double radiusBand = std::max(2.0, cfg.axialEndBandFraction * axialLength);

    std::vector<cv::Point2d> endPoints;
    std::vector<std::size_t> endIndices;

    for (std::size_t i = 0; i < g.points.size(); ++i) {
        const bool selected = lowEnd
            ? (g.t[i] <= g.tMin + radiusBand)
            : (g.t[i] >= g.tMax - radiusBand);

        if (selected) {
            endPoints.emplace_back(
                static_cast<double>(g.points[i].x),
                static_cast<double>(g.points[i].y));
            endIndices.push_back(i);
        }
    }

    const cv::Vec2d direction = lowEnd ? -g.major : g.major;
    const cv::Point2d axisPoint = addScaled(
        g.center,
        g.major,
        lowEnd ? g.tMin : g.tMax);

    const FrameChoice frame = chooseAlignedFrame(
        endPoints, direction, width, height, cfg);

    double terminalRadius = 0.0;
    for (const auto index : endIndices) {
        const auto& p = g.points[index];
        terminalRadius = std::max(
            terminalRadius,
            static_cast<double>(distanceTransform.at<float>(p.y, p.x)));
    }

    const double terminalRadiusRatio = terminalRadius / std::max(maxRadius, kEps);
    const CapShape shape = computeCapShape(contour, g, lowEnd, cfg);

    EndMetrics out;
    out.axisPoint = axisPoint;
    out.frameSide = frame.side;
    out.frameAlignment = frame.alignment;
    out.frameMarginPx = frame.marginPx;
    out.frameMarginFraction = frame.marginFraction;
    out.terminalRadiusRatio = terminalRadiusRatio;
    out.capSpanRatio = shape.spanRatio;
    out.capFlatnessRatio = shape.flatnessRatio;
    out.capFlatnessValid = std::isfinite(shape.flatnessRatio);

    const bool aligned = frame.alignment >= cfg.minEndFrameAlignment;
    out.veryNear = aligned && frame.marginFraction <= cfg.veryNearFrameFraction;
    out.near = aligned && frame.marginFraction <= cfg.nearFrameFraction;
    out.broad = shape.spanRatio >= cfg.minBroadCapSpanRatio;
    out.flat = out.capFlatnessValid && shape.flatnessRatio <= cfg.maxFlatCapRatio;
    out.thick = terminalRadiusRatio >= cfg.minTerminalRadiusRatio;

    const bool suspiciousShape = out.broad && (out.flat || out.thick);
    out.candidate = out.veryNear || (out.near && suspiciousShape);
    out.strongCandidate = out.near && out.broad && out.flat && out.thick;

    return out;
}

}  // namespace

EdgeTruncationDetector::EdgeTruncationDetector(TruncationConfig config)
    : config_(std::move(config)) {}

TruncationResult EdgeTruncationDetector::analyze(const cv::Mat& mask) const {
    TruncationResult result;

    try {
        const PcaGeometry g = computePcaGeometry(mask);
        const int height = g.binaryMask.rows;
        const int width = g.binaryMask.cols;

        const double axialLength = std::max(g.tMax - g.tMin, 1e-6);

        std::vector<std::vector<cv::Point>> contours;
        // findContours mutates its input on some OpenCV versions, so clone it.
        cv::Mat contourMask = g.binaryMask.clone();
        cv::findContours(
            contourMask,
            contours,
            cv::RETR_EXTERNAL,
            cv::CHAIN_APPROX_NONE);

        if (contours.empty()) {
            throw std::runtime_error("No external contour.");
        }

        auto largestIt = std::max_element(
            contours.begin(),
            contours.end(),
            [](const std::vector<cv::Point>& a, const std::vector<cv::Point>& b) {
                return cv::contourArea(a) < cv::contourArea(b);
            });

        cv::Mat dt;
        cv::distanceTransform(g.binaryMask, dt, cv::DIST_L2, 5);
        double maxRadius = 0.0;
        cv::minMaxLoc(dt, nullptr, &maxRadius);

        result.imageHeightPx = height;
        result.imageWidthPx = width;
        result.pcaCenter = g.center;
        result.majorAxis = g.major;
        result.axialLengthPx = axialLength;
        result.maxRadiusPx = maxRadius;

        result.low = analyzeEnd(
            g, dt, maxRadius, *largestIt, true, width, height, config_);
        result.high = analyzeEnd(
            g, dt, maxRadius, *largestIt, false, width, height, config_);

        result.candidateEndMask =
            (result.low.candidate ? 1 : 0) |
            (result.high.candidate ? 2 : 0);

        const bool anyCandidate = result.candidateEndMask != 0;
        const bool anyStrong = result.low.strongCandidate || result.high.strongCandidate;

        result.truncationCandidate = anyCandidate;
        result.reject = anyCandidate;  // Current app policy requested by the user.
        result.candidateStrength = anyStrong
            ? CandidateStrength::Strong
            : (anyCandidate ? CandidateStrength::Review : CandidateStrength::Clear);
        result.valid = true;
        result.error.clear();
        return result;

    } catch (const std::exception& e) {
        // Fail closed for capture-time screening: if the mask cannot be analyzed,
        // ask for a retake instead of forwarding an invalid sample to weight estimation.
        result.valid = false;
        result.reject = true;
        result.truncationCandidate = true;
        result.candidateEndMask = 0;
        result.candidateStrength = CandidateStrength::Error;
        result.error = e.what();
        return result;
    }
}

const char* frameSideName(FrameSide side) noexcept {
    switch (side) {
        case FrameSide::Left: return "left";
        case FrameSide::Right: return "right";
        case FrameSide::Top: return "top";
        case FrameSide::Bottom: return "bottom";
        default: return "none";
    }
}

const char* candidateStrengthName(CandidateStrength strength) noexcept {
    switch (strength) {
        case CandidateStrength::Clear: return "clear";
        case CandidateStrength::Review: return "review";
        case CandidateStrength::Strong: return "strong";
        case CandidateStrength::Error: return "error";
        default: return "error";
    }
}

}  // namespace instaham
