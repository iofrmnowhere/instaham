import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/stat_card.dart';
import '../../domain/models/analytics_models.dart';
import 'analytics_empty_state.dart';
import 'health_bar_chart.dart';
import 'weight_line_chart.dart';

class OverviewPanel extends StatelessWidget {
  final int totalScanRecords;
  final int filteredScanRecords;
  final AnalyticsDateFilter dateFilter;
  final WeightAnalytics weightData;
  final HealthAnalytics healthData;
  final List<WeightDataPoint> weightTimeSeries;
  final List<HealthClassBar> healthClassBars;

  const OverviewPanel({
    super.key,
    required this.totalScanRecords,
    required this.filteredScanRecords,
    required this.dateFilter,
    required this.weightData,
    required this.healthData,
    required this.weightTimeSeries,
    required this.healthClassBars,
  });

  String get _filterLabel {
    switch (dateFilter) {
      case AnalyticsDateFilter.allTime:
        return 'All Time Scans';
      case AnalyticsDateFilter.thisMonth:
        return 'Last 30 Days Scans';
      case AnalyticsDateFilter.thisWeek:
        return 'Last 7 Days Scans';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (totalScanRecords == 0 &&
        weightData.totalScans == 0 &&
        healthData.totalScans == 0) {
      return const AnalyticsEmptyState(
        icon: Icons.analytics_outlined,
        title: 'No analytics yet',
        subtitle:
            'Overview statistics and trends will appear here once scans are recorded.',
      );
    }

    final notHealthyCount = healthData.classCounts.entries
        .where((e) => e.key.trim().toLowerCase() != 'healthy')
        .fold(0, (sum, e) => sum + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Total Scans',
                value: '$totalScanRecords',
                icon: const Icon(Icons.inventory_2_outlined),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: _filterLabel,
                value: '$filteredScanRecords',
                icon: const Icon(Icons.filter_alt_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Avg Weight',
                value: weightData.averageKg?.toStringAsFixed(1) ?? '—',
                unit: 'kg',
                icon: const Icon(Icons.scale_outlined),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'Not Healthy',
                value: '$notHealthyCount',
                icon: const Icon(Icons.warning_amber_outlined),
                status: notHealthyCount > 0 ? StatCardStatus.warning : null,
              ),
            ),
          ],
        ),
        if (weightTimeSeries.isNotEmpty) ...[
          const SizedBox(height: 16),
          WeightLineChart(points: weightTimeSeries),
        ],
        if (healthClassBars.isNotEmpty) ...[
          const SizedBox(height: 16),
          HealthBarChart(bars: healthClassBars),
        ],
      ],
    );
  }
}
