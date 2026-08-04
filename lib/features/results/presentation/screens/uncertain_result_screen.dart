import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../widgets/health_status_card.dart';

class UncertainResultScreen extends StatelessWidget {
  const UncertainResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              icon: const Icon(Icons.chevron_left),
              onPressed: () => context.go('/measurements'),
            ),
            Text('Analysis Results', style: AppTextStyles.headline.copyWith(fontSize: 20)),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Photo Thumbnail Card
          AppCard(
            padding: EdgeInsets.zero,
            backgroundColor: AppColors.muted,
            child: SizedBox(
              height: 140,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('📸', style: TextStyle(fontSize: 32)),
                    const SizedBox(height: 4),
                    Text(
                      'Scan Photo',
                      style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Quality Warning Card
          AppCard(
            backgroundColor: AppColors.uncertain.withValues(alpha: 0.1),
            border: Border.all(color: AppColors.uncertain.withValues(alpha: 0.3)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 20, color: AppColors.blocked),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Image Quality Issues Detected',
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.blocked,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lighting or pig positioning may affect accuracy. Review results carefully or retake.',
                        style: AppTextStyles.subtext.copyWith(color: AppColors.blocked),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text('Measurements', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          const HealthStatusCard(
            label: 'Weight',
            value: 44.8,
            unit: 'kg',
            status: ResultStatus.uncertain,
            subtext: 'Range: 43-46 kg (confidence: 72%)',
          ),
          const SizedBox(height: 12),

          const HealthStatusCard(
            label: 'Health Score',
            value: 7.2,
            unit: '/10',
            status: ResultStatus.uncertain,
            subtext: 'Possible minor concerns - recommend review',
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
                  child: const Text('Retake'),
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
                  child: const Text('Submit Anyway'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          OutlinedButton(
            onPressed: () => context.push('/capture-guidance'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
            ),
            child: const Text('Get Tips for Better Results'),
          ),
        ],
      ),
    );
  }
}
