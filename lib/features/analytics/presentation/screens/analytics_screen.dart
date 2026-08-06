import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../../../core/theme/widgets/stat_card.dart';
import '../../domain/models/analytics_models.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AppDatabase? _database;
  Stream<WeightAnalytics>? _weightStream;
  Stream<HealthAnalytics>? _healthStream;
  String _selectedTab = 'weight';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_database != null) return;
    _database = DatabaseScope.of(context);
    _weightStream = _database!.watchWeightAnalytics();
    _healthStream = _database!.watchHealthAnalytics();
  }

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
            Text(
              'Analytics',
              style: AppTextStyles.headline.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 2),
            Text(
              'Track trends and patterns for weight and health',
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'weight',
                    label: Text('Weight Analytics'),
                    icon: Icon(Icons.monitor_weight_outlined),
                  ),
                  ButtonSegment<String>(
                    value: 'health',
                    label: Text('Health Analytics'),
                    icon: Icon(Icons.health_and_safety_outlined),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (selection) {
                  setState(() => _selectedTab = selection.first);
                },
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 24.0),
              child: _selectedTab == 'weight'
                  ? _WeightPanel(stream: _weightStream)
                  : _HealthPanel(stream: _healthStream),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightPanel extends StatelessWidget {
  final Stream<WeightAnalytics>? stream;

  const _WeightPanel({required this.stream});

  @override
  Widget build(BuildContext context) {
    if (stream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<WeightAnalytics>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final data = snapshot.data ?? WeightAnalytics.empty();
        if (data.eligibleScans == 0) {
          return const _AnalyticsEmptyState(
            icon: Icons.monitor_weight_outlined,
            title: 'No weight analytics yet',
            subtitle:
                'Collect scans with valid reference objects to view weight statistics.',
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Total Scans',
                    value: '${data.totalScans}',
                    icon: const Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'Avg Weight',
                    value: data.averageKg?.toStringAsFixed(1) ?? '—',
                    unit: 'kg',
                    icon: const Icon(Icons.scale_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Min Weight',
                    value: data.minKg?.toStringAsFixed(1) ?? '—',
                    unit: 'kg',
                    icon: const Icon(Icons.arrow_downward_outlined),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'Max Weight',
                    value: data.maxKg?.toStringAsFixed(1) ?? '—',
                    unit: 'kg',
                    icon: const Icon(Icons.arrow_upward_outlined),
                  ),
                ),
              ],
            ),
            if (data.blockedScans > 0) ...[
              const SizedBox(height: 8),
              StatCard(
                label: 'Ineligible / Blocked',
                value: '${data.blockedScans}',
                icon: const Icon(Icons.block_outlined),
                status: StatCardStatus.warning,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HealthPanel extends StatelessWidget {
  final Stream<HealthAnalytics>? stream;

  const _HealthPanel({required this.stream});

  @override
  Widget build(BuildContext context) {
    if (stream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<HealthAnalytics>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final data = snapshot.data ?? HealthAnalytics.empty();
        if (data.eligibleScans == 0) {
          return const _AnalyticsEmptyState(
            icon: Icons.health_and_safety_outlined,
            title: 'No health analytics yet',
            subtitle:
                'Health assessment trends will appear here as you perform pig health scans.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Total Scans',
                    value: '${data.totalScans}',
                    icon: const Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'Eligible',
                    value: '${data.eligibleScans}',
                    icon: const Icon(Icons.check_circle_outline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Uncertain',
                    value: '${data.uncertainScans}',
                    icon: const Icon(Icons.help_outline),
                    status: data.uncertainScans > 0
                        ? StatCardStatus.warning
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'Blocked',
                    value: '${data.blockedScans}',
                    icon: const Icon(Icons.block_outlined),
                    status: data.blockedScans > 0
                        ? StatCardStatus.warning
                        : null,
                  ),
                ),
              ],
            ),
            if (data.classCounts.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Status Breakdown',
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...data.classCounts.entries.map((entry) {
                      final count = entry.value;
                      final ratio = data.eligibleScans > 0
                          ? count / data.eligibleScans
                          : 0.0;
                      final isHealthy =
                          entry.key.trim().toLowerCase() == 'healthy';
                      final color = isHealthy
                          ? AppColors.success
                          : AppColors.uncertain;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  entry.key,
                                  style: AppTextStyles.label.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '$count scan${count == 1 ? '' : 's'} (${(ratio * 100).toStringAsFixed(0)}%)',
                                  style: AppTextStyles.subtext.copyWith(
                                    color: AppColors.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 8,
                                backgroundColor: AppColors.muted,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AnalyticsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AnalyticsEmptyState({
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
              decoration: BoxDecoration(
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
