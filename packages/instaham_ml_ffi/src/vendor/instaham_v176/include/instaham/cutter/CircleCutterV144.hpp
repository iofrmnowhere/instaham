#pragma once
#include "instaham/cutter/CutterTypes.hpp"
namespace instaham { struct CircleCutterConfig{double rayStepPx=.25;double rayMaxMultiplier=4.0;int localTangentSpan=3;}; CircleCutResult cutWithV144Circle(const cv::Mat& jiMask,const OrientedTrunk& trunk,const ShoulderDecision& shoulder,const CircleCutterConfig& cfg={}); }
