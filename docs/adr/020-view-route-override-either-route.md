# ADR-020: The view-gate override lets the user choose either route, from `reject` or `health_only`

Status: Accepted (partly supersedes [ADR-017](017-user-consent-view-gate-override.md))

## Context

[ADR-017](017-user-consent-view-gate-override.md) (round 9) made the view gate overridable by
explicit per-photograph consent, but in exactly one shape: from a `reject` verdict, toward the
`dorsal_valid` route, disclosed by a banner on the results screen.

Round 10 (`docs/fix-6.md`) found that shape too narrow for how the view classifier actually
fails (F68). The classifier can be wrong in both directions in which it stops a photo:

- On `reject`, the only override was "Analyze anyway", which always meant the full
  weight-and-health route. A user whose photo was usable for a health check but not for
  weight had no way to ask for health alone.
- On `health_only`, there was no dialog at all. A dorsal photo the classifier misread as
  health-only could never get a weight estimate.

The user also decided (F69) that the photo check's own output — the results screen's
"Photo framing" card and the "Photo check overridden" banner — is internal routing detail and
does not belong on the user side.

## Decision

A `reject` or `health_only` verdict shows one three-option dialog: **Retake photo**, **Check
health only**, **Check weight and health**. The route that runs is:

| Photo check says | Retake photo | Check health only | Check weight and health |
|---|---|---|---|
| `dorsal_valid` | no dialog | no dialog | no dialog |
| `health_only` | back to camera | health-only route, no override recorded | override to `dorsal_valid` |
| `reject` | back to camera | override to `health_only` | override to `dorsal_valid` |
| unresolved | no dialog | no dialog | no dialog |

This supersedes three parts of ADR-017:

- **"An overridden `reject` is routed as `dorsal_valid`"** becomes "the override carries the
  chosen route". The consent event's status is `override:<route>`; the round 9 plain
  `override` status still reads as `dorsal_valid`. On the native side the request field is
  `view_route_override` (`"dorsal_valid"` / `"health_only"`), with the old boolean
  `view_gate_override` kept as an alias for `dorsal_valid`. The decision itself is the pure
  function `stages::resolve_view_route()` (`src/stages/view_route.h`), covered by the
  model-free ctest `test_view_route`. See [../ffi-bridge.md](../ffi-bridge.md).
- **The override is no longer limited to `reject`.** A `health_only` verdict can be raised to
  the full route. A `dorsal_valid` verdict is never changed, and an override is never used to
  downgrade one.
- **"The result is labelled" is withdrawn.** The results screen no longer shows the view card
  or the override banner. The override is kept only in the database (`view_override` event)
  and in the envelope, whose `view` block gains `"override": true` and `"override_route"`
  whenever — and only when — the override actually changed the route.

Everything else in ADR-017 stands: consent is per photograph and keyed to the image's content
hash, never per scan or session; the stored verdict is never rewritten; and only the view gate
is bypassed — truncation, posture, reference-scale and feature-domain gates all still run and
can still decline to produce a number.

## Consequences

**The AGENTS.md rules 3 and 8 tension widens.** ADR-017's narrowing — explicit, recorded,
per-photograph consent replaces the view verdict as the eligibility input for that one
photograph — now also covers forcing a full weight run on a photo the classifier called
health-only. The protection is unchanged: every other gate stays live.

**Provenance is lost on screen.** An overridden result now looks the same as a clean one on
the results screen, the records list, and any export. This is the user's explicit choice
(round 10, open question 3), not an oversight. The fact is recoverable from the database and
the envelope only.

**The results cards read the route that ran, not the verdict (F70).** Without the view card to
explain a skip, the weight and health cards must tell **Skipped** (routing) from
**Unavailable** (a gate declined) themselves. `LocalScanBundle.effectiveRoute` — the override
when present, otherwise the verdict — drives both.

**F67 is still not closed.** The classifier's landscape unreliability is unchanged. This gives
the user more ways around it, not a better classifier.

**Verification.** Host: `test_view_route` covers every row of the table plus request parsing;
Dart tests cover the route round-trip, legacy-row reading, per-image scoping, the forwarded route
for each choice, the dialog, and `effectiveRoute`. Device: a sideload check with gallery
photos is owed and is recorded in `docs/fix-phase-6/4-docs-and-device.md`.
