#include "instaham/cutter/CircleCutterV144.hpp"
#include "instaham/MaskUtils.hpp"
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace instaham {
static cv::Vec2d tangentAt(const OrientedTrunk&t,int pos,int span){int n=t.centers.size();if(n<2)throw std::runtime_error("Need 2 trunk centers");pos=std::clamp(pos,0,n-1);int lo=std::max(0,pos-span),hi=std::min(n-1,pos+span);if(lo==hi){lo=std::max(0,pos-1);hi=std::min(n-1,pos+1);}cv::Vec2d v(t.centers[hi].x-t.centers[lo].x,t.centers[hi].y-t.centers[lo].y);if(hypot(v[0],v[1])<=1e-12){if(pos<n-1)v={t.centers[pos+1].x-t.centers[pos].x,t.centers[pos+1].y-t.centers[pos].y};else v={t.centers[pos].x-t.centers[pos-1].x,t.centers[pos].y-t.centers[pos-1].y};}v=unitVec(v);cv::Vec2d g(t.centers.back().x-t.centers.front().x,t.centers.back().y-t.centers.front().y);if(dot2(v,g)<0)v=-v;return v;}
static double exitD(const cv::Mat&m,const cv::Point2d&c,const cv::Vec2d&dir,double r,const CircleCutterConfig&cfg){if(!maskContainsNearest(m,c))throw std::runtime_error("Shoulder center outside Ji/Duan");auto d=unitVec(dir);double maxD=std::min(hypot(m.cols,m.rows),std::max(r*cfg.rayMaxMultiplier,r+20.0));for(double x=0;x<=maxD;x+=cfg.rayStepPx){cv::Point2d p(c.x+x*d[0],c.y+x*d[1]);if(!maskContainsNearest(m,p))return x;}throw std::runtime_error("No transverse exit");}
CircleCutResult cutWithV144Circle(
    const cv::Mat& mask,
    const OrientedTrunk& trunk,
    const ShoulderDecision& shoulder,
    const CircleCutterConfig& cfg) {

    if (!shoulder.valid || !shoulder.cutRequired) {
        throw std::runtime_error("Invalid V176 shoulder");
    }

    const cv::Mat ji = strictBinary(mask);
    const int pos = std::clamp(shoulder.selectedPos, 0, static_cast<int>(trunk.centers.size()) - 1);
    const cv::Point2d center = trunk.centers[pos];
    const double medialRadius = trunk.radii[pos];
    const cv::Vec2d tangent = tangentAt(trunk, pos, cfg.localTangentSpan);
    const cv::Vec2d normal(-tangent[1], tangent[0]);

    const double plus = exitD(ji, center, normal, medialRadius, cfg);
    const double minus = exitD(ji, center, -normal, medialRadius, cfg);
    const double radius = std::max(medialRadius, std::max(plus, minus));

    cv::Mat finalMask = cv::Mat::zeros(ji.size(), CV_8U);
    for (int y = 0; y < ji.rows; ++y) {
        for (int x = 0; x < ji.cols; ++x) {
            if (!ji.at<uchar>(y, x)) continue;
            const double dx = x - center.x;
            const double dy = y - center.y;
            const bool insideCircle = dx * dx + dy * dy <= radius * radius;
            const bool rumpward = dx * tangent[0] + dy * tangent[1] >= 0.0;
            if (insideCircle || rumpward) {
                finalMask.at<uchar>(y, x) = 1;
            }
        }
    }

    if (cv::countNonZero(finalMask) <= 0) {
        throw std::runtime_error("V144 circle cut produced an empty mask");
    }

    // Production output intentionally contains no kept-area / <80% flag.
    // That reviewer statistic was research-only and is not part of runtime behavior.
    CircleCutResult out;
    out.finalMask = finalMask;
    return out;
}
}
