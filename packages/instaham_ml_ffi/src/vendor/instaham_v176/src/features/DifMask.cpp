#include "instaham/features/DifMask.hpp"
#include <limits>
namespace instaham { double featureDifMask(double d,double a){return a>0?d/a:std::numeric_limits<double>::quiet_NaN();} }
