import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../widgets/height_mode_alignment.dart';
import '../widgets/height_mode_settings.dart';
import '../widgets/reference_object_details.dart';
import '../widgets/reference_object_picker.dart';

enum CaptureModeState { camera, heightSettings, heightAlignment, refPicker, refDetails }

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CaptureModeState mode = CaptureModeState.camera;
  double heightValue = 0.0;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showNav: false,
      child: Stack(
        children: [
          if (mode == CaptureModeState.camera)
            _CameraView(
              onHeightMode: () => setState(() => mode = CaptureModeState.heightSettings),
              onReferenceMode: () => setState(() => mode = CaptureModeState.refPicker),
            ),
          if (mode == CaptureModeState.heightSettings)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: HeightModeSettings(
                  value: heightValue,
                  onChange: (val) => setState(() => heightValue = val),
                  onNext: () => setState(() => mode = CaptureModeState.heightAlignment),
                  onBack: () => setState(() => mode = CaptureModeState.camera),
                ),
              ),
            ),
          if (mode == CaptureModeState.heightAlignment)
            Positioned.fill(
              child: HeightModeAlignment(
                onConfirm: () => context.push('/reference-marking'),
                onBack: () => setState(() => mode = CaptureModeState.heightSettings),
              ),
            ),
          if (mode == CaptureModeState.refPicker)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ReferenceObjectPicker(
                  onSelect: (type) {
                    if (type == 'custom') {
                      setState(() => mode = CaptureModeState.refDetails);
                    } else {
                      context.push('/reference-marking');
                    }
                  },
                  onBack: () => setState(() => mode = CaptureModeState.camera),
                ),
              ),
            ),
          if (mode == CaptureModeState.refDetails)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ReferenceObjectDetails(
                  onConfirm: () => context.push('/reference-marking'),
                  onBack: () => setState(() => mode = CaptureModeState.refPicker),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraView extends StatelessWidget {
  final VoidCallback onHeightMode;
  final VoidCallback onReferenceMode;

  const _CameraView({
    required this.onHeightMode,
    required this.onReferenceMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Camera Preview',
                      style: AppTextStyles.subtext.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
                // Crosshair overlay box
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ],
            ),
          ),

          // Control Bar
          Container(
            color: Colors.white.withValues(alpha: 0.05),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onHeightMode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.signalPink,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        ),
                        child: const Text('Height Mode'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReferenceMode,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        ),
                        child: const Text('Reference Mode'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                  label: Text(
                    'Reset',
                    style: AppTextStyles.label.copyWith(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
