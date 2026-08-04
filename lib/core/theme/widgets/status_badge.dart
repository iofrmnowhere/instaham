import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_text_styles.dart';
import '../app_theme.dart';

class StatusBadge extends StatelessWidget {
  final ResultStatus status;

  const StatusBadge({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case ResultStatus.success:
        backgroundColor = AppColors.success.withOpacity(0.15);
        textColor = AppColors.success;
        text = 'Confirmed';
        break;
      case ResultStatus.uncertain:
        backgroundColor = AppColors.uncertain.withOpacity(0.15);
        textColor = AppColors.uncertain;
        text = 'Uncertain';
        break;
      case ResultStatus.blocked:
        backgroundColor = AppColors.blocked.withOpacity(0.15);
        textColor = AppColors.blocked;
        text = 'Blocked';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: AppTextStyles.label.copyWith(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
