#include "instaham/features/ConvexHullArea.hpp"
#include "instaham/Common.hpp"
#include "instaham/MaskUtils.hpp"
#include <opencv2/imgproc.hpp>
namespace instaham { double featureConvexHullArea(const cv::Mat&m){auto c=largestExternalContour(m,cv::CHAIN_APPROX_NONE);if(c.size()<5||cv::contourArea(c)<=0)return nanValue();std::vector<cv::Point>h;cv::convexHull(c,h);cv::Mat hm=cv::Mat::zeros(m.size(),CV_8U);cv::fillConvexPoly(hm,h,cv::Scalar(255));return (double)cv::countNonZero(hm);} }
