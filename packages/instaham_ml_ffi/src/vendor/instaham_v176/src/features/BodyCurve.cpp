#include "instaham/features/BodyCurve.hpp"
#include "instaham/Common.hpp"
#include "instaham/MaskUtils.hpp"

#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

namespace instaham {
namespace {

// Exact Zhang-Suen neighborhood classification table used by
// scikit-image 0.26.0's 2-D skeletonize(..., method="zhang") implementation.
// Neighborhood bit order is:
//   NW=1, N=2, NE=4, E=8, SE=16, S=32, SW=64, W=128.
// Class 1/3 is deleted on pass 1; class 2/3 on pass 2.
constexpr std::array<std::uint8_t, 256> kSkimage026ZhangLut = {
    0,0,0,1,0,0,1,3,0,0,3,1,1,0,1,3,0,0,0,0,0,0,0,0,2,0,2,0,3,0,3,3,
    0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,3,0,2,2,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    2,0,0,0,0,0,0,0,2,0,0,0,2,0,0,0,3,0,0,0,0,0,0,0,3,0,0,0,3,0,2,0,
    0,0,3,1,0,0,1,3,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    3,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    2,3,1,3,0,0,1,3,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    2,3,0,1,0,0,0,1,0,0,0,0,0,0,0,0,3,3,0,1,0,0,0,0,2,2,0,0,2,0,0,0
};

cv::Mat skeletonizeLikeSkimage026(const cv::Mat& input) {
    cv::Mat core = strictBinary(input);
    if (core.empty()) {
        return core;
    }

    // scikit-image pads a one-pixel zero border around the image before the
    // Zhang-Suen loop so edge-touching foreground is handled as background-
    // bounded rather than being artificially frozen.
    cv::Mat skeleton;
    cv::copyMakeBorder(
        core,
        skeleton,
        1,
        1,
        1,
        1,
        cv::BORDER_CONSTANT,
        cv::Scalar(0)
    );

    // scikit-image initializes one cleaned copy and then carries deletions
    // forward. Every subpass reads only from `skeleton`, marks removals in
    // `cleanedSkeleton`, and copies the completed subpass back at once.
    cv::Mat cleanedSkeleton = skeleton.clone();
    bool pixelRemoved = true;

    while (pixelRemoved) {
        pixelRemoved = false;

        for (int passNum = 0; passNum < 2; ++passNum) {
            const bool firstPass = (passNum == 0);

            for (int row = 1; row < skeleton.rows - 1; ++row) {
                for (int col = 1; col < skeleton.cols - 1; ++col) {
                    if (skeleton.at<std::uint8_t>(row, col) == 0) {
                        continue;
                    }

                    const unsigned neighborhood =
                        static_cast<unsigned>(skeleton.at<std::uint8_t>(row - 1, col - 1)) +
                        2u   * static_cast<unsigned>(skeleton.at<std::uint8_t>(row - 1, col)) +
                        4u   * static_cast<unsigned>(skeleton.at<std::uint8_t>(row - 1, col + 1)) +
                        8u   * static_cast<unsigned>(skeleton.at<std::uint8_t>(row,     col + 1)) +
                        16u  * static_cast<unsigned>(skeleton.at<std::uint8_t>(row + 1, col + 1)) +
                        32u  * static_cast<unsigned>(skeleton.at<std::uint8_t>(row + 1, col)) +
                        64u  * static_cast<unsigned>(skeleton.at<std::uint8_t>(row + 1, col - 1)) +
                        128u * static_cast<unsigned>(skeleton.at<std::uint8_t>(row,     col - 1));

                    const std::uint8_t classification = kSkimage026ZhangLut[neighborhood];
                    const bool deletePixel =
                        classification == 3 ||
                        (classification == 1 && firstPass) ||
                        (classification == 2 && !firstPass);

                    if (deletePixel) {
                        cleanedSkeleton.at<std::uint8_t>(row, col) = 0;
                        pixelRemoved = true;
                    }
                }
            }

            cleanedSkeleton.copyTo(skeleton);
        }
    }

    return skeleton(cv::Rect(1, 1, core.cols, core.rows)).clone();
}

}  // namespace

double computeBodyCurve(const cv::Mat& mask) {
    cv::Mat b = binary255(mask);
    std::vector<cv::Point> fg;
    cv::findNonZero(b, fg);
    if (fg.size() < 5) {
        return nanValue();
    }

    cv::Rect box = cv::boundingRect(fg);
    cv::Mat crop = strictBinary(b(box));
    cv::Mat sk = skeletonizeLikeSkimage026(crop);

    std::vector<cv::Point> pts;
    cv::findNonZero(sk, pts);
    if (pts.size() < 3) {
        return nanValue();
    }

    std::vector<cv::Point2d> endpoints;
    cv::Point2d centroid(0, 0);

    for (const auto& p : pts) {
        centroid.x += p.x;
        centroid.y += p.y;

        int nb = 0;
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                if (dx == 0 && dy == 0) {
                    continue;
                }
                const int x = p.x + dx;
                const int y = p.y + dy;
                if (
                    x >= 0 && x < sk.cols &&
                    y >= 0 && y < sk.rows &&
                    sk.at<std::uint8_t>(y, x) > 0
                ) {
                    ++nb;
                }
            }
        }

        if (nb == 1) {
            endpoints.emplace_back(p.x, p.y);
        }
    }

    centroid.x /= static_cast<double>(pts.size());
    centroid.y /= static_cast<double>(pts.size());

    cv::Point2d p1;
    cv::Point2d p2;

    if (endpoints.size() >= 2) {
        auto farFrom = [&](const cv::Point2d& q) {
            std::size_t bestIndex = 0;
            double bestDistance = -1.0;
            for (std::size_t i = 0; i < endpoints.size(); ++i) {
                const double d = cv::norm(endpoints[i] - q);
                if (d > bestDistance) {
                    bestDistance = d;
                    bestIndex = i;
                }
            }
            return endpoints[bestIndex];
        };

        p1 = farFrom(endpoints[0]);
        p2 = farFrom(p1);
    } else {
        cv::Mat data(static_cast<int>(pts.size()), 2, CV_64F);
        for (int i = 0; i < static_cast<int>(pts.size()); ++i) {
            data.at<double>(i, 0) = pts[i].x - centroid.x;
            data.at<double>(i, 1) = pts[i].y - centroid.y;
        }

        cv::PCA pca(data, cv::Mat(), cv::PCA::DATA_AS_ROW);
        cv::Vec2d axis(
            pca.eigenvectors.at<double>(0, 0),
            pca.eigenvectors.at<double>(0, 1)
        );

        double lo = std::numeric_limits<double>::max();
        double hi = -std::numeric_limits<double>::max();
        for (const auto& p : pts) {
            const double t =
                (p.x - centroid.x) * axis[0] +
                (p.y - centroid.y) * axis[1];
            if (t < lo) {
                lo = t;
                p1 = {static_cast<double>(p.x), static_cast<double>(p.y)};
            }
            if (t > hi) {
                hi = t;
                p2 = {static_cast<double>(p.x), static_cast<double>(p.y)};
            }
        }
    }

    const cv::Point2d v1 = p1 - centroid;
    const cv::Point2d v2 = p2 - centroid;
    const double n1 = cv::norm(v1);
    const double n2 = cv::norm(v2);
    if (n1 <= 1e-9 || n2 <= 1e-9) {
        return nanValue();
    }

    double c = (v1.x * v2.x + v1.y * v2.y) / (n1 * n2);
    c = std::clamp(c, -1.0, 1.0);
    return std::acos(c) * 180.0 / CV_PI;
}

}  // namespace instaham
