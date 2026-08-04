import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

class CaptureGuidanceScreen extends StatefulWidget {
  const CaptureGuidanceScreen({super.key});

  @override
  State<CaptureGuidanceScreen> createState() => _CaptureGuidanceScreenState();
}

class _CaptureGuidanceScreenState extends State<CaptureGuidanceScreen> {
  String mode = 'weight-health'; // 'weight-health' or 'health-only'

  final guidanceTips = {
    'weight-health': [
      'Position pig broadside to camera',
      'Ensure good lighting and clear view',
      'Keep camera at marked height',
      'Avoid shadows and reflections',
      'Include reference object in frame',
    ],
    'health-only': [
      'Focus on pig profile view',
      'Check for visible health indicators',
      'Ensure clear facial features visible',
      'Good lighting is essential',
      'Take multiple angles if needed',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final tips = guidanceTips[mode]!;

    return AppScaffold(
      showNav: false,
      header: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => context.go('/measurements'),
            ),
            Text('Capture Tips', style: AppTextStyles.headline.copyWith(fontSize: 20)),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Mode Selector Segmented buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => mode = 'weight-health'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: mode == 'weight-health' ? AppColors.signalPink : Colors.transparent,
                    foregroundColor: mode == 'weight-health' ? Colors.white : AppColors.foreground,
                    side: const BorderSide(color: AppColors.signalPink),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  child: const Text('Weight + Health'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => mode = 'health-only'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: mode == 'health-only' ? AppColors.signalPink : Colors.transparent,
                    foregroundColor: mode == 'health-only' ? Colors.white : AppColors.foreground,
                    side: const BorderSide(color: AppColors.signalPink),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  child: const Text('Health Only'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Guidance Card
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best Practices', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...tips.map((tip) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(tip, style: AppTextStyles.body.copyWith(fontSize: 13)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Example Section
          Text('Example', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          AppCard(
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.muted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: Text(
                mode == 'weight-health'
                    ? 'Side view with reference object'
                    : 'Profile view for health assessment',
                style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.go('/measurements'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  ),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context.push('/capture'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.signalPink,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  ),
                  child: const Text('Start Capture'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
