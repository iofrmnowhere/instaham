#include "instaham/features/Longest.hpp"
#include <limits>
namespace instaham { double featureLongest(const AxisWorkResult&w){return w.valid?w.longest:std::numeric_limits<double>::quiet_NaN();} }
