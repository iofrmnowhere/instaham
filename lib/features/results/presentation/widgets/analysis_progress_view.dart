import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_card.dart';

/// plan-phase-2/2-progress-ui.md: the only phase boundaries Dart actually observes while
/// `_loadAndRunPipelineIfNeeded` runs. Labels must stay honest -- no per-stage checklist,
/// since the native call is opaque and inventing ticks for segmentation/measurement/weight
/// would be a fabricated completed state (AGENTS.md).
enum AnalysisPhase {
  loadingBundle('Loading the saved scan…'),
  runningPipeline('Analyzing the photo…'),
  reloadingBundle('Finishing up…');

  final String label;

  const AnalysisPhase(this.label);
}

/// Replaces the bare `CircularProgressIndicator()` on `/analysis` (results_screen.dart)
/// with an app-styled, animating wait that names the phase Dart is actually in and warns
/// the wait can be long, without claiming any result the pipeline has not produced yet.
class AnalysisProgressView extends StatefulWidget {
  final AnalysisPhase phase;

  const AnalysisProgressView({super.key, required this.phase});

  @override
  State<AnalysisProgressView> createState() => _AnalysisProgressViewState();
}

class _AnalysisProgressViewState extends State<AnalysisProgressView> {
  late final Stopwatch _stopwatch;
  Timer? _ticker;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    // Elapsed-seconds counter: observed, not predicted, so it is honest liveness rather
    // than an ETA. Ticks at 1s; disposed with the widget so it never outlives it.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds = _stopwatch.elapsed.inSeconds);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 18),
              Semantics(
                liveRegion: true,
                label: '${widget.phase.label} $_elapsedSeconds seconds elapsed',
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      Text(
                        widget.phase.label,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$_elapsedSeconds s',
                        style: AppTextStyles.subtext.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This can take up to a minute on some phones.',
                textAlign: TextAlign.center,
                style: AppTextStyles.subtext.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
