# Phase 4, task 1 — recorded envelopes for the 11 scenario fixtures

**STALE as of `docs/metrics-phase/3.1-corpus-rebuild.md`.** Every fixture image below was
regenerated from a different source (`.pig_pictures/` and `health_pigs/` instead of
PIGRGB/mixed sources) — the per-scenario `observed`/`verdict` results here describe images
that no longer exist at those paths. Re-run task 1 against the rebuilt corpus before trusting
any row in the table below as current. The two pipeline-level bugs in "Two bugs surfaced"
(the JiDuan kernel-sizing hang, the missing native HEIC decoder) are code-level findings, not
fixture-specific, and likely still apply — but that has not been re-confirmed against the new
corpus either.

Per `docs/metrics-plan.md` phase 4, task 1: ran all 11 fixtures through the phase 2 harness
(`test/support/native_harness.dart`'s load recipe, driven from a throwaway Dart script, not
committed) with `INSTAHAM_NATIVE_TESTS=1` against the Windows host build, and recorded the
actual envelope each produced into an `observed_phase4` (or `phase4_blocked`) block in that
scenario's `meta.json`. This closes known gaps 1, 3, and 4 from `docs/metrics-phase/
3-fixture-corpus.md`, and corrects several other hypotheses that turned out wrong. Gap 2
(pixel endpoints for scenarios 1, 2, 3, 11) is still open — these runs did not pass
`cm_per_px`.

## Results by scenario

| # | expected (pre-phase-4) | observed | verdict |
|---|---|---|---|
| 1 | weight number | `cutter_failed` (`no_terminal_balls`) — independent of the missing reference | corrected: weight_branch.expect_number is now flagged unconfirmed |
| 2 | weight number | `cutter_failed` (`jiduan_failed`) — same shape as 1 | corrected: unconfirmed |
| 3 | weight number | cutter succeeds, reaches `weight_needs_reference_object` cleanly | confirmed reachable, only gap 2 blocks the final number |
| 4 | blocked, `weight_needs_reference_object`, health assessed | exact match | confirmed |
| 5 | `health_only` (placeholder caveat) | `dorsal_valid` — gap 1 confirmed, placeholder does not exercise health_only at all | corrected |
| 6 | `health_only`, reason `weight_needs_reference_object` | view confirmed, reason is actually `view_not_dorsal` (never reaches the reference check) | reason corrected |
| 7 | reason TBD (finding 5's `multiple_pigs` known dead) | `dorsal_valid`, one pig's mask selected, blocked by the ordinary `mask_implausibly_small` gate — no pig-count-aware logic involved | resolved |
| 8 | `reject`, health NOT assessed | `health_only`, health IS assessed (`view_not_dorsal`) — radius-8 blur insufficient to reach `reject` | corrected; blur radius increase + fixture regen is a separate follow-up, not done here |
| 9 | reason unknown (gate off in manifest) | gate off: ordinary `weight_needs_reference_object`, truncation never flagged. Gate on (test-copy manifest): `truncation_gate_rejected` / `weight_truncation_gate_rejected`, health still assessed | both variants confirmed, finding 6 verified |
| 10 | `weight_needs_reference_object` | **BLOCKED** — native pipeline hangs on this fixture's image, reproducible twice, process CPU stays at 0 for 5+ minutes vs. <15s for every other scenario | **unresolved bug, see below** |
| 11 | weight number, cross-container agreement | JPEG and PNG agree (`dorsal_valid`, `mask_implausibly_small`); **HEIC fails to decode** (`view.status: error`, all downstream stages `view_unresolved`) | expect_number corrected; **HEIC decode bug, see below** |

## Two bugs surfaced

Task 1 was a recording pass; both bugs below were investigated further this round (per the
user's "fix the bugs first" direction) to root cause, but neither is fixed yet -- both
touch validated/architectural code and need a direction decision first (see each entry).

1. **Scenario 10's image effectively never finishes in the native pipeline -- root cause
   confirmed.** `packages/instaham_ml_ffi/src/vendor/instaham_v176/src/preprocess/
   JiDuan.cpp`'s `applyJiDuan()` sizes its morphological-opening kernel as
   `area / areaDivisor` (areaDivisor = 800). For this fixture's mask (area 320175 px on an
   803×1600 canvas) that produces a **401×401 elliptical structuring element** passed to
   `cv::morphologyEx(..., MORPH_OPEN, ...)`. The only existing clamp is `min(rows, cols)`
   (~803 here), which does nothing to bound a kernel this large. Checkpoint instrumentation
   added and fully reverted this session isolated the exact call and confirmed it via two
   CPU-time samples 10 minutes apart reading identical (11.28s) -- true stall, not merely
   slow. This is not test-corpus-only: the same unbounded formula ships in production, so a
   real photo with a large segmented mask on a narrow-ish frame can trigger the same
   effective hang with no timeout. **Fix needs a decision**: this is vendor cutter code
   documented elsewhere (`ref_fix.md`, `VALIDATION.md`) as validated against a Python parity
   oracle, so capping kernel size affects that parity and needs a call on where to draw the
   line and whether `ML/parity/` needs re-verification after. Root cause and full detail
   recorded in scenario 10's `meta.json` (`phase4_blocked`).
2. **HEIC decode fails in the native pipeline for scenario 11's `image.heic` -- root cause
   confirmed, may not be a bug at this layer.** `util/image_io.cpp`'s `decode_image_rgb` is
   stb_image compiled with `STBI_ONLY_JPEG`/`PNG`/`BMP` -- HEIC support was never built in,
   by design, not by accident. Separately, in production the Flutter layer
   (`lib/core/utils/image_service.dart`'s `processCapture`/`processRawBytes`) **always**
   decodes via `package:image` and re-encodes to JPEG before any image path reaches native
   code, so the shipped app never hands native code a raw HEIC file. Scenario 11's Tier B
   premise -- feeding the native harness a raw `.heic` file directly -- bypasses that Dart
   normalization layer entirely, so it may be exercising a guarantee the architecture never
   makes at the native layer. **Needs a direction decision, not a native-code fix**: either
   (a) add real HEIC decoding to the native pipeline (a real cross-platform dependency
   addition, e.g. libheif via vcpkg/NDK), or (b) treat native-layer HEIC as intentionally
   unsupported and correct scenario 11 to test what the architecture actually guarantees
   (JPEG/PNG agreement post-Dart-normalization), dropping or reclassifying its HEIC leg.

## Next steps (phase 4 tasks 2-4, per docs/metrics-plan.md)

- Task 2: rewrite the 11 scenario titles against the live reason vocabulary now recorded
  here.
- Task 3: write two-tier bodies per scenario.
- Task 4: ruling on `WeightEligibilityChecker` still needed before scenarios 7/9/10 are
  finalized (7 no longer depends on it per this round's finding; 9 does not either; 10 is
  blocked independent of this ruling).
- The two bugs above should get their own fix-doc entries (`docs/fix-3.md` or a new phase)
  before Tier B bodies for scenarios 10 and 11 can be written truthfully.
