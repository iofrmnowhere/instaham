#include "instaham/features/Hu6.hpp"
#include <limits>
namespace instaham { double featureHu6(const HuWorkResult&w){return w.valid?w.hu[5]:std::numeric_limits<double>::quiet_NaN();} }
