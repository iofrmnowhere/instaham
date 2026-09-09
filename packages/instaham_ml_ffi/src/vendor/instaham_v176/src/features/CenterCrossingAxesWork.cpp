#include "instaham/features/CenterCrossingAxesWork.hpp"
#include "instaham/MaskUtils.hpp"
#include <opencv2/imgproc.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
namespace instaham {
AxisWorkResult computeCenterCrossingAxes(const cv::Mat&m){AxisWorkResult r;cv::Mat b=strictBinary(m);cv::Moments mo=cv::moments(b,true);if(mo.m00<=0)return r;cv::Point2d center(mo.m10/mo.m00,mo.m01/mo.m00);auto c=largestExternalContour(b,cv::CHAIN_APPROX_NONE);if(c.size()<3)return r;if(cv::pointPolygonTest(c,center,false)<0){std::vector<cv::Point>fg;cv::findNonZero(b,fg);if(fg.empty())return r;auto it=std::min_element(fg.begin(),fg.end(),[&](auto&a,auto&z){return cv::norm(cv::Point2d(a)-center)<cv::norm(cv::Point2d(z)-center);});center=*it;}
 double longest=-1,shortest=1e300;for(int deg=0;deg<180;deg++){double th=deg*CV_PI/180.0,dx=cos(th),dy=sin(th);double neg=-1e300,pos=1e300;bool hn=false,hp=false;for(size_t i=0;i<c.size();i++){cv::Point2d p0=c[i],p1=c[(i+1)%c.size()],e=p1-p0,q=p0-center;double den=dx*e.y-dy*e.x;if(std::abs(den)<=1e-12)continue;double t=(q.x*e.y-q.y*e.x)/den;double s=(q.x*dy-q.y*dx)/den;if(!std::isfinite(t)||!std::isfinite(s)||s<-1e-9||s>1+1e-9)continue;if(t<=1e-9){if(!hn||t>neg){neg=t;hn=true;}}if(t>=-1e-9){if(!hp||t<pos){pos=t;hp=true;}}}if(hn&&hp&&pos-neg>0){double ch=pos-neg;longest=std::max(longest,ch);shortest=std::min(shortest,ch);}}
 if(longest>0&&shortest<1e299){r.longest=longest;r.shortest=shortest;r.valid=true;}return r;}
}
