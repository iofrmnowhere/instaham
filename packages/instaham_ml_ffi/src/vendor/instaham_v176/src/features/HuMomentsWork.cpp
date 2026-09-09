#include "instaham/features/HuMomentsWork.hpp"
#include "instaham/MaskUtils.hpp"
#include <opencv2/imgproc.hpp>
#include <cmath>
namespace instaham { HuWorkResult computeHuMoments(const cv::Mat&m){HuWorkResult r;cv::Mat b=strictBinary(m);cv::Moments mo=cv::moments(b,true);if(mo.m00<=0)return r;double hu[7];cv::HuMoments(mo,hu);for(int i=0;i<7;i++){r.hu[i]=hu[i];if(!std::isfinite(hu[i]))return r;}r.valid=true;return r;} }
