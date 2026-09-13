#pragma once
#include "instaham/Common.hpp"
#include <opencv2/core.hpp>
#include <string>
#include <vector>
namespace instaham {
struct OutlineResult { cv::Mat mask; std::vector<cv::Point2d> smooth; std::vector<cv::Vec2d> normals; };
struct ShrinkingBallResult { std::vector<PointRadius> candidates; };
struct SelleResult { std::vector<PointRadius> retained; cv::Point2d frameOrigin{}; cv::Vec2d major{1,0}; cv::Vec2d lateral{0,1}; };
struct TerminalResult { OrientedTrunk trunk; bool valid=false; std::string error; };
struct CircleCutResult { cv::Mat finalMask; };
}
