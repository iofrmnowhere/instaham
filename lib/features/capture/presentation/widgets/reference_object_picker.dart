import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_scope.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../data/custom_references_dao.dart';
import 'reference_object_details.dart';

class ReferenceObjectPicker extends StatefulWidget {
  final ValueChanged<ReferenceSelection> onSelect;
  final VoidCallback onBack;

  const ReferenceObjectPicker({
    super.key,
    required this.onSelect,
    required this.onBack,
  });

  static Future<ReferenceSelection?> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet<ReferenceSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (pageContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(pageContext).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(pageContext).height * 0.70,
          child: ReferenceObjectPicker(
            onSelect: (selection) => Navigator.pop(pageContext, selection),
            onBack: () => Navigator.pop(pageContext),
          ),
        ),
      ),
    );
  }

  @override
  State<ReferenceObjectPicker> createState() => _ReferenceObjectPickerState();
}

class _ReferenceObjectPickerState extends State<ReferenceObjectPicker> {
  bool _isAdding = false;
  CustomReferencesDao? _dao;

  static const presets = [
    ReferenceSelection.meterStick,
    ReferenceSelection.poracStick,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final database = DatabaseScope.of(context);
    _dao = CustomReferencesDao(database);
  }

  Future<void> _handleSaveCustom(ReferenceSelection selection) async {
    if (_dao == null) return;
    await _dao!.addCustomReference(
      CustomReferencesCompanion.insert(
        id: AppDatabase.newLocalId('ref'),
        name: selection.name,
        lengthCm: selection.lengthCm,
      ),
    );
    widget.onSelect(selection);
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdding) {
      return ReferenceObjectDetails(
        onConfirm: _handleSaveCustom,
        onBack: () => setState(() => _isAdding = false),
      );
    }

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
        child: SingleChildScrollView(
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
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.close),
                  ),
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
                    onTap: () => widget.onSelect(preset),
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
              FutureBuilder<List<CustomReference>>(
                future: _dao?.getAllCustomReferences(),
                builder: (context, snapshot) {
                  final customRefs = snapshot.data ?? [];
                  return Column(
                    children: customRefs.map((ref) {
                      final selection = ReferenceSelection(
                        type: 'custom',
                        name: ref.name,
                        lengthCm: ref.lengthCm,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          onTap: () => widget.onSelect(selection),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.pinkTint,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
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
                                      ref.name,
                                      style: AppTextStyles.label.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${ref.lengthCm.toStringAsFixed(1)} cm custom reference',
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
                      );
                    }).toList(),
                  );
                },
              ),
              AppCard(
                onTap: () => setState(() => _isAdding = true),
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
                            'Add reference object',
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
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.signalPink,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
