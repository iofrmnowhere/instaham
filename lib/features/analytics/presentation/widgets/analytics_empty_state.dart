import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class AnalyticsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const AnalyticsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.pinkTint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppColors.signalPink),
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.headline.copyWith(fontSize: 19)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
