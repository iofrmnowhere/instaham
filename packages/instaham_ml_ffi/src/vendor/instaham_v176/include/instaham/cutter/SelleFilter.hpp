#pragma once
#include "instaham/cutter/CutterTypes.hpp"
namespace instaham { struct SelleConfig{double sameSideEpsPx=.75;double edtTolerancePx=1.5;double minRadiusPx=2.0;int minRetainedPoints=8;}; SelleResult applySelleFilter(const ShrinkingBallResult& sb,const OutlineResult& outline,const SelleConfig& cfg={}); }
