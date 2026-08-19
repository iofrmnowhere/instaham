import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/utils/length_units.dart';
import 'unit_toggle.dart';

class HeightModeSettings extends StatefulWidget {
  final double value;
  final LengthUnit unit;
  final ValueChanged<double> onChange;
  final ValueChanged<LengthUnit> onUnitChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const HeightModeSettings({
    super.key,
    required this.value,
    this.unit = LengthUnit.cm,
    required this.onChange,
    required this.onUnitChanged,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<HeightModeSettings> createState() => _HeightModeSettingsState();
}

class _HeightModeSettingsState extends State<HeightModeSettings> {
  late TextEditingController _controller;
  late LengthUnit _currentUnit;

  @override
  void initState() {
    super.initState();
    _currentUnit = widget.unit;
    _controller = TextEditingController(
      text: widget.value > 0 ? _currentUnit.format(widget.value) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _switchUnit(LengthUnit newUnit) {
    if (_currentUnit == newUnit) return;
    final currentText = _controller.text.trim();
    if (currentText.isNotEmpty) {
      final parsed = double.tryParse(currentText);
      if (parsed != null && parsed > 0) {
        final cm = _currentUnit.toCm(parsed);
        _controller.text = newUnit.format(cm);
      }
    }
    setState(() {
      _currentUnit = newUnit;
    });
    widget.onUnitChanged(newUnit);
  }

  void _handleConfirm() {
    final parsed = double.tryParse(_controller.text.trim()) ?? 0.0;
    final cm = _currentUnit.toCm(parsed);
    widget.onChange(cm);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.x2l),
        ),
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
                onPressed: widget.onBack,
              ),
              Text(
                'Camera Height',
                style: AppTextStyles.headline.copyWith(fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppCard(
            backgroundColor: AppColors.muted.withValues(alpha: 0.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Height (${_currentUnit.label})',
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    UnitToggle(selected: _currentUnit, onChanged: _switchUnit),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppTextStyles.numeric.copyWith(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: '0',
                    fillColor: Colors.white,
                    filled: true,
                    suffixText: _currentUnit.label,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Position camera at this height above the pig for accurate measurement',
                  style: AppTextStyles.subtext.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.signalPink,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
