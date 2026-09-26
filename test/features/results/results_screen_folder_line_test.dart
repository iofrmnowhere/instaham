// docs/plan-6.md (round 6, pig folders) step 5: the results screen's pig card Folder line
// and picker.
import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/data/repositories/drift_folders_repository.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/database/database_scope.dart';
import 'package:instaham/core/domain/repositories/i_folders_repository.dart';
import 'package:instaham/core/models/folder_pig.dart';
import 'package:instaham/core/models/folder_summary.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/core/widgets/folders_scope.dart';
import 'package:instaham/features/results/presentation/screens/results_screen.dart';

/// A pure in-memory stand-in for [IFoldersRepository], used only by the "New folder"
/// test below. Driving that flow against the real Drift-backed repository deadlocks
/// flutter_test's own end-of-test teardown -- reproducible, but specific to mixing
/// NativeDatabase's real (FFI-backed) I/O with FakeAsync across two nested dialogs, not a
/// bug in the widget under test. The DAO-level behavior of createFolder/setPigFolder is
/// already covered by folders_dao_test.dart, and the other tests in this file already
/// prove the Folder line reacts correctly to the real database.
class _FakeFoldersRepository implements IFoldersRepository {
  final List<PigFolder> _folders = [];
  final Map<String, String?> _pigFolderIds;
  final _changes = StreamController<void>.broadcast();
  int _idCounter = 0;

  _FakeFoldersRepository({Map<String, String?> pigFolderIds = const {}})
    : _pigFolderIds = Map.of(pigFolderIds);

  List<String> get folderNames => _folders.map((f) => f.name).toList();

  String? folderIdFor(String pigId) => _pigFolderIds[pigId];

  List<FolderSummary> _snapshotFolders() {
    return _folders
        .map(
          (f) => FolderSummary(
            folder: f,
            pigCount: _pigFolderIds.values.where((id) => id == f.id).length,
            weighedCount: 0,
            totalKg: null,
            averageKg: null,
          ),
        )
        .toList();
  }

  @override
  Stream<List<FolderSummary>> watchFolders() async* {
    yield _snapshotFolders();
    await for (final _ in _changes.stream) {
      yield _snapshotFolders();
    }
  }

  @override
  Stream<String?> watchPigFolderId(String pigId) async* {
    yield _pigFolderIds[pigId];
    await for (final _ in _changes.stream) {
      yield _pigFolderIds[pigId];
    }
  }

  @override
  Stream<List<FolderPig>> watchFolderPigs(String folderId) =>
      const Stream.empty();

  @override
  Stream<List<Pig>> watchUngroupedPigs() => const Stream.empty();

  @override
  Future<String> createFolder(String name) async {
    final id = 'fake-folder-${_idCounter++}';
    final now = DateTime.now();
    _folders.add(
      PigFolder(id: id, name: name.trim(), createdAt: now, updatedAt: now),
    );
    _changes.add(null);
    return id;
  }

  @override
  Future<void> renameFolder(String id, String name) async {}

  @override
  Future<void> setPigFolder(String pigId, String? folderId) async {
    _pigFolderIds[pigId] = folderId;
    _changes.add(null);
  }

  @override
  Future<void> deleteFolder(String id, {required bool includeRecords}) async {}
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpResults(WidgetTester tester, String scanId) async {
    // Same sizing workaround as results_screen_view_cards_removed_test.dart: the default
    // test surface plus cacheExtent is too short for the cards below the fold to build.
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The name dialog's autofocus TextField drives its blinking-cursor animation with its
    // own AnimationController (EditableText._cursorBlinkOpacityController), which never
    // lets pumpAndSettle's frame-scheduling loop go idle -- pumpAndSettle hangs until its
    // own 10-minute internal timeout (or hangs the framework's end-of-test teardown, if
    // that Ticker is still running when the test returns). This is EditableText's own
    // test hook for it.
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);

    await tester.pumpWidget(
      MaterialApp(
        home: DatabaseScope(
          database: database,
          child: FoldersScope(
            repository: DriftFoldersRepository(database.foldersDao),
            child: ResultsScreen(args: ScanFlowArgs(sessionId: scanId)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The Folder line's StreamBuilder subscribes to a live Drift query. Drift schedules a
  // zero-duration Timer when that subscription is cancelled (StreamQueryStore.markAsClosed),
  // and flutter_test's own end-of-test teardown disposes the widget tree (and so cancels the
  // subscription) too late for that timer to be flushed, tripping its "no pending timers"
  // invariant. Unmounting and pumping a real duration here, still inside the test body, lets
  // the timer fire before that check runs.
  Future<void> flushDriftStreamTimers(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  // docs/fix-8.md F74: createDraftScan now gives every scan its own auto-ID pig, so a
  // pigless scan can no longer arise through the app's own API. It stays possible only as
  // leftover pre-migration data, so this seeds one the same way the v7->v8 migration would
  // find it: a scan row with no pig, inserted directly rather than through
  // createDraftScan -- to prove the Folder line's defensive `bundle.pig == null` branch
  // still holds.
  Future<String> seedUnassignedScan() async {
    final id = AppDatabase.newLocalId('scan');
    final now = DateTime.now();
    await database
        .into(database.scanRecords)
        .insert(
          ScanRecordsCompanion.insert(
            id: id,
            goal: ScanGoal.weightAndHealth.storageValue,
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<String> seedAssignedScan({String displayName = 'PIG-1'}) async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    await database.renamePigForScan(scanId: scanId, displayName: displayName);
    return scanId;
  }

  testWidgets('no Folder line when the scan has no pig', (tester) async {
    final scanId = await seedUnassignedScan();

    await pumpResults(tester, scanId);

    expect(find.byIcon(Icons.folder_outlined), findsNothing);
    expect(find.text('Folder'), findsNothing);
  });

  testWidgets('shows "No folder" for a pig not in any folder', (tester) async {
    final scanId = await seedAssignedScan();

    await pumpResults(tester, scanId);

    expect(find.text('No folder'), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);

    await flushDriftStreamTimers(tester);
  });

  testWidgets('shows the pig\'s current folder', (tester) async {
    final scanId = await seedAssignedScan();
    final pig = await database.select(database.pigs).getSingle();
    await database.foldersDao
        .createFolder('Nursery')
        .then((folderId) => database.foldersDao.setPigFolder(pig.id, folderId));

    await pumpResults(tester, scanId);

    expect(find.text('Nursery'), findsOneWidget);
    expect(find.text('No folder'), findsNothing);

    await flushDriftStreamTimers(tester);
  });

  testWidgets('picking an existing folder moves the pig into it', (
    tester,
  ) async {
    final scanId = await seedAssignedScan();
    await database.foldersDao.createFolder('Nursery');

    await pumpResults(tester, scanId);
    expect(find.text('No folder'), findsOneWidget);

    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nursery'));
    await tester.pumpAndSettle();

    expect(find.text('Nursery'), findsOneWidget);
    expect(find.text('No folder'), findsNothing);

    await flushDriftStreamTimers(tester);
  });

  testWidgets('"New folder" creates a folder and assigns the pig', (
    tester,
  ) async {
    final scanId = await seedAssignedScan();
    final pig = await database.select(database.pigs).getSingle();
    final fakeRepo = _FakeFoldersRepository();

    // Same sizing workaround as pumpResults, with the fake repository swapped in for
    // FoldersScope (see _FakeFoldersRepository's doc comment).
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);

    await tester.pumpWidget(
      MaterialApp(
        home: DatabaseScope(
          database: database,
          child: FoldersScope(
            repository: fakeRepo,
            child: ResultsScreen(args: ScanFlowArgs(sessionId: scanId)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Finishing Pen');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Finishing Pen'), findsOneWidget);
    expect(fakeRepo.folderNames, ['Finishing Pen']);
    expect(fakeRepo.folderIdFor(pig.id), isNotNull);
  });
}
