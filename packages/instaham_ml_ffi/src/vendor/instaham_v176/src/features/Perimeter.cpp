#include "instaham/features/Perimeter.hpp"
#include "instaham/Common.hpp"
#include "instaham/MaskUtils.hpp"
#include <opencv2/imgproc.hpp>
namespace instaham { double featurePerimeter(const cv::Mat&m){auto c=largestExternalContour(m,cv::CHAIN_APPROX_NONE);if(c.size()<5)return nanValue();return cv::arcLength(c,true);} }
