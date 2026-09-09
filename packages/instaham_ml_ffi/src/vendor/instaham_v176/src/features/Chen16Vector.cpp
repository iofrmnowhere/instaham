#include "instaham/features/Chen16Vector.hpp"
#include <cmath>
namespace instaham {
const std::array<const char*,16> kChen16FeatureNames={"mask_area","convex_hull_area","difference","dif_mask","body_curve","perimeter","outline_curve","longest","shortest","Hu_1","Hu_2","Hu_3","Hu_4","Hu_5","Hu_6","Hu_7"};
Chen16Features assembleChen16(double a,double h,double d,double dm,double bc,double p,double oc,double lo,double sh,const std::array<double,7>& hu){Chen16Features r;r.values={a,h,d,dm,bc,p,oc,lo,sh,hu[0],hu[1],hu[2],hu[3],hu[4],hu[5],hu[6]};r.valid=true;for(double v:r.values)if(!std::isfinite(v)){r.valid=false;r.error="Non-finite Chen16 feature";break;}if(!(lo>0&&sh>0)){r.valid=false;r.error="Invalid longest/shortest";}return r;}
}
