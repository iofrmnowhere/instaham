import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../database/database_scope.dart';
import '../models/scan_flow.dart';
import '../models/scan_with_pig.dart';
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
    return AppScaffold(
      currentPath: '/',
      header: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'INSTAHAM',
              style: AppTextStyles.headline.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 2),
            Text(
              'On-device pig screening records',
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      child: StreamBuilder<List<ScanWithPig>>(
        stream: DatabaseScope.of(
          context,
        ).recordsDao.watchRecentScans(limit: 20),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <ScanWithPig>[];
          final today = DateTime.now();
          final scansToday = items.where((item) {
            final date = item.scan.createdAt.toLocal();
            return date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;
          }).length;
          final needsReview = items
              .where(
                (item) =>
                    item.scan.status == ScanStatuses.blocked ||
                    item.scan.status == ScanStatuses.rejected,
              )
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              AppCard(
                backgroundColor: AppColors.signalPink,
                border: Border.all(color: AppColors.signalPink),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start a new scan',
                      style: AppTextStyles.headline.copyWith(
                        color: Colors.white,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose Weight + Health or Health Only in the camera.',
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () => context.push('/capture'),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Open camera'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.signalPink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Scans Today',
                      value: '$scansToday',
                      icon: const Icon(Icons.bolt),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Needs Review',
                      value: '$needsReview',
                      icon: const Icon(Icons.error_outline),
                      status: needsReview > 0
                          ? StatCardStatus.warning
                          : StatCardStatus.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent scans',
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/records'),
                    child: const Text('View all'),
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (items.isEmpty)
                AppCard(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 38,
                        color: AppColors.mutedForeground,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No scans saved yet',
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Your first captured scan will appear here.',
                        style: AppTextStyles.subtext.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...items.take(5).map((item) => _RecentScanCard(item: item)),
            ],
          );
        },
      ),
    );
  }
}

class _RecentScanCard extends StatelessWidget {
  final ScanWithPig item;

  const _RecentScanCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scan = item.scan;
    final goal = scanGoalFromStorage(scan.goal);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () => context.push(
          '/analysis',
          extra: ScanFlowArgs(
            sessionId: scan.id,
            goal: goal,
            imagePath: scan.imagePath,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.pinkTint,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                goal.requiresReference
                    ? Icons.monitor_weight_outlined
                    : Icons.health_and_safety_outlined,
                color: AppColors.signalPink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayPigName,
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${goal.label} · ${scan.status.replaceAll('_', ' ')}',
                    style: AppTextStyles.subtext.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.mutedForeground),
          ],
        ),
      ),
    );
  }
}
