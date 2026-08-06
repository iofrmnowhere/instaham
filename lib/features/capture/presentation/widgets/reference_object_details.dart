import 'package:flutter/material.dart';

import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';

class ReferenceObjectDetails extends StatefulWidget {
  final ValueChanged<ReferenceSelection> onConfirm;
  final VoidCallback onBack;

  const ReferenceObjectDetails({
    super.key,
    required this.onConfirm,
    required this.onBack,
  });

  @override
  State<ReferenceObjectDetails> createState() => _ReferenceObjectDetailsState();
}

class _ReferenceObjectDetailsState extends State<ReferenceObjectDetails> {
  final _nameController = TextEditingController();
  final _lengthController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  void _submit() {
    final length = double.tryParse(_lengthController.text.trim());
    if (length == null || !length.isFinite || length <= 0) {
      setState(() => _error = 'Enter a positive measured length.');
      return;
    }
    widget.onConfirm(
      ReferenceSelection(
        type: 'custom',
        name: _nameController.text.trim().isEmpty
            ? 'Custom reference'
            : _nameController.text.trim(),
        lengthCm: length,
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
            Text(
              'Known length',
              style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
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
                suffixText: 'cm',
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
              child: const Text('Use this reference'),
            ),
          ],
        ),
      ),
    );
  }
}
