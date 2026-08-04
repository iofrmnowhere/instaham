import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class AppNavItem {
  final String href;
  final String label;
  final IconData icon;

  const AppNavItem({
    required this.href,
    required this.label,
    required this.icon,
  });
}

class AppBottomNav extends StatelessWidget {
  final String? currentPath;

  const AppBottomNav({
    super.key,
    this.currentPath,
  });

  static const items = [
    AppNavItem(href: '/', label: 'Home', icon: Icons.home_outlined),
    AppNavItem(href: '/measurements', label: 'Measurements', icon: Icons.straighten),
    AppNavItem(href: '/analytics', label: 'Analytics', icon: Icons.bar_chart),
    AppNavItem(href: '/health', label: 'Health', icon: Icons.favorite_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final location = currentPath ?? GoRouterState.of(context).uri.path;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1.0),
        ),
      ),
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((item) {
          final isActive = location == item.href;
          final color = isActive ? AppColors.signalPink : AppColors.mutedForeground;

          return Expanded(
            child: InkWell(
              onTap: () {
                if (!isActive) {
                  context.go(item.href);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(item.icon, size: 22, color: color),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: AppTextStyles.label.copyWith(
                      fontSize: 11,
                      color: color,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (isActive)
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.signalPink,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 4),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
