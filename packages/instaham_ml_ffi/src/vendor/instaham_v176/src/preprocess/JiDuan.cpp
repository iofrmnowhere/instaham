#include "instaham/preprocess/JiDuan.hpp"
#include "instaham/MaskUtils.hpp"
#include <opencv2/imgproc.hpp>
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace instaham {
static int oddWindow(int v,int minimum){v=std::max(minimum,v);return v%2?v:v+1;}
JiDuanResult applyJiDuan(const cv::Mat& wholeMask,const JiDuanConfig& c){
    if(c.areaDivisor<=0||c.secondKernelFactor<=0||c.secondKernelFactor>1) throw std::invalid_argument("Invalid Ji/Duan config");
    cv::Mat clean=cleanBinaryMask(wholeMask); double original=cv::countNonZero(clean); JiDuanResult r; r.mask=clean.clone();
    if(original<=0){r.fallback=true;return r;}
    cv::Mat lc=largestComponentFill(clean); double area=cv::countNonZero(lc);
    r.firstKernel=oddWindow(roundEvenInt(area/c.areaDivisor),c.minimumKernel);
    r.secondKernel=oddWindow(roundEvenInt(r.firstKernel*c.secondKernelFactor),c.minimumKernel);
    cv::Mat opened=clean.clone();
    for(int k0: {r.firstKernel,r.secondKernel}){
        int maxs=std::max(1,std::min(opened.rows,opened.cols)); int cap=(maxs%2)?maxs:std::max(1,maxs-1); int k=std::max(1,std::min(k0,cap));
        cv::Mat kernel=cv::getStructuringElement(cv::MORPH_ELLIPSE,{k,k}); cv::morphologyEx(opened,opened,cv::MORPH_OPEN,kernel); opened=largestComponentFill(opened);
        if(cv::countNonZero(opened)==0){r.mask=clean;r.fallback=true;r.retainedFraction=1.0;return r;}
    }
    r.retainedFraction=cv::countNonZero(opened)/original;
    if(r.retainedFraction<c.minimumRetainedFraction){r.mask=clean;r.fallback=true;r.retainedFraction=1.0;return r;}
    r.mask=opened;return r;
}
}
