#pragma once
#include <opencv2/core.hpp>
#include <array>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

namespace instaham {
constexpr double kEps = 1e-12;
inline double nanValue() { return std::numeric_limits<double>::quiet_NaN(); }

struct PointRadius {
    cv::Point2d center{};
    double radius = 0.0;
    int pIndex = -1;
    int qIndex = -1;
    cv::Point2d p{};
    cv::Point2d q{};
    cv::Vec2d normal{0.0,0.0};
    bool converged = false;
    double contactAngleDeg = 0.0;
    double edtRadius = 0.0;
    double radiusMinusEdt = 0.0;
    double longitudinal = 0.0;
    double lateral = 0.0;
};

struct OrientedTrunk {
    std::vector<cv::Point2d> centers;
    std::vector<double> radii;
    std::vector<int> nodes;
    std::string headEnd;
    std::string rumpEnd;
    double headRadius = 0.0;
    double rumpRadius = 0.0;
};

struct Break1Result {
    bool valid = false;
    double break1Augmented = 0.0;
    double break2Augmented = 0.0;
    double break1Real = 0.0;
    std::vector<double> predictionReal;
    double rss = 0.0;
};

struct ShoulderDecision {
    bool valid = false;
    bool cutRequired = false;
    int selectedPos = -1;
    double selectedX = 0.0;
    double break1X = 0.0;
    std::string caseName;
    std::string reason;
};

struct Chen16Features {
    std::array<double,16> values{};
    bool valid = false;
    std::string error;
};
}
