import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';

class ReferenceObjectPicker extends StatelessWidget {
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;

  const ReferenceObjectPicker({
    super.key,
    required this.onSelect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [
      {'id': 'meter', 'name': '1-Meter Stick', 'description': 'Standard measurement reference'},
      {'id': 'porac', 'name': 'Porac Stick', 'description': 'Field standard reference'},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.x2l)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: onBack,
              ),
              Text(
                'Reference Object',
                style: AppTextStyles.headline.copyWith(fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...presets.map((preset) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: AppCard(
                onTap: () => onSelect(preset['id']!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset['name']!, style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      preset['description']!,
                      style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                    ),
                  ],
                ),
              ),
            );
          }),
          AppCard(
            onTap: () => onSelect('custom'),
            border: Border.all(color: AppColors.signalPink, width: 2),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.signalPink.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.add, color: AppColors.signalPink),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add Custom', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      'Upload your own reference',
                      style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
