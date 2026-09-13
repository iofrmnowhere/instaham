#pragma once
#include <opencv2/core.hpp>
#include <array>
namespace instaham { struct HuWorkResult{std::array<double,7> hu{};bool valid=false;}; HuWorkResult computeHuMoments(const cv::Mat& mask); }
