// docs/plan-phase-2/3-validation-docs.md phase 3: proves CallQueue -- the lock ml_runtime.dart
// serializes native calls through (plan-phase-2/1-isolate-offload.md) -- actually runs tasks
// strictly in enqueue order even when an earlier task finishes after a later one starts, and
// that a failed task never wedges the queue for the tasks behind it.
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/utils/call_queue.dart';

void main() {
  group('CallQueue', () {
    test('two overlapping calls complete strictly in enqueue order', () async {
      final queue = CallQueue();
      final completionOrder = <int>[];

      // Task 1 is slower than task 2, so without serialization task 2 would finish first.
      final first = queue.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        completionOrder.add(1);
        return 1;
      });
      final second = queue.run(() async {
        completionOrder.add(2);
        return 2;
      });

      final results = await Future.wait([first, second]);
      expect(results, [1, 2]);
      expect(completionOrder, [1, 2]);
    });

    test('a failed task does not wedge tasks queued behind it', () async {
      final queue = CallQueue();

      final failing = queue.run(() async {
        throw StateError('native call failed');
      });
      final after = queue.run(() async => 'still runs');

      await expectLater(failing, throwsA(isA<StateError>()));
      expect(await after, 'still runs');
    });

    test('the failing task\'s own error reaches its own caller', () async {
      final queue = CallQueue();
      await expectLater(
        queue.run(() async => throw ArgumentError('boom')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
