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
| `/` (home) | `HomeScreen` | *(in `app.dart` or `core/`)* |
| `/capture` | `CaptureScreen` | `features/capture/` |
| `/capture-guidance` | `CaptureGuidanceScreen` | `features/capture/` |
| `/analysis` | `ResultsScreen` | `features/results/` |
| `/health` | `HealthHistoryScreen` | `features/health_assessment/` |
| `/measurements` | `MeasurementsScreen` | `features/weight_estimation/` |
| `/reference-marking` | `ReferenceMarkingScreen` | `features/weight_estimation/` |
| `/analytics` | `AnalyticsScreen` | *(future)* |
| `/privacy` | `PrivacyScreen` | `core/` |
| `/reject-result` | Inline in `ResultsScreen` | `features/results/` |
| `/skip-weight` | Inline in `ResultsScreen` | `features/results/` |
| `/uncertain-result` | Inline in `ResultsScreen` | `features/results/` |
| `/weight-blocked` | Inline in `ResultsScreen` | `features/results/` |

## Widget Mapping

| Next.js Component | Flutter Widget | Location |
|---|---|---|
| `ScreenContainer` | `AppScaffold` | `core/theme/widgets/app_scaffold.dart` |
| `HealthStatusLabel` | `HealthStatusCard` | `features/results/presentation/widgets/` |
| `StatCard` | `StatCard` | `core/theme/widgets/stat_card.dart` |
| `Badge` | `StatusBadge` | `core/theme/widgets/status_badge.dart` |
| `BottomNav` | `AppBottomNav` | `core/router/widgets/app_bottom_nav.dart` |
| `Card` | Flutter `Card` or custom `AppCard` | `core/theme/widgets/app_card.dart` |
| `Button` (default) | `FilledButton` | themed in `app_theme.dart` |
| `Button` (outline) | `OutlinedButton` | themed in `app_theme.dart` |
| `Button` (tertiary) | `TextButton` | themed in `app_theme.dart` |
