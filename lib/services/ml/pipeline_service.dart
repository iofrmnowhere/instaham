// Thin wrapper over MlRuntime.runPipeline -- the whole-graph native call
// (instaham_ml_run_pipeline_json, pipeline.cpp), added for TASKS.md's P0 fix: replaces the
// up-to-three per-capability calls (view/health/segmentation/weight) each independently
// re-segmenting from the image path with one native pass that constructs the pig mask once
// and reuses it for both the health and weight branches.
//
// The per-capability services (health_model_service.dart, segmentation_service.dart,
// weight_model_service.dart) are kept as-is -- they remain the isolated-debugging path for
// screens or tools that only need one signal. This service exists only for
// RunAndPersistPipelineUseCase's full-scan path.
import 'ml_runtime.dart';

export 'ml_runtime.dart' show MlStatus;

abstract interface class IPipelineService {
  Future<void> loadModel();

  /// Returns the raw decoded section-9 envelope alongside the call's native status.
  /// Callers must branch on the envelope's own per-stage `status` fields, not just this
  /// status -- `instaham_ml_run_pipeline_json` returns OK for a stage-level failure that
  /// is reported inside the envelope (AGENTS.md rule 4), and returns the STOPPED shape
  /// (only `status`/`reason`/`view` keys) for a rejected photo.
  ///
  /// TASKS.md W3: `cmPerPixel` is the user-confirmed reference object's measured cm/pixel
  /// for this scan -- pass it only when the caller has already verified the annotation is
  /// user-confirmed and coplanar-confirmed (AGENTS.md rule 7). Omitted, the weight branch
  /// degrades exactly as it did before this feature existed.
  Future<(MlStatus, Map<String, dynamic>)> run(
    String imagePath, {
    double? cmPerPixel,
  });
}

class PipelineServiceImpl implements IPipelineService {
  const PipelineServiceImpl();

  @override
  Future<void> loadModel() async {
    await MlRuntime.instance();
  }

  @override
  Future<(MlStatus, Map<String, dynamic>)> run(
    String imagePath, {
    double? cmPerPixel,
  }) async {
    final runtime = await MlRuntime.instance();
    return runtime.runPipeline(imagePath, cmPerPixel: cmPerPixel);
  }
}
