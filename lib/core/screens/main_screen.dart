import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../theme/widgets/app_card.dart';
import '../theme/widgets/app_scaffold.dart';
import '../theme/widgets/stat_card.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final recentScans = [
      {'id': 1, 'pig': 'Pig #042', 'date': '2 hours ago', 'weight': '45kg', 'health': 'Good'},
      {'id': 2, 'pig': 'Pig #038', 'date': '4 hours ago', 'weight': '42kg', 'health': 'Monitor'},
      {'id': 3, 'pig': 'Pig #035', 'date': 'Yesterday', 'weight': '48kg', 'health': 'Good'},
    ];

    return AppScaffold(
      currentPath: '/',
      header: Container(
        padding: const EdgeInsets.all(16.0),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('INSTAHAM', style: AppTextStyles.headline.copyWith(fontSize: 24)),
            const SizedBox(height: 2),
            Text(
              'Farm Health Monitoring',
              style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
            ),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          // Welcome Card
          AppCard(
            backgroundColor: AppColors.signalPink,
            border: Border.all(color: AppColors.signalPink),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back',
                  style: AppTextStyles.headline.copyWith(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap below to start a new scan',
                  style: AppTextStyles.body.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.push('/capture-guidance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.signalPink,
                    elevation: 0,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: Text(
                    'Start Capture',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.signalPink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stat Cards Grid
          Row(
            children: [
              const Expanded(
                child: StatCard(
                  label: 'Scans Today',
                  value: '12',
                  icon: Icon(Icons.bolt),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: StatCard(
                  label: 'Health Alerts',
                  value: '2',
                  icon: Icon(Icons.error_outline),
                  status: StatCardStatus.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Recent Scans
          Text('Recent Scans', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          ...recentScans.map((scan) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: AppCard(
                onTap: () => context.push('/analysis'),
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scan['pig'] as String,
                            style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            scan['date'] as String,
                            style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          scan['weight'] as String,
                          style: AppTextStyles.numeric.copyWith(fontSize: 14),
                        ),
                        Text(
                          scan['health'] as String,
                          style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20, color: AppColors.mutedForeground),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
