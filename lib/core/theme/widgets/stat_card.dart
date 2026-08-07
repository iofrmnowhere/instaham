import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_text_styles.dart';
import '../app_theme.dart';
import 'app_card.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Widget? icon;
  final StatCardStatus? status;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isAlert =
        status == StatCardStatus.warning || status == StatCardStatus.error;

    final backgroundColor = isAlert ? AppColors.pinkTint : AppColors.card;
    final borderColor = isAlert ? const Color(0xFFFBCFE8) : AppColors.border;
    final iconColor = isAlert ? AppColors.signalPink : AppColors.foreground;

    return AppCard(
      backgroundColor: backgroundColor,
      border: Border.all(color: borderColor),
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            IconTheme(
              data: IconThemeData(color: iconColor, size: 20),
              child: icon!,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.subtext.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: AppTextStyles.numeric.copyWith(
                        fontSize: 24,
                        color: AppColors.foreground,
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        unit!,
                        style: AppTextStyles.subtext.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
