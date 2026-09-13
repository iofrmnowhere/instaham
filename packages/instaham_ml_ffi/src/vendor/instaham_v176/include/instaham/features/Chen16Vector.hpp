#pragma once
#include "instaham/Common.hpp"
#include <array>
namespace instaham {
Chen16Features assembleChen16(double maskArea,double convexHullArea,double difference,double difMask,double bodyCurve,double perimeter,double outlineCurve,double longest,double shortest,const std::array<double,7>& hu);
extern const std::array<const char*,16> kChen16FeatureNames;
}
