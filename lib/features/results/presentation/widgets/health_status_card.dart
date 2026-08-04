import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/status_badge.dart';

class HealthStatusCard extends StatelessWidget {
  final String label;
  final dynamic value;
  final String? unit;
  final ResultStatus status;
  final String? subtext;

  const HealthStatusCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    required this.status,
    this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value.toString(),
                        style: AppTextStyles.numeric.copyWith(
                          fontSize: 30,
                          color: AppColors.foreground,
                        ),
                      ),
                      if (unit != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          unit!,
                          style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              StatusBadge(status: status),
            ],
          ),
          if (subtext != null) ...[
            const SizedBox(height: 8),
            Text(
              subtext!,
              style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}
