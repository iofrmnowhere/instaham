#include "instaham/MaskUtils.hpp"
#include <opencv2/imgproc.hpp>
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace instaham {
cv::Mat strictBinary(const cv::Mat& mask){
    if(mask.empty()||mask.channels()!=1) throw std::runtime_error("Mask must be non-empty single-channel.");
    cv::Mat out; cv::compare(mask,0,out,cv::CMP_GT); out/=255; return out;
}
cv::Mat binary255(const cv::Mat& mask){ cv::Mat b=strictBinary(mask); b*=255; return b; }
std::vector<cv::Point> largestExternalContour(const cv::Mat& mask,int chainMode){
    cv::Mat b=binary255(mask); std::vector<std::vector<cv::Point>> cs;
    cv::findContours(b,cs,cv::RETR_EXTERNAL,chainMode);
    if(cs.empty()) return {};
    return *std::max_element(cs.begin(),cs.end(),[](auto&a,auto&b){return cv::contourArea(a)<cv::contourArea(b);});
}
cv::Mat largestComponentFill(const cv::Mat& mask){
    cv::Mat b=binary255(mask); std::vector<std::vector<cv::Point>> cs;
    cv::findContours(b,cs,cv::RETR_EXTERNAL,cv::CHAIN_APPROX_SIMPLE);
    if(cs.empty()) return b;
    auto it=std::max_element(cs.begin(),cs.end(),[](auto&a,auto&b){return cv::contourArea(a)<cv::contourArea(b);});
    cv::Mat out=cv::Mat::zeros(b.size(),CV_8U); cv::drawContours(out,std::vector<std::vector<cv::Point>>{*it},-1,cv::Scalar(255),cv::FILLED); return out;
}
cv::Mat cleanBinaryMask(const cv::Mat& mask){
    cv::Mat clean=largestComponentFill(mask); if(cv::countNonZero(clean)==0) return clean;
    int k=std::max(3,roundEvenInt(std::min(clean.rows,clean.cols)*0.006)); if(k%2==0) ++k;
    cv::Mat kernel=cv::getStructuringElement(cv::MORPH_ELLIPSE,{k,k});
    cv::morphologyEx(clean,clean,cv::MORPH_CLOSE,kernel); return largestComponentFill(clean);
}
int roundEvenInt(double x){ double f=std::floor(x), frac=x-f; if(frac<0.5)return (int)f; if(frac>0.5)return (int)(f+1.0); long long fi=(long long)f; return (fi%2==0)?(int)fi:(int)(fi+1); }
bool maskContainsNearest(const cv::Mat& mask,const cv::Point2d&p){
    int x=roundEvenInt(p.x),y=roundEvenInt(p.y); if(x<0||x>=mask.cols||y<0||y>=mask.rows) return false;
    return mask.at<uint8_t>(y,x)>0;
}
cv::Vec2d unitVec(const cv::Vec2d&v){double n=std::hypot(v[0],v[1]); if(!std::isfinite(n)||n<=1e-12) throw std::runtime_error("Cannot normalize vector");return {v[0]/n,v[1]/n};}
double dot2(const cv::Vec2d&a,const cv::Vec2d&b){return a[0]*b[0]+a[1]*b[1];}
}
