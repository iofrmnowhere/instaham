// Service for running YOLO11s-seg (LDConv/ACmix) detection at 640x640 with letterboxing.
//
// This pass exposes detection only (pig_count / confidence / mask_available) — the native
// layer does not yet decode the 32 mask coefficients against the 160x160 prototype into a
// pixel mask or map it back to original-image coordinates. That unletterbox + mask-decode
// work is the geometry port deferred to the section-3.5 decision point
// (ML_implementation_plan.md); `available` in the manifest also rests on a numeric
// torch-vs-ORT self-check rather than the formal gate-B fixture suite, which does not exist
// in the repo yet (section 11.3.1).
import 'ml_runtime.dart';

abstract interface class ISegmentationService {
  Future<void> loadModel();
  Future<SegmentationResult> segment(String imagePath);
}

class SegmentationResult {
  final int pigCount;
  final double confidence;
  final bool maskAvailable;
  // TODO: Add mask data (pixel map or polygon) once the geometry port lands.

  const SegmentationResult({
    required this.pigCount,
    required this.confidence,
    required this.maskAvailable,
  });
}

/// Real implementation: delegates to the native ORT session via [MlRuntime]. Returns a
/// zero-pig, unavailable-mask result (never a fabricated detection) if the manifest marks
/// segmentation unavailable or inference itself fails (AGENTS.md rule 8).
class SegmentationServiceImpl implements ISegmentationService {
  const SegmentationServiceImpl();

  @override
  Future<void> loadModel() async {
    await MlRuntime.instance();
  }

  @override
  Future<SegmentationResult> segment(String imagePath) async {
    final runtime = await MlRuntime.instance();
    final (status, json) = runtime.segment(imagePath);
    if (status != MlStatus.ok) {
      return const SegmentationResult(
        pigCount: 0,
        confidence: 0.0,
        maskAvailable: false,
      );
    }
    return SegmentationResult(
      pigCount: (json['pig_count'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      maskAvailable: json['mask_available'] as bool? ?? false,
    );
  }
}
