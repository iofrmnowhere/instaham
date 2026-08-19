import 'package:flutter/material.dart';

import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/length_units.dart';
import 'unit_toggle.dart';

class ReferenceObjectDetails extends StatefulWidget {
  final LengthUnit unit;
  final ValueChanged<LengthUnit> onUnitChanged;
  final ValueChanged<ReferenceSelection> onConfirm;
  final VoidCallback onBack;

  const ReferenceObjectDetails({
    super.key,
    this.unit = LengthUnit.cm,
    required this.onUnitChanged,
    required this.onConfirm,
    required this.onBack,
  });

  @override
  State<ReferenceObjectDetails> createState() => _ReferenceObjectDetailsState();
}

class _ReferenceObjectDetailsState extends State<ReferenceObjectDetails> {
  final _nameController = TextEditingController();
  final _lengthController = TextEditingController();
  late LengthUnit _currentUnit;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUnit = widget.unit;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  void _switchUnit(LengthUnit newUnit) {
    if (_currentUnit == newUnit) return;
    final currentText = _lengthController.text.trim();
    if (currentText.isNotEmpty) {
      final parsed = double.tryParse(currentText);
      if (parsed != null && parsed > 0) {
        final cm = _currentUnit.toCm(parsed);
        _lengthController.text = newUnit.format(cm);
      }
    }
    setState(() {
      _currentUnit = newUnit;
    });
    widget.onUnitChanged(newUnit);
  }

  void _submit() {
    final length = double.tryParse(_lengthController.text.trim());
    if (length == null || !length.isFinite || length <= 0) {
      setState(() => _error = 'Enter a positive measured length.');
      return;
    }
    final lengthCm = _currentUnit.toCm(length);
    widget.onConfirm(
      ReferenceSelection(
        type: 'custom',
        name: _nameController.text.trim().isEmpty
            ? 'Custom reference'
            : _nameController.text.trim(),
        lengthCm: lengthCm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  'Custom reference',
                  style: AppTextStyles.headline.copyWith(fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Name (optional)',
              style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Example: marked PVC pipe',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Known length',
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                UnitToggle(selected: _currentUnit, onChanged: _switchUnit),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _lengthController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '0.0',
                suffixText: _currentUnit.label,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'The app uses this real-world length and the two endpoints you confirm after capture. Width and a separate object photo are not required.',
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Save and Use this reference'),
            ),
          ],
        ),
      ),
    );
  }
}
