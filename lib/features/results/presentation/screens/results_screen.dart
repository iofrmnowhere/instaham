import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../widgets/health_status_card.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

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
              height: 160,
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
          const SizedBox(height: 16),

          Text('Measurements', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          // Weight Card
          const HealthStatusCard(
            label: 'Weight',
            value: 45.2,
            unit: 'kg',
            status: ResultStatus.success,
            subtext: 'Healthy weight range for age',
          ),
          const SizedBox(height: 12),

          // Health Score Card
          const HealthStatusCard(
            label: 'Health Score',
            value: 8.5,
            unit: '/10',
            status: ResultStatus.success,
            subtext: 'Good body condition, no concerns detected',
          ),
          const SizedBox(height: 12),

          // Veterinary Disclaimer
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: AppColors.muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              'This is not a veterinary diagnosis.',
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),

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
                  child: const Text('Done'),
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
                  child: const Text('Retake'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Export Report'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
            ),
          ),
        ],
      ),
    );
  }
}
