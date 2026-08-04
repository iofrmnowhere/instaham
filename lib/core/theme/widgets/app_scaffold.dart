import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../../router/widgets/app_bottom_nav.dart';

class AppScaffold extends StatelessWidget {
  final Widget child;
  final Widget? header;
  final bool showNav;
  final String? currentPath;

  const AppScaffold({
    super.key,
    required this.child,
    this.header,
    this.showNav = true,
    this.currentPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            if (header case final h?) h,
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: showNav ? AppBottomNav(currentPath: currentPath) : null,
    );
  }
}
