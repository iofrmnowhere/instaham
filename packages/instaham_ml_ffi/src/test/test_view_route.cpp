// docs/fix-phase-6/1-native-route-override.md: stages/view_route.h's resolve_view_route(),
// covering every row of the route table plus the request-parsing rules that feed it (the
// bool alias, view_route_override winning, invalid values meaning none) -- those parsing
// rules are exercised here by calling resolve_view_route() with the already-normalized
// strings instaham_ml.cpp would produce for each case, since the parsing itself lives in
// instaham_ml.cpp, not in this pure function. Header-only, no OpenCV/ORT, so this builds
// and runs unconditionally like test_stage_invariants.cpp.

#include "stages/view_route.h"

#include <cassert>
#include <cstdio>
#include <string>

using instaham_ml::stages::resolve_view_route;
using instaham_ml::stages::ViewRoute;

int main() {
  // ==== the route table (fix-phase-6/1-native-route-override.md) =========================
  // dorsal_valid + any -> dorsal (an override never downgrades a clean verdict).
  assert(resolve_view_route("dorsal_valid", "") == ViewRoute::kDorsal);
  assert(resolve_view_route("dorsal_valid", "dorsal_valid") == ViewRoute::kDorsal);
  assert(resolve_view_route("dorsal_valid", "health_only") == ViewRoute::kDorsal);

  // health_only + none or health_only -> health_only.
  assert(resolve_view_route("health_only", "") == ViewRoute::kHealthOnly);
  assert(resolve_view_route("health_only", "health_only") == ViewRoute::kHealthOnly);

  // health_only + dorsal_valid -> dorsal.
  assert(resolve_view_route("health_only", "dorsal_valid") == ViewRoute::kDorsal);

  // reject + none -> stopped (view_rejected, unchanged).
  assert(resolve_view_route("reject", "") == ViewRoute::kStopped);

  // reject + dorsal_valid -> dorsal.
  assert(resolve_view_route("reject", "dorsal_valid") == ViewRoute::kDorsal);

  // reject + health_only -> health_only.
  assert(resolve_view_route("reject", "health_only") == ViewRoute::kHealthOnly);

  // anything else / view unavailable -> unresolved (fail closed, unchanged), any override.
  assert(resolve_view_route("", "") == ViewRoute::kUnresolved);
  assert(resolve_view_route("", "dorsal_valid") == ViewRoute::kUnresolved);
  assert(resolve_view_route("unrecognised_label", "") == ViewRoute::kUnresolved);
  assert(resolve_view_route("unrecognised_label", "health_only") == ViewRoute::kUnresolved);

  // ==== request-parsing rules, applied before resolve_view_route() ever sees the value ====
  // (instaham_ml.cpp normalizes: bool alias -> "dorsal_valid"; view_route_override wins over
  // the bool alias when both are present; an invalid string means "" (none)). Simulated here
  // by feeding resolve_view_route() the string the parser would have produced.
  {
    // bool alias: "view_gate_override": true means override_route == "dorsal_valid".
    const std::string bool_alias_override = "dorsal_valid";
    assert(resolve_view_route("reject", bool_alias_override) == ViewRoute::kDorsal);
  }
  {
    // view_route_override wins when both are present: "view_gate_override": true (would
    // alias to "dorsal_valid") plus "view_route_override": "health_only" -- the string wins.
    const std::string both_present_override = "health_only";
    assert(resolve_view_route("reject", both_present_override) == ViewRoute::kHealthOnly);
  }
  {
    // an invalid view_route_override value (not "dorsal_valid"/"health_only") normalizes to
    // "" (none) before reaching resolve_view_route(), so a reject with an invalid override
    // stops exactly as with no override at all.
    const std::string invalid_override = "";
    assert(resolve_view_route("reject", invalid_override) == ViewRoute::kStopped);
  }

  std::puts("test_view_route: all assertions passed");
  return 0;
}
