#pragma once
#include "instaham/cutter/CutterTypes.hpp"
namespace instaham { struct TerminalConfig{double clusterEpsPx=1.25;double leafFraction=.65;int lookbackNodes=8;int tangentBackNodes=4;double capMismatchMax=.55;double nearTieScore=.10;double rayStepPx=.50;int rayBisectionSteps=10;}; TerminalResult buildTerminalTrunk(const SelleResult& selle,const cv::Mat& jiMask,const TerminalConfig& cfg={}); }
