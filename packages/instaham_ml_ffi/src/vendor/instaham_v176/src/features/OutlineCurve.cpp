#include "instaham/features/OutlineCurve.hpp"
#include "instaham/Common.hpp"
#include "instaham/MaskUtils.hpp"
#include <opencv2/imgproc.hpp>
#include <algorithm>
#include <cmath>
#include <vector>
namespace instaham {
static bool resample(const std::vector<cv::Point>& c,std::vector<cv::Point2d>&out,int n=256){if(c.size()<4)return false;std::vector<cv::Point2d>p;for(auto&q:c)p.emplace_back(q.x,q.y);p.push_back(p.front());std::vector<double>cum(p.size(),0);for(size_t i=1;i<p.size();i++)cum[i]=cum[i-1]+cv::norm(p[i]-p[i-1]);double total=cum.back();if(!(total>1e-9))return false;out.resize(n);size_t j=0;for(int i=0;i<n;i++){double target=total*i/n;while(j+1<cum.size()&&cum[j+1]<=target)j++;j=std::min(j,p.size()-2);double den=cum[j+1]-cum[j],t=den<=1e-12?0:(target-cum[j])/den;out[i]=p[j]*(1-t)+p[j+1]*t;}return true;}
double featureOutlineCurve(const cv::Mat&m){auto c=largestExternalContour(m,cv::CHAIN_APPROX_NONE);std::vector<cv::Point2d>s;if(!resample(c,s))return nanValue();std::vector<cv::Point2d>sm(256);for(int i=0;i<256;i++){cv::Point2d a(0,0);for(int o=-3;o<=3;o++)a+=s[(i+o+256)%256];sm[i]=a*(1.0/7.0);}double best=-1;for(int i=0;i<256;i++){auto prev=sm[(i+255)%256],cur=sm[i],next=sm[(i+1)%256];auto d1=(next-prev)*0.5;auto d2=next-cur*2.0+prev;double num=std::abs(d1.x*d2.y-d1.y*d2.x),den=std::pow(d1.x*d1.x+d1.y*d1.y,1.5);double k=num/std::max(den,1e-9);if(std::isfinite(k))best=std::max(best,k);}return best>=0?best:nanValue();}
}
