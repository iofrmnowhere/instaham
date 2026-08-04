import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

class SkipWeightScreen extends StatelessWidget {
  const SkipWeightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showNav: false,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.x2l)),
            ),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.uncertain.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline, color: AppColors.blocked),
                ),
                const SizedBox(height: 12),
                Text(
                  'Skip Weight Measurement?',
                  style: AppTextStyles.headline.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  'You can still capture health information without a reference object',
                  style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('You will get:', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('✓ ', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                          Text('Health score and indicators', style: AppTextStyles.body.copyWith(fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('✗ ', style: TextStyle(color: AppColors.destructive, fontWeight: FontWeight.bold)),
                          Text('Weight estimation', style: AppTextStyles.body.copyWith(fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.push('/capture'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        ),
                        child: const Text('Keep Reference Mode'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.go('/measurements'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.signalPink,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        ),
                        child: const Text('Skip Weight'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'You can always retake with a reference object later',
                  style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
