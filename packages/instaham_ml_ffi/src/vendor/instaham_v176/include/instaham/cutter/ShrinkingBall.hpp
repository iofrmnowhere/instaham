#pragma once
#include "instaham/cutter/CutterTypes.hpp"
namespace instaham { struct ShrinkingBallConfig{double initialRadiusFactor=4.0;int maxIterations=100;double radiusTolPx=1e-3;double maximalityTolPx=.15;double minRadiusPx=2.0;double denomEps=1e-9;double minSeparationDeg=35.0;}; ShrinkingBallResult runShrinkingBall(const OutlineResult& outline,const ShrinkingBallConfig& cfg={}); }
