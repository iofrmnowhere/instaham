#pragma once
#include <opencv2/core.hpp>
#include <vector>
namespace instaham {
cv::Mat strictBinary(const cv::Mat& mask);            // CV_8U, values 0/1
cv::Mat binary255(const cv::Mat& mask);               // CV_8U, values 0/255
cv::Mat largestComponentFill(const cv::Mat& mask);    // 0/255
cv::Mat cleanBinaryMask(const cv::Mat& mask);         // 0/255
std::vector<cv::Point> largestExternalContour(const cv::Mat& mask, int chainMode);
bool maskContainsNearest(const cv::Mat& mask, const cv::Point2d& p);
cv::Vec2d unitVec(const cv::Vec2d& v);
double dot2(const cv::Vec2d& a,const cv::Vec2d& b);
int roundEvenInt(double x);
}
