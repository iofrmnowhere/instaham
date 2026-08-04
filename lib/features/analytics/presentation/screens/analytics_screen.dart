import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentPath: '/analytics',
      header: Container(
        padding: const EdgeInsets.all(16.0),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analytics', style: AppTextStyles.headline.copyWith(fontSize: 24)),
            const SizedBox(height: 2),
            Text(
              'Track trends and patterns',
              style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
            ),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.signalPink.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bar_chart, size: 32, color: AppColors.signalPink),
              ),
              const SizedBox(height: 16),
              Text('Analytics Coming Soon', style: AppTextStyles.headline.copyWith(fontSize: 20)),
              const SizedBox(height: 6),
              Text(
                'Detailed insights and trend analysis will appear here as you collect more scans',
                style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
