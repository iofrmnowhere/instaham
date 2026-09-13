#pragma once
#include "instaham/cutter/CutterTypes.hpp"
namespace instaham { struct OutlineConfig{int resamplePoints=420;int savgolWindow=31;int savgolPolyorder=3;int normalHalfWindow=7;}; OutlineResult buildOutline(const cv::Mat& jiMask,const OutlineConfig& cfg={}); }
