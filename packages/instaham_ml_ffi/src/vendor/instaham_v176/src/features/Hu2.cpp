#include "instaham/features/Hu2.hpp"
#include <limits>
namespace instaham { double featureHu2(const HuWorkResult&w){return w.valid?w.hu[1]:std::numeric_limits<double>::quiet_NaN();} }
