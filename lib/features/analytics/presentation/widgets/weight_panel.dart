import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/stat_card.dart';
import '../../domain/models/analytics_models.dart';
import 'analytics_empty_state.dart';
import 'weight_line_chart.dart';

class WeightPanel extends StatelessWidget {
  final WeightAnalytics data;
  final List<WeightDataPoint> timeSeries;

  const WeightPanel({super.key, required this.data, required this.timeSeries});

  @override
  Widget build(BuildContext context) {
    if (data.eligibleScans == 0) {
      return const AnalyticsEmptyState(
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
        if (timeSeries.isNotEmpty) ...[
          const SizedBox(height: 16),
          WeightLineChart(points: timeSeries),
        ],
      ],
    );
  }
}
