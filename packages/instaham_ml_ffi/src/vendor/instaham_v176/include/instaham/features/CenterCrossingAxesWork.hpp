#pragma once
#include <opencv2/core.hpp>
namespace instaham { struct AxisWorkResult{double longest=0,shortest=0;bool valid=false;}; AxisWorkResult computeCenterCrossingAxes(const cv::Mat& mask); }
