// Service for running YOLO11s-seg (LDConv/ACmix) detection at 640x640 with letterboxing,
// then constructing the pig mask in original-image coordinates.
//
// ML_implementation_plan.md revision 7: `instaham_ml_segment_json` now decodes the 32 mask
// coefficients against the 160x160 prototype and unletterboxes the result (stages 1+2,
// section 4.2), so this service carries the mask's bounding box and pixel area rather than
// detection-only fields. It still does not carry the mask's pixel data itself -- the
// section-9 envelope (`instaham_ml_run_pipeline_json`) is what a caller wanting the actual
// pixels should use; this per-capability entrypoint stays for isolated debugging and
// screens that only need to know whether a pig was found (section 4.3 of the plan).
import 'ml_runtime.dart';

abstract interface class ISegmentationService {
  Future<void> loadModel();
  Future<SegmentationResult> segment(String imagePath);
}

class SegmentationResult {
  final int pigCount;
  final double confidence;
  final bool maskAvailable;
  final int maskAreaPx;
  final int bboxX;
  final int bboxY;
  final int bboxW;
  final int bboxH;
  final String? maskProtocol;

  const SegmentationResult({
    required this.pigCount,
    required this.confidence,
    required this.maskAvailable,
    this.maskAreaPx = 0,
    this.bboxX = 0,
    this.bboxY = 0,
    this.bboxW = 0,
    this.bboxH = 0,
    this.maskProtocol,
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
    final bbox = json['bbox'] as List<dynamic>?;
    return SegmentationResult(
      pigCount: (json['pig_count'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      maskAvailable: json['mask_available'] as bool? ?? false,
      maskAreaPx: (json['mask_area_px'] as num?)?.toInt() ?? 0,
      bboxX: bbox != null && bbox.isNotEmpty ? (bbox[0] as num).toInt() : 0,
      bboxY: bbox != null && bbox.length > 1 ? (bbox[1] as num).toInt() : 0,
      bboxW: bbox != null && bbox.length > 2 ? (bbox[2] as num).toInt() : 0,
      bboxH: bbox != null && bbox.length > 3 ? (bbox[3] as num).toInt() : 0,
      maskProtocol: json['mask_protocol'] as String?,
    );
  }
}
