#include "instaham/features/MaskArea.hpp"
#include "instaham/MaskUtils.hpp"
#include <opencv2/core.hpp>
namespace instaham { double featureMaskArea(const cv::Mat&m){return (double)cv::countNonZero(binary255(m));} }
