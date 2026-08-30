// Gate D (ML_implementation_plan.md revision 7, section 10): the cutter is a permanent
// identity dummy (section 3.4) and must never silently become anything else. This test is
// the mechanical form of AGENTS.md rule 8 for this one stage.

#include "../stages/cutter.h"

#include <cassert>
#include <cstdint>
#include <vector>

using instaham_ml::stages::CutterResult;
using instaham_ml::stages::cut_body_mask;
using instaham_ml::stages::MaskView;

namespace {

void assert_identity(const std::vector<uint8_t>& mask, int w, int h) {
  MaskView view{mask.data(), w, h};
  CutterResult result = cut_body_mask(view);
  assert(result.ok());
  assert(result.status == "identity_stub");
  assert(result.head_removal_applied == false);
  assert(result.width == w);
  assert(result.height == h);
  assert(result.mask.size() == mask.size());
  for (size_t i = 0; i < mask.size(); ++i) {
    assert(result.mask[i] == mask[i]);  // byte for byte -- section 10 gate D, item 1
  }
}

}  // namespace

int main() {
  // Edge cases named in the plan's gate D (section 10): 1x1, all-zero, all-one, non-square.
  assert_identity({1}, 1, 1);
  assert_identity(std::vector<uint8_t>(9, 0), 3, 3);
  assert_identity(std::vector<uint8_t>(9, 255), 3, 3);
  {
    std::vector<uint8_t> mixed(7 * 5);
    for (size_t i = 0; i < mixed.size(); ++i) mixed[i] = (i % 3 == 0) ? 255 : 0;
    assert_identity(mixed, 7, 5);
  }

  // Invalid input must never crash or fabricate a mask.
  {
    MaskView invalid{nullptr, 0, 0};
    CutterResult result = cut_body_mask(invalid);
    assert(!result.ok());
    assert(result.status == "invalid_input");
    assert(result.mask.empty());
  }

  return 0;
}
