import 'package:flutter/material.dart';

import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';

class ReferenceObjectPicker extends StatelessWidget {
  final ValueChanged<ReferenceSelection> onSelect;
  final VoidCallback onCustom;
  final VoidCallback onBack;

  const ReferenceObjectPicker({
    super.key,
    required this.onSelect,
    required this.onCustom,
    required this.onBack,
  });

  static Future<Object?> pushFullScreen(BuildContext context) {
    return Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: ReferenceObjectPicker(
              onSelect: (selection) => Navigator.pop(pageContext, selection),
              onCustom: () => Navigator.pop(pageContext, 'custom'),
              onBack: () => Navigator.pop(pageContext),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const presets = [
      ReferenceSelection.meterStick,
      ReferenceSelection.poracStick,
    ];

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.x2l),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(onPressed: onBack, icon: const Icon(Icons.close)),
                Expanded(
                  child: Text(
                    'Choose reference object',
                    style: AppTextStyles.headline.copyWith(fontSize: 18),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
              child: Text(
                'Use a straight object with a known length. Keep both endpoints visible beside the pig.',
                style: AppTextStyles.subtext.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
            ),
            ...presets.map(
              (preset) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () => onSelect(preset),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.pinkTint,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(
                          Icons.straighten,
                          color: AppColors.signalPink,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preset.name,
                              style: AppTextStyles.label.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${preset.lengthCm.toStringAsFixed(0)} cm known length',
                              style: AppTextStyles.subtext.copyWith(
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AppCard(
              onTap: onCustom,
              border: Border.all(color: AppColors.signalPink),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.pinkTint,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.add, color: AppColors.signalPink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom reference',
                          style: AppTextStyles.label.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Enter its measured straight length',
                          style: AppTextStyles.subtext.copyWith(
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.signalPink),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
