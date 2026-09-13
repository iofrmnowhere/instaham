#pragma once
#include "instaham/Common.hpp"
namespace instaham { struct Break1Config{int minGap=4;int minEdge=2;double refineSpan=1.0;double refineStep=.02;double maxFraction=.35;}; Break1Result fitBreak1(const OrientedTrunk& trunk,const Break1Config& cfg={}); }
