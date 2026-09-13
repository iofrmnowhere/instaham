#pragma once
#include <opencv2/core.hpp>
namespace instaham {
struct JiDuanConfig { double areaDivisor=800.0; double secondKernelFactor=0.5; int minimumKernel=3; double minimumRetainedFraction=0.20; };
struct JiDuanResult { cv::Mat mask; int firstKernel=0; int secondKernel=0; double retainedFraction=0.0; bool fallback=false; };
JiDuanResult applyJiDuan(const cv::Mat& wholeMask,const JiDuanConfig& cfg={});
}
