#include "instaham/features/Difference.hpp"
#include <algorithm>
namespace instaham { double featureDifference(double h,double a){return std::max(h-a,0.0);} }
