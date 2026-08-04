import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

class RejectResultScreen extends StatelessWidget {
  const RejectResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showNav: false,
      child: Center(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24.0),
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.destructive.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, size: 32, color: AppColors.destructive),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('Scan Failed', style: AppTextStyles.headline.copyWith(fontSize: 24)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                "We couldn't process this image. See details below.",
                style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // Error Details Card
            AppCard(
              backgroundColor: AppColors.destructive.withValues(alpha: 0.05),
              border: Border.all(color: AppColors.destructive.withValues(alpha: 0.2)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What went wrong:',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.destructive,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildErrorItem('Poor lighting or shadows detected'),
                  _buildErrorItem('Pig positioning not aligned with guide'),
                  _buildErrorItem('Reference object not clearly visible'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // How to fix Card
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to fix it:', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildFixItem('Move to a brighter location'),
                  _buildFixItem('Position pig side-on to camera'),
                  _buildFixItem('Ensure reference object is in frame'),
                  _buildFixItem('Check camera height setting'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: () => context.push('/capture-guidance'),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('View Tips'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.signalPink,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/capture'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
              child: const Text('Retake Photo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppColors.destructive)),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body.copyWith(fontSize: 13, color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTextStyles.body.copyWith(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
