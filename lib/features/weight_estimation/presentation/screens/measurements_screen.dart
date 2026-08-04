import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

class MeasurementsScreen extends StatelessWidget {
  const MeasurementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentPath: '/measurements',
      header: Container(
        padding: const EdgeInsets.all(16.0),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Measurements', style: AppTextStyles.headline.copyWith(fontSize: 24)),
            const SizedBox(height: 2),
            Text(
              'Capture and track measurements',
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
                child: const Icon(Icons.camera_alt_outlined, size: 32, color: AppColors.signalPink),
              ),
              const SizedBox(height: 16),
              Text('Start a New Scan', style: AppTextStyles.headline.copyWith(fontSize: 20)),
              const SizedBox(height: 6),
              Text(
                'Position your pig and tap below to begin capturing measurements',
                style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.push('/capture-guidance'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.signalPink,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                ),
                child: const Text('Start Capture'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
