#include "instaham/features/Hu5.hpp"
#include <limits>
namespace instaham { double featureHu5(const HuWorkResult&w){return w.valid?w.hu[4]:std::numeric_limits<double>::quiet_NaN();} }
