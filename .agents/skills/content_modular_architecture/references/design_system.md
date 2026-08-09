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
Camera: Weight + Health | Health Only
    |-- Weight + Health -> choose known reference preset/custom length
    |-- Health Only -> no reference setup
    v
Dominant centered shutter
    v
Photo review: Retake | Use photo
    |-- Weight + Health -> verify or manually mark reference endpoints
    |                      -> Confirm & analyze | Continue health only
    |-- Health Only ------> analyze
    v
Independent weight and visual-health results
    v
Assign pig (optional) -> save in Records
```

### Camera control hierarchy

- The only top-level capture modes are `Weight + Health` and `Health Only`.
- The mode selector stays at the top of the camera and persists for the scan session.
- A 76dp circular shutter is the dominant bottom control.
- Reference configuration is a status/action chip, never a capture mode.
- Weight guidance must say dorsal/top-down; never use side-on or broadside wording.
- The former camera-height flow is not a weight scale method. Phone alignment can be a guidance signal only.
- Guidance is contextual in the camera; the full guidance screen is optional help, not a required recurring gate.

### Reference object review

- Weight mode requires a preset or a custom positive straight length in centimeters before capture.
- Custom setup asks for optional name and known length only. It does not require a separate reference photo or width.
- The review uses the actual captured photo when an image path is available.
- A validated future detector may provide normalized endpoint suggestions and confidence. Suggestions must be clearly labeled for review.
- Without a detector or below its threshold, the user places exactly two endpoints manually.
- Both endpoints use 44dp drag handles. Tapping a handle must not delete it.
- The user can change object type/name/length, clear/reset points, retake, or continue with health only.
- Confirmation requires the reference to be flat on the same floor plane as the pig.
- Endpoint coordinates are stored normalized to the original image. `cm/pixel` is calculated only with original image dimensions; never use rendered preview dimensions as image pixels.
- Automatic reference recognition is not present in the current model package. Manual confirmation remains mandatory until a separate detector is trained and validated.

### Results and recovery

- Weight and visual-health branches render independently.
- Never show a fabricated health score, healthy-weight claim, diagnosis, or numeric output from a failed eligibility branch.
- Visual health shows `Possible visual indicator`, model confidence, and uncertainty wording.
- Pending model integration is shown as `Pending`; it is not replaced with mock numbers.
- A blocked reference flow offers manual review or health-only continuation before forcing a retake.
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
| `scan_records` | Scan goal, lifecycle, image path, failure, timestamps, remote/sync state |
| `reference_annotations` | Known length, normalized endpoints, source/confidence, user and floor-plane confirmation |
| `weight_results` | Eligible output, failure reason, scale, and features in fixed `RA, LC, BL, BW, E` order |
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

- Implemented: design flow, scan-session persistence, reference confirmation UI, Records source of truth, pig assignment, truthful result states, privacy persistence, delete confirmation, sync outbox schema, and analytics module (with graphs).
- Pending: hardware camera/image picker integration, EXIF correction, trained reference detector, concrete ML service implementations, and remote backend sync worker.
- Until the model pipeline is integrated, result branches must remain visibly pending or unavailable.
