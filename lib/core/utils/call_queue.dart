/// Runs tasks strictly one at a time, in the order [run] was called, regardless of how
/// long each task takes to complete.
///
/// plan-phase-2/1-isolate-offload.md: [MlRuntime] uses this to serialize calls into the
/// one native `InstahamMlContext`. Nothing in this app has ever exercised two concurrent
/// calls into that context, and this queue keeps it that way rather than relying on
/// `Ort::Session::Run`'s documented thread-safety and an unmutated-after-create struct as
/// the only guardrail. Extracted as its own top-level (rather than private-to-ml_runtime)
/// class so it can be unit-tested directly, since `ml_runtime.dart` itself cannot be
/// exercised host-side (it stages assets via `rootBundle`/`path_provider` and calls into
/// the native library).
class CallQueue {
  Future<void> _tail = Future.value();

  /// Queues [task] behind every previously queued task. The returned future completes
  /// with [task]'s own result (or error) once it runs; a failure in an earlier task never
  /// propagates to a later one, and never stops the queue from draining.
  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    // Swallow the task's own error here so a failed call doesn't wedge the queue for
    // every call queued after it; the real error still reaches this call's caller via
    // the returned `result` future.
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
