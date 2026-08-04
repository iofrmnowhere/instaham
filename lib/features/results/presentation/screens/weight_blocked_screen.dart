import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../widgets/health_status_card.dart';

class WeightBlockedScreen extends StatelessWidget {
  const WeightBlockedScreen({super.key});

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
          const SizedBox(height: 16),

          Text('Measurements', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          // Blocked Weight Card
          AppCard(
            backgroundColor: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade200),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 20, color: Colors.orange.shade900),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Weight', style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground)),
                      const SizedBox(height: 2),
                      Text(
                        'Unavailable',
                        style: AppTextStyles.numeric.copyWith(
                          fontSize: 22,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Reference object was not detected. Include it in your next scan for weight measurement.',
                        style: AppTextStyles.subtext.copyWith(color: Colors.orange.shade900),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => context.push('/capture'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade900,
                          side: BorderSide(color: Colors.orange.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Health Score Card (Independent & Success)
          const HealthStatusCard(
            label: 'Health Score',
            value: 8.1,
            unit: '/10',
            status: ResultStatus.success,
            subtext: 'Good body condition detected',
          ),
          const SizedBox(height: 16),

          // Blue Info Box
          AppCard(
            backgroundColor: Colors.blue.shade50,
            border: Border.all(color: Colors.blue.shade200),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 20, color: Colors.blue.shade900),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Health assessment is complete. Retake with your reference object to get weight measurements.',
                    style: AppTextStyles.subtext.copyWith(color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

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
        ],
      ),
    );
  }
}
