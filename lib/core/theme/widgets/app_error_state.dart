import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_text_styles.dart';

class AppErrorState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const AppErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.destructive, size: 48),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.headline),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.subtext,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
