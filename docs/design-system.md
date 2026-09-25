# Design System Reference

Maps the UI reference (Next.js at `C:\src\instaham\instaham_ui`) to Flutter equivalents for the INSTAHAM app.

## Color Tokens → `lib/core/theme/app_colors.dart`

| CSS Variable | Hex | Dart Constant |
|---|---|---|
| `--primary` | `#C2185B` | `AppColors.signalPink` |
| `--bright-pink` | `#FF5C97` | `AppColors.brightPink` |
| `--pink-tint` | `#FDE1EB` | `AppColors.pinkTint` |
| `--background` | `#FAFAFA` | `AppColors.background` |
| `--foreground` | `#121212` | `AppColors.foreground` |
| `--card` | `#FFFFFF` | `AppColors.card` |
| `--muted` | `#E0E0E0` | `AppColors.muted` |
| `--muted-foreground` | `#616161` | `AppColors.mutedForeground` |
| `--success` | `#22C55E` | `AppColors.success` |
| `--uncertain` | `#FBBF24` | `AppColors.uncertain` |
| `--blocked` | `#B45309` | `AppColors.blocked` |
| `--destructive` | `#D32F2F` | `AppColors.destructive` |
| `--border` | `#E0E0E0` | `AppColors.border` |

## Typography → `lib/core/theme/app_text_styles.dart`

| Usage | Font | Dart Style |
|---|---|---|
| Body text | Inter | `AppTextStyles.body` |
| Numeric/readout values | IBM Plex Mono | `AppTextStyles.numeric` |
| Headlines | Inter 700 | `AppTextStyles.headline` |
| Labels | Inter 500 | `AppTextStyles.label` |
| Subtext | Inter 400 | `AppTextStyles.subtext` |

## Radius Scale → `lib/core/theme/app_theme.dart`

| CSS Variable | Value |
|---|---|
| `--radius-sm` | `0.6rem` (~9.6dp) |
| `--radius-md` | `0.8rem` (~12.8dp) |
| `--radius-lg` (base) | `1rem` (~16dp) |
| `--radius-xl` | `1.4rem` (~22.4dp) |
| `--radius-2xl` | `1.8rem` (~28.8dp) |
| `--radius-3xl` | `2.2rem` (~35.2dp) |
| `--radius-4xl` | `2.6rem` (~41.6dp) |

## Status States

```dart
// 3 status states used throughout the app
enum ResultStatus { success, uncertain, blocked }
```

| State | Color | Use Case |
|---|---|---|
| `success` | Green | Valid weight/health result |
| `uncertain` | Amber | Low confidence, needs human review |
| `blocked` | Orange | Weight estimation blocked (check failed) |

## Screen Structure → Mapping from Next.js Pages

| Next.js route | Flutter Screen | Feature Module |
|---|---|---|
| `/` (home) | `MainScreen` | `core/screens/` |
| `/capture` | `CaptureScreen` | `features/capture/` |
| `/capture-guidance` | `CaptureGuidanceScreen` (optional help) | `features/capture/` |
| `/analysis` | `ResultsScreen` | `features/results/` |
| `/records` | `RecordsScreen` | `features/records/` |
| `/health` | Redirect to `/records` | legacy route |
| `/measurements` | Redirect to `/records` | legacy route |
| `/reference-marking` | `ReferenceMarkingScreen` | `features/weight_estimation/` |
| `/analytics` | `AnalyticsScreen` | `features/analytics/` |
| `/privacy` | `PrivacyScreen` | `core/` |
| Legacy result-state routes | Redirect to `/records` | states render inside `ResultsScreen` |

### Screen Deviations from Next.js UI Reference

- **Analytics Screen (`/analytics`)**:
  - Uses a left-aligned `DropdownButton` for tab selection (Overview, Weight, Health) instead of a `SegmentedButton` to save horizontal space for filters.
  - Includes a cyclical date Filter button (All Time, Last 30 Days, Last 7 Days) and a Pig Search toggle button in the top right toolbar.
  - The `OverviewPanel` uses a 2x2 grid of `StatCard` widgets (Total Scans, Filtered Scans, Avg Weight, Not Healthy) to maintain consistency with the Weight and Health panels.

## Widget Mapping

| Next.js Component | Flutter Widget | Location |
|---|---|---|
| `ScreenContainer` | `AppScaffold` | `core/theme/widgets/app_scaffold.dart` |
| `HealthStatusLabel` | `HealthStatusCard` | `features/results/presentation/widgets/` |
| `StatCard` | `StatCard` | `core/theme/widgets/stat_card.dart` |
| `Badge` | `StatusBadge` | `core/theme/widgets/status_badge.dart` |
| `BottomNav` | `AppBottomNav` | `core/router/widgets/app_bottom_nav.dart` |
| `Card` | Flutter `Card` or custom `AppCard` | `core/theme/widgets/app_card.dart` |
| `ErrorState` (generic) | `AppErrorState` | `core/theme/widgets/app_error_state.dart` |
| `Button` (default) | `FilledButton` | themed in `app_theme.dart` |
| `Button` (outline) | `OutlinedButton` | themed in `app_theme.dart` |
| `Button` (tertiary) | `TextButton` | themed in `app_theme.dart` |

## Approved End-to-End Scan Flow

```text
Home / Records
    |
    v
Camera: Reference Mode (only mode; docs/metrics-plan.md phase 4 task 5 withdrew height mode)
    |-- choose known reference preset/custom length
    v
Dominant centered shutter
    v
Photo review: Retake | Use photo
    |
    v
VIEW GATE runs here, on "Use photo" -- not at analysis time, because its
label decides which screen comes next. Routes on argmax; no threshold.
    |
    |-- reject ------> "Photo not recognized" dialog  --.
    |-- health_only -> "Weight may not be measurable"  --+-> Retake photo (status: rejected)
    |                  dialog (same three buttons)       |-> Check health only
    |                                                     `-> Check weight and health
    |
    |-- health_only route (verdict or chosen) -> analyze directly. Reference
    |                  marking is SKIPPED: it exists only to scale a weight, and
    |                  there is no weight branch here.
    |
    `-- dorsal_valid route (verdict or chosen) -> verify or manually mark reference
                       endpoints -> Confirm & analyze
    v
Independent weight and visual-health results
    v
Assign pig (optional) -> save in Records
```

The route dialog (`showViewChoiceDialog()`, `capture_screen.dart`) stacks its three buttons
full-width so each keeps a 44px target on a small phone; **Check weight and health** is the
filled button, and dismissing the dialog counts as **Retake photo**. A `dorsal_valid` verdict
never shows it.

The view gate's outcome has **no card** in results (round 10,
[adr/020](adr/020-view-route-override-either-route.md)), and an override is not shown on
screen. The weight and health cards explain a routing skip themselves (**Skipped**, read from
the route that actually ran), and it is never folded into an "Unavailable". See
[app-flow.md](app-flow.md) for the full model graph behind "analyze".

### Camera control hierarchy

- Reference Mode is the only capture mode. Height mode was withdrawn (docs/metrics-plan.md
  phase 4 task 5, finding 9): it required a height-calibrated model that was never
  available, and the capture flow now requires a marked reference object for every weight
  capture. `measurementMode`/`camera_height_cm` stay in the Drift schema (no migration, no
  behavioural gain) and still render on scans captured before this change (results screen);
  the capture UI simply no longer offers a way to produce a new one.
- A 76dp circular shutter is the dominant bottom control.
- Reference configuration is a status/action chip in the camera header.
- Reference selection displays as a 70% height modal bottom sheet. Custom reference configuration happens in-place to preserve container size.
- Weight guidance must say dorsal/top-down; never use side-on or broadside wording.
- Guidance is contextual in the camera; the full guidance screen is optional help, not a required recurring gate.

### Reference object review

- Weight mode requires a preset or a custom positive straight length in centimeters before capture.
- Custom setup asks for optional name and known length only. It does not require a separate reference photo or width.
- The review uses the actual captured photo when an image path is available.
- A validated future detector may provide normalized endpoint suggestions and confidence. Suggestions must be clearly labeled for review.
- Without a detector or below its threshold, the user places exactly two endpoints manually.
- Both endpoints use 44dp drag handles. Tapping a handle must not delete it.
- The user can change object type/name/length, clear/reset points, retake, or continue.
- Confirmation requires the reference to be flat on the same floor plane as the pig.
- Endpoint coordinates are stored normalized to the original image. `cm/pixel` is calculated only with original image dimensions; never use rendered preview dimensions as image pixels.
- Automatic reference recognition is not present in the current model package. Manual confirmation remains mandatory until a separate detector is trained and validated.

### Loading and progress contract

Every wait longer than a frame or two gets a visible, animating state. The reference
implementation is `AnalysisProgressView`
(`lib/features/results/presentation/widgets/analysis_progress_view.dart`); the next screen
that needs a progress state follows this contract rather than inventing a second pattern.

- **Indeterminate indicator only.** No progress bar, no percentage. Nothing in the pipeline
  reports fractional completion, so a filling bar would be an invented number.
- **Honest phase label.** Name only a phase the Dart side actually observes. For `/analysis`
  that is three: loading the saved scan, analyzing the photo, finishing up. The native call in
  the middle is one opaque blocking call.
- **No fabricated stage ticks.** Never render a per-stage checklist (segmentation ✓,
  measurement ✓, weight ✓) for work whose completion the app cannot observe. This is the same
  rule as "never display invented model scores" applied to progress.
- **Elapsed, not estimated.** Show an observed elapsed-seconds counter, not an ETA or a
  predicted remaining time. Pair it with a plain expectation line ("This can take up to a
  minute on some phones") so a long wait reads as expected rather than hung.
- **No cancel.** A native call already in flight cannot be interrupted, so no screen offers a
  cancel button it could not honor.
- **Leaving is warn-once, never blocked.** Work that continues and persists on a worker
  isolate must not trap the user on the screen. `PopScope` warns once, then lets the next
  press through. A screen with no in-flight work to lose gets no `PopScope` at all.
- **Controls are disabled while work is in flight**, and the control that started the work
  shows the busy state inline. Entry points re-check their own busy flag on entry, since an
  `onPressed` guard is a frame behind and a double-tap can beat it.
- **Accessibility.** The progress text is one `Semantics` live region carrying the phase and
  the elapsed count together, with the decorative duplicate text excluded, so a screen reader
  announces one coherent update instead of two fragments.

### Results and recovery

- Weight and visual-health branches render independently. A failed weight branch must never
  block, degrade, or hide a successful health result.
- Never show a fabricated health score, healthy-weight claim, diagnosis, or numeric output from a failed eligibility branch.
- Visual health shows `Possible visual indicator`, model confidence, and uncertainty wording.
  The label is always the model's argmax; the `uncertain` badge (below 0.60) is a display
  flag layered on top, never a gate that changes the label.
- The view gate has no card of its own (round 10). `Skipped` (a routing outcome — the route
  that actually ran was not `dorsal_valid`) and `Unavailable` (genuinely no number) are
  distinct weight states and must stay distinct; collapsing them has regressed twice.
- Pending model integration is shown as `Pending`; it is not replaced with mock numbers.
- A blocked reference flow offers manual review before forcing a retake.
- Retake preserves session ID, selected goal, reference configuration, pig assignment, and usable prior inputs.
- Records distinguish unassigned, pending, completed, blocked, rejected, and deleted states.

## Local Persistence and Backend Boundary

Drift/SQLite is the on-device source of truth. The database is defined in:

```text
lib/core/database/app_database.dart
lib/core/database/database_scope.dart
lib/core/models/scan_flow.dart
```

| Table | Purpose |
|---|---|
| `pigs` | Optional pig tag/display name and soft-delete metadata |
| `scan_records` | Scan goal, lifecycle, image path, measurement mode, camera height, failure, timestamps, remote/sync state |
| `reference_annotations` | Known length, normalized endpoints, source/confidence, user and floor-plane confirmation |
| `weight_results` | Eligible output, failure reason, scale, and features in fixed `RA, LC, BL, BW, E` order. `cm_per_pixel` is persisted for provenance but does not currently scale the features — the shipped regressor's feature space is `fixed_camera_pixels`. |
| `health_results` | Independent eligibility, visual class, confidence, uncertainty, and versions |
| `pipeline_events` | Stage-level progress, failure, and retry audit trail |
| `privacy_preferences` | Explicit research/analytics choices and declared inference location |
| `sync_outbox_entries` | Backend-ready pending create/update/delete operations |

Persistence rules:

- Optional research-image sharing and usage analytics default to `false`.
- The backend must consume the outbox and must not upload images unless explicit preference allows it.
- Local IDs remain stable; remote IDs are separate mappings.
- Deletion removes scans, annotations, results, pipeline events, pigs, and pending outbox entries while keeping privacy preferences.
- Database migrations increment `schemaVersion`; destructive schema replacement is not allowed for released builds.
- ML services write independent result rows and pipeline events. UI screens read stored results and do not manufacture placeholders.
- Original image paths stay local unless upload consent and backend policy both permit transfer.

## Current Integration Status

- **Implemented:** design flow, scan-session persistence, reference confirmation UI, Records
  source of truth, pig assignment, truthful result states, privacy persistence, delete
  confirmation, sync outbox schema, analytics module (with graphs), hardware camera/image
  picker, EXIF correction, and the native ML runtime — view, health, segmentation, mask
  construction, five-feature extraction, and the XGBoost weight regressor all run on-device
  in `libinstaham_ml.so`.
- **Gated, not missing — the weight number.** All five C++ stages run, but stage 3 (the
  head/neck cutter) is a permanent identity stub, so `weight.available` is `false` in every
  shipping manifest and the weight card reads "Unavailable" with reason
  `cutter_identity_stub`. This is a stated contract, not an unfinished integration.
  A developer-only export flag (`--enable-for-testing`) can surface a real but
  head-inclusive, overestimated kg value for verifying the native chain end-to-end.
- **Pending:** trained reference detector (manual endpoint marking remains mandatory), a
  cm-space regressor that actually consumes `cm_per_pixel`, binding the C++ whole-graph
  entrypoint from Dart, and the remote backend sync worker.
- A result branch that did not produce a number must stay visibly pending, skipped, or
  unavailable — and those three are distinct states, never collapsed into one.
