#include "instaham/features/Hu1.hpp"
#include <limits>
namespace instaham { double featureHu1(const HuWorkResult&w){return w.valid?w.hu[0]:std::numeric_limits<double>::quiet_NaN();} }
