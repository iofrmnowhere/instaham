import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class AppNavItem {
  final String href;
  final String label;
  final IconData icon;
  final bool primary;

  const AppNavItem({
    required this.href,
    required this.label,
    required this.icon,
    this.primary = false,
  });
}

class AppBottomNav extends StatelessWidget {
  final String? currentPath;

  const AppBottomNav({super.key, this.currentPath});

  static const items = [
    AppNavItem(href: '/', label: 'Home', icon: Icons.home_outlined),
    AppNavItem(
      href: '/analytics',
      label: 'Analytics',
      icon: Icons.bar_chart_outlined,
    ),
    AppNavItem(
      href: '/capture',
      label: 'Scan',
      icon: Icons.camera_alt,
      primary: true,
    ),
    AppNavItem(
      href: '/records',
      label: 'Records',
      icon: Icons.inventory_2_outlined,
    ),
    AppNavItem(href: '/privacy', label: 'Privacy', icon: Icons.shield_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final location = currentPath ?? GoRouterState.of(context).uri.path;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: items.map((item) {
          final active = location == item.href;
          final color = active || item.primary
              ? AppColors.signalPink
              : AppColors.mutedForeground;
          return Expanded(
            child: InkWell(
              onTap: () => item.href == '/capture'
                  ? context.push(item.href)
                  : context.go(item.href),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: item.primary ? 38 : 28,
                    height: item.primary ? 38 : 28,
                    decoration: item.primary
                        ? const BoxDecoration(
                            color: AppColors.signalPink,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Icon(
                      item.icon,
                      size: item.primary ? 22 : 20,
                      color: item.primary ? Colors.white : color,
                    ),
                  ),
                  if (!item.primary) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: AppTextStyles.label.copyWith(
                        fontSize: 9,
                        color: color,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
