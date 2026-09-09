#include "instaham/features/Hu3.hpp"
#include <limits>
namespace instaham { double featureHu3(const HuWorkResult&w){return w.valid?w.hu[2]:std::numeric_limits<double>::quiet_NaN();} }
