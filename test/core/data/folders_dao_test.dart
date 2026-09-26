import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/data/folders_dao.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/scan_flow.dart';

void main() {
  late AppDatabase database;
  late FoldersDao dao;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dao = database.foldersDao;
  });

  tearDown(() => database.close());

  Future<String> createPig(
    AppDatabase db, {
    String? tag,
    String? displayName,
  }) async {
    final id = AppDatabase.newLocalId('pig');
    await db
        .into(db.pigs)
        .insert(
          PigsCompanion.insert(
            id: id,
            tag: Value(tag),
            displayName: Value(displayName),
          ),
        );
    return id;
  }

  Future<String> createWeighedScan(
    AppDatabase db, {
    required String pigId,
    required double valueKg,
  }) async {
    final scanId = await db.createDraftScan(
      goal: ScanGoal.weightAndHealth,
      pigId: pigId,
    );
    await db.markCaptured(scanId, imagePath: 'scan.jpg');
    await db.saveWeightResult(scanId: scanId, eligible: true, valueKg: valueKg);
    return scanId;
  }

  test('createFolder then renameFolder: watchFolders reflects both', () async {
    final id = await dao.createFolder('Nursery');
    var folders = await dao.watchFolders().first;
    expect(folders, hasLength(1));
    expect(folders.single.folder.id, id);
    expect(folders.single.folder.name, 'Nursery');
    expect(folders.single.pigCount, 0);
    expect(folders.single.totalKg, isNull);
    expect(folders.single.averageKg, isNull);

    await dao.renameFolder(id, ' Nursery A ');
    folders = await dao.watchFolders().first;
    expect(folders.single.folder.name, 'Nursery A');
  });

  test(
    'setPigFolder adds a pig to a folder and removes it from ungrouped',
    () async {
      final folderId = await dao.createFolder('Grower Pen');
      final pigId = await createPig(database, tag: 'TAG-1');

      var ungrouped = await dao.watchUngroupedPigs().first;
      expect(ungrouped.map((p) => p.id), contains(pigId));

      await dao.setPigFolder(pigId, folderId);

      ungrouped = await dao.watchUngroupedPigs().first;
      expect(ungrouped.map((p) => p.id), isNot(contains(pigId)));

      final folderPigs = await dao.watchFolderPigs(folderId).first;
      expect(folderPigs.map((fp) => fp.pig.id), contains(pigId));

      final folders = await dao.watchFolders().first;
      expect(folders.single.pigCount, 1);
      expect(folders.single.weighedCount, 0);
    },
  );

  test('setPigFolder(pigId, null) removes a pig from its folder', () async {
    final folderId = await dao.createFolder('Grower Pen');
    final pigId = await createPig(database, tag: 'TAG-1');
    await dao.setPigFolder(pigId, folderId);

    await dao.setPigFolder(pigId, null);

    final folderPigs = await dao.watchFolderPigs(folderId).first;
    expect(folderPigs, isEmpty);
    final ungrouped = await dao.watchUngroupedPigs().first;
    expect(ungrouped.map((p) => p.id), contains(pigId));
  });

  test(
    'a pig is in at most one folder: moving it to a new folder takes it out of the old one',
    () async {
      final folderA = await dao.createFolder('Folder A');
      final folderB = await dao.createFolder('Folder B');
      final pigId = await createPig(database, tag: 'TAG-1');

      await dao.setPigFolder(pigId, folderA);
      await dao.setPigFolder(pigId, folderB);

      final pigsInA = await dao.watchFolderPigs(folderA).first;
      final pigsInB = await dao.watchFolderPigs(folderB).first;
      expect(pigsInA, isEmpty);
      expect(pigsInB.map((fp) => fp.pig.id), contains(pigId));
    },
  );

  test(
    'watchFolders totals only the weighed pigs; unweighed pigs count but are excluded',
    () async {
      final folderId = await dao.createFolder('Finishing Pen');
      final weighedPig = await createPig(database, tag: 'TAG-1');
      final unweighedPig = await createPig(database, tag: 'TAG-2');
      await dao.setPigFolder(weighedPig, folderId);
      await dao.setPigFolder(unweighedPig, folderId);
      await createWeighedScan(database, pigId: weighedPig, valueKg: 80.0);

      final folders = await dao.watchFolders().first;
      final summary = folders.single;
      expect(summary.pigCount, 2);
      expect(summary.weighedCount, 1);
      expect(summary.totalKg, 80.0);
      expect(summary.averageKg, 80.0);
    },
  );

  test(
    'deleteFolder without records: the folder goes, its pigs are ungrouped and keep '
    'their scans',
    () async {
      final folderId = await dao.createFolder('Sold Batch');
      final pigId = await createPig(database, tag: 'TAG-1');
      await dao.setPigFolder(pigId, folderId);
      final scanId = await createWeighedScan(
        database,
        pigId: pigId,
        valueKg: 90.0,
      );

      await dao.deleteFolder(folderId, includeRecords: false);

      final folders = await dao.watchFolders().first;
      expect(folders, isEmpty);

      final pig = await (database.select(
        database.pigs,
      )..where((p) => p.id.equals(pigId))).getSingleOrNull();
      expect(pig, isNotNull);
      expect(pig!.folderId, isNull);

      final scan = await (database.select(
        database.scanRecords,
      )..where((s) => s.id.equals(scanId))).getSingleOrNull();
      expect(scan, isNotNull);
    },
  );

  test(
    'deleteFolder with records: the folder, its pigs, and their scans/results are '
    "deleted -- other folders' pigs and ungrouped scans stay",
    () async {
      final targetFolder = await dao.createFolder('Cull Batch');
      final otherFolder = await dao.createFolder('Keep Batch');
      final targetPig = await createPig(database, tag: 'TAG-1');
      final otherPig = await createPig(database, tag: 'TAG-2');
      final ungroupedPig = await createPig(database, tag: 'TAG-3');
      await dao.setPigFolder(targetPig, targetFolder);
      await dao.setPigFolder(otherPig, otherFolder);

      final targetScan = await createWeighedScan(
        database,
        pigId: targetPig,
        valueKg: 70.0,
      );
      final otherScan = await createWeighedScan(
        database,
        pigId: otherPig,
        valueKg: 60.0,
      );
      final ungroupedScan = await createWeighedScan(
        database,
        pigId: ungroupedPig,
        valueKg: 50.0,
      );

      await dao.deleteFolder(targetFolder, includeRecords: true);

      final folders = await dao.watchFolders().first;
      expect(folders.map((f) => f.folder.id), [otherFolder]);

      expect(
        await (database.select(
          database.pigs,
        )..where((p) => p.id.equals(targetPig))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (database.select(
          database.scanRecords,
        )..where((s) => s.id.equals(targetScan))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (database.select(
          database.weightResults,
        )..where((w) => w.scanId.equals(targetScan))).getSingleOrNull(),
        isNull,
      );

      // Other folder's pig and its scan survive untouched.
      expect(
        await (database.select(
          database.pigs,
        )..where((p) => p.id.equals(otherPig))).getSingleOrNull(),
        isNotNull,
      );
      expect(
        await (database.select(
          database.scanRecords,
        )..where((s) => s.id.equals(otherScan))).getSingleOrNull(),
        isNotNull,
      );

      // An ungrouped pig's scan survives untouched too.
      expect(
        await (database.select(
          database.pigs,
        )..where((p) => p.id.equals(ungroupedPig))).getSingleOrNull(),
        isNotNull,
      );
      expect(
        await (database.select(
          database.scanRecords,
        )..where((s) => s.id.equals(ungroupedScan))).getSingleOrNull(),
        isNotNull,
      );
    },
  );
}
