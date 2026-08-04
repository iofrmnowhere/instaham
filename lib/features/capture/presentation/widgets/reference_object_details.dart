import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';

class ReferenceObjectDetails extends StatefulWidget {
  final VoidCallback onConfirm;
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
  bool imageUploaded = false;
  final TextEditingController lengthController = TextEditingController();
  final TextEditingController widthController = TextEditingController();

  bool get isValid =>
      imageUploaded && lengthController.text.isNotEmpty && widthController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.x2l)),
        ),
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
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
                    'Reference Characteristics',
                    style: AppTextStyles.headline.copyWith(fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Image Upload section
              Text('Reference Photo', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (!imageUploaded)
                AppCard(
                  onTap: () => setState(() => imageUploaded = true),
                  border: Border.all(color: AppColors.border, width: 2),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(Icons.upload_file, size: 32, color: AppColors.mutedForeground),
                          const SizedBox(height: 8),
                          Text('Upload Image', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            'Tap to select or drag image here',
                            style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                AppCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('reference-object.jpg', style: AppTextStyles.body),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => imageUploaded = false),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Dimensions Inputs
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Length (cm)', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: lengthController,
                          keyboardType: TextInputType.number,
                          style: AppTextStyles.numeric.copyWith(fontSize: 16),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: '0',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Width (cm)', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: widthController,
                          keyboardType: TextInputType.number,
                          style: AppTextStyles.numeric.copyWith(fontSize: 16),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: '0',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'Provide accurate measurements for reliable pig analysis',
                  style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onBack,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isValid ? widget.onConfirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.signalPink,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                      ),
                      child: const Text('Confirm'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
