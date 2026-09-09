#include "instaham/features/Shortest.hpp"
#include <limits>
namespace instaham { double featureShortest(const AxisWorkResult&w){return w.valid?w.shortest:std::numeric_limits<double>::quiet_NaN();} }
