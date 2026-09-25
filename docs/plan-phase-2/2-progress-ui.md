# Phase 2 — loading and progress UI for both waits

Status: implemented; device-checked 2026-09-23 for the indicators only

The user sideloaded and confirmed the visible result: "it's working great now." That covers
the animating indicator on both waits. It does **not** cover the large-text-scale layout, the
back-press-leaves-a-complete-scan behaviour, or the elapsed counter's frame cost on low-tier
hardware -- those were never observed either way and phase 3's device step still owes them.

Depends on phase 1. Building this first would produce an indicator that is painted once and
then frozen for the whole run, which is the current defect with extra steps.

## Goal

Replace both silent waits with a visible, animating, app-styled progress state that tells the
user what is happening and roughly how long it may take, without claiming any stage result the
app does not have.

## Design/Approach

### Wait A — capture review, "Verify reference"

`_usePhoto` (`capture_screen.dart:383`) sets `_saving = true` around `resolveViewGate`, but
`_buildReview()` never reads `_saving`: the button is not disabled and nothing indicates work.
A second tap during the wait re-enters `_usePhoto`, which is also a double-run hazard.

- Disable both review actions while `_saving` is true, and show an inline indicator in the
  primary button (the camera shutter in `_buildCamera()` already uses this pattern at
  `capture_screen.dart:649` — reuse its shape rather than inventing a second one).
- Add a short status line under the buttons: "Checking the photo…". No percentage, no stage
  breakdown — one model runs here.
- The existing reject dialog flow is unchanged; the indicator clears before the dialog opens,
  as it already does at `capture_screen.dart:400`.

### Wait B — `/analysis`, the full pipeline

`ResultsScreen`'s `FutureBuilder` currently renders `Center(CircularProgressIndicator())` for
everything that is not `ConnectionState.done` (`results_screen.dart:187`). Replace that branch
with a dedicated widget, `AnalysisProgressView`, in
`lib/features/results/presentation/widgets/`.

Contents, in order of importance:

1. An animating indeterminate indicator plus the app's existing card/typography tokens
   (`AppCard`, `AppTextStyles`, `AppColors`) so it reads as the same product, not a bare
   Material default.
2. A single honest phase label. The only boundaries Dart actually observes are: loading the
   scan bundle, running the native pipeline, re-loading the persisted bundle. Label them as
   such ("Analyzing the photo…" for the long middle phase) and do not render a per-stage
   checklist of segmentation/measurement/weight — the native call is opaque and those ticks
   would be fabricated (AGENTS.md: never display invented model scores, predictions, or
   completed states).
3. An expectation line, because 12–71 seconds of silence reads as a crash: "This can take up to
   a minute on some phones." Do not print a countdown or an ETA — no per-device estimate exists
   at runtime.
4. An elapsed-seconds counter is acceptable (it is observed, not predicted) and is the cheapest
   way to show liveness on a low-tier device. Optional; decide during implementation, and drop
   it if it adds a timer that outlives the widget.

### Behaviour while analyzing

- **Back-press**: the run continues in the worker isolate and `RunAndPersistPipelineUseCase`
  persists its results regardless of whether the screen is alive, so leaving is safe and the
  scan is complete when reopened from Records. Wrap the progress state in a `PopScope` that
  warns once ("Analysis will finish in the background") rather than blocking. Open question 1
  in `plan-2.md` owns whether the user wants blocking instead.
- **No Cancel button.** The native ABI has no cancel token, so a cancel could only abandon the
  wait, not the work; offering it would misrepresent what the app can do.
- **No re-entry.** `_loadAndRunPipelineIfNeeded` already runs the pipeline only when
  `bundle.health == null`, and `_reload()` is called from `didChangeDependencies` once. Confirm
  a rebuild during the wait does not create a second future.

### Accessibility (AGENTS.md UI contract)

- `Semantics` with `liveRegion: true` on the status text so a screen reader announces phase
  changes; label the indicator rather than leaving it unlabeled.
- Text scales; the layout must survive a large text scale without overflow.
- Any interactive element (the warn dialog's buttons) keeps a 44×44 logical-pixel target.
- Contrast is taken from the existing theme tokens, not hand-picked greys.

## Steps

- [x] `AnalysisProgressView` widget + its phase enum, in
      `lib/features/results/presentation/widgets/`.
- [x] `ResultsScreen`: swap the bare indicator branch for the new widget and feed it the phase
      the screen is actually in.
- [x] `PopScope` warn-once behaviour while the analysis phase is active.
- [x] `capture_screen.dart`: disable review actions on `_saving`, inline button indicator,
      "Checking the photo…" status line.
- [x] Check `reference_marking_screen.dart`'s existing saving indicator
      (`reference_marking_screen.dart:709`) still reads consistently with the new one; align the
      copy if it does not. No behaviour change there. — Already the same disabled-button +
      inline-spinner pattern; left untouched.

## Verification

- `dart format`, `flutter analyze`.
- Widget tests (phase 3 owns them) for: the progress view's three phases, the disabled review
  actions, and that no stage-completion text appears while the pipeline future is pending.
- Device check: one full scan on a physical phone, confirming the indicator animates, the copy
  is readable at a large text scale, and a back-press mid-analysis leaves a complete scan in
  Records.

## Open questions

- ~~Whether the elapsed counter ships.~~ Resolved: shipped. `AnalysisProgressView` uses a
  `Timer.periodic(1s)` (not a `Ticker`) driving a `Stopwatch`, cancelled in `dispose()`. Confirm
  on the device check that it doesn't visibly cost frames on `lion`-tier hardware during the
  ~71 s wait; if it does, the fallback is dropping the counter and keeping the static copy.
