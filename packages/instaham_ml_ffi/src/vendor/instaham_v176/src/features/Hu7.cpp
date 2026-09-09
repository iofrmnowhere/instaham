#include "instaham/features/Hu7.hpp"
#include <limits>
namespace instaham { double featureHu7(const HuWorkResult&w){return w.valid?w.hu[6]:std::numeric_limits<double>::quiet_NaN();} }
