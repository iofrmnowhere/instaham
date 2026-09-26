import 'package:flutter/material.dart';

import '../../../../core/models/folder_summary.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_card.dart';

/// docs/plan-6.md (round 6, pig folders): one folder's card on the folders list screen.
/// Shows "—" for total/average when no pig in the folder has a weight yet, never an
/// invented `0`.
class FolderSummaryCard extends StatelessWidget {
  final FolderSummary summary;
  final VoidCallback? onTap;

  const FolderSummaryCard({super.key, required this.summary, this.onTap});

  static String _formatKg(double? kg) =>
      kg == null ? '—' : '${kg.toStringAsFixed(1)} kg';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.folder.name,
            style: AppTextStyles.label.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Stat(label: 'Total', value: _formatKg(summary.totalKg)),
              ),
              Expanded(
                child: _Stat(
                  label: 'Average',
                  value: _formatKg(summary.averageKg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${summary.weighedCount} of ${summary.pigCount} pigs weighed',
            style: AppTextStyles.subtext.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.subtext.copyWith(
            color: AppColors.mutedForeground,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
