import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

class CaptureGuidanceScreen extends StatelessWidget {
  const CaptureGuidanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const tips = [
      'Photograph one pig from directly above.',
      'Keep the complete head, body, and tail inside the frame.',
      'Place a known straight reference flat beside the pig (or set camera height).',
      'Keep both reference endpoints visible when using a reference object.',
      'Keep the phone parallel to the ground and avoid blur.',
    ];

    return AppScaffold(
      showNav: false,
      header: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.close),
            ),
            Text(
              'Capture tips',
              style: AppTextStyles.headline.copyWith(fontSize: 20),
            ),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before you capture',
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...tips.map(
                  (tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tip, style: AppTextStyles.body)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            backgroundColor: AppColors.pinkTint,
            border: Border.all(
              color: AppColors.signalPink.withValues(alpha: 0.3),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.signalPink),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Weight is available only after scale calibration and all eligibility checks pass.',
                    style: AppTextStyles.subtext,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () =>
                context.push('/capture', extra: const ScanFlowArgs()),
            child: const Text('Open camera'),
          ),
        ],
      ),
    );
  }
}
