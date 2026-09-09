#include "instaham/features/Hu4.hpp"
#include <limits>
namespace instaham { double featureHu4(const HuWorkResult&w){return w.valid?w.hu[3]:std::numeric_limits<double>::quiet_NaN();} }
