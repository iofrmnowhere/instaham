import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/stat_card.dart';
import '../../domain/models/analytics_models.dart';
import 'analytics_empty_state.dart';
import 'health_bar_chart.dart';

class HealthPanel extends StatelessWidget {
  final HealthAnalytics data;
  final List<HealthClassBar> classBars;

  const HealthPanel({super.key, required this.data, required this.classBars});

  @override
  Widget build(BuildContext context) {
    if (data.eligibleScans == 0) {
      return const AnalyticsEmptyState(
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
                status: data.uncertainScans > 0 ? StatCardStatus.warning : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'Blocked',
                value: '${data.blockedScans}',
                icon: const Icon(Icons.block_outlined),
                status: data.blockedScans > 0 ? StatCardStatus.warning : null,
              ),
            ),
          ],
        ),
        if (classBars.isNotEmpty) ...[
          const SizedBox(height: 16),
          HealthBarChart(bars: classBars),
        ],
      ],
    );
  }
}
