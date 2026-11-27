import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/local_cipher.dart';
import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/features/livestock/domain/animal_photos.dart';

import 'photo_test_fixtures.dart';

Future<void> seed(OfflineStore db) async {
  await db.save(photoSnapshot(), project: photoProject);
  for (final id in [firstPhoto, secondPhoto]) {
    await db.savePhotoMetadata(
      photoUser,
      photoOwner,
      photoProject,
      id,
      photoEntity(id),
    );
  }
}

Future<void> capture(OfflineStore db, Map<String, dynamic> operation) =>
    db.enqueuePhotoOperation(
      photoUser,
      photoOwner,
      photoProject,
      operation,
      expected: photoData(
        operation['entityId'] as String,
        primary: operation['entityId'] == firstPhoto,
      ),
      verify: () {},
    );

void main() {
  test('version-one cache migrates with encryption before the project column exists', () async {
    final db = OfflineStore(
      NativeDatabase.memory(
        setup: (sql) {
          sql.execute(
            'CREATE TABLE inventory_cache (user_id TEXT PRIMARY KEY,owner_id TEXT NOT NULL,saved_at INTEGER NOT NULL,payload TEXT NOT NULL)',
          );
          sql.execute('INSERT INTO inventory_cache VALUES(?,?,?,?)', [
            photoUser,
            photoOwner,
            DateTime.now().millisecondsSinceEpoch,
            jsonEncode({
              'ranchName': 'Legado',
              'role': 'owner',
              'records': photoSnapshot().records,
              'statusOptions': {},
              'statusLabels': {},
              'config': {},
              'configRevision': 0,
            }),
          ]);
          sql.userVersion = 1;
        },
      ),
      LocalCipher(Uint8List(32)),
    );
    addTearDown(db.close);
    expect((await db.read(photoUser))!.ranchName, 'Legado');
    expect(await db.read(photoUser, project: photoProject), isNull);
    await seed(db);
    expect(
      (await db.read(photoUser, project: photoProject))!.ownerId,
      photoOwner,
    );
    await capture(db, photoOperation());
    expect(
      await db.photoChanges(photoUser, photoOwner, photoProject),
      hasLength(1),
    );
  });

  test('legacy photo without an internal animal ID uses its validated parent and original raw metadata', () async {
    final db = OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    final snapshot = photoSnapshot();
    final photos = (snapshot.records.first['payload'] as Map)['photos'] as List;
    final legacy = Map<String, dynamic>.from(photos.first as Map)
      ..remove('animalId');
    photos[0] = legacy;
    await db.save(snapshot, project: photoProject);
    await db.savePhotoMetadata(
      photoUser,
      photoOwner,
      photoProject,
      firstPhoto,
      {'revision': 7, 'parentId': 'a', 'data': legacy},
    );
    await db.enqueuePhotoOperation(
      photoUser,
      photoOwner,
      photoProject,
      photoOperation(),
      expected: legacy,
      verify: () {},
    );
    final preview = projectPhotoChanges(
      (await db.read(photoUser))!,
      await db.photoChanges(photoUser, photoOwner, photoProject),
    );
    expect(AnimalPhoto.fromSnapshot(preview, 'a').first.crop.x, 82);
  });

  test('archived operation keeps project provenance and a restored conflict remains visible', () async {
    final db = OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final original = photoOperation(), id = original['operationId'] as String;
    await capture(db, original);
    await db.settleUniversal(photoUser, photoOwner, id, 'conflict', {
      'code': 'REVISION_MISMATCH',
    }, 0);
    await db.archiveUniversal(photoUser, photoOwner, id, true);
    await capture(db, photoOperation(id: 'new-pending'));
    expect(
      await db.photoOperationProject(photoUser, photoOwner, id),
      photoProject,
    );
    await db.archiveUniversal(photoUser, photoOwner, id, false);
    // A late acknowledgement cannot overwrite a terminal conflict or remove its badge.
    await db.settleUniversal(photoUser, photoOwner, id, 'confirmed', {
      'revision': 8,
    }, 0);
    expect(await db.confirmedPhotoOperations(photoUser, photoProject), isEmpty);
    await db.acknowledgePhotoSnapshot(photoUser, photoOwner, photoProject, [
      id,
    ]);
    final changes = await db.photoChanges(photoUser, photoOwner, photoProject);
    expect(changes, hasLength(2));
    expect(
      projectPhotoChanges(
        (await db.read(photoUser))!,
        changes,
      ).photoSyncStates['a'],
      'conflict',
    );
  });

  test('encrypted originals, revision and pending preview survive restart with exact bytes', () async {
    final directory = await Directory.systemTemp.createTemp('ganaderov-photo-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/photos.sqlite');
    final cipher = LocalCipher(Uint8List(32));
    var db = OfflineStore(NativeDatabase(file), cipher);
    await seed(db);
    final path = '$photoOwner/a/$firstPhoto';
    await db.savePhotoOriginal(
      photoUser,
      photoOwner,
      photoProject,
      path,
      photoPng(),
    );
    await capture(db, photoOperation());
    for (final table in [
      'photo_originals',
      'photo_metadata',
      'universal_outbox',
    ]) {
      final rows = await db.customSelect('SELECT payload FROM $table').get();
      expect(
        rows.every((row) => row.read<String>('payload').startsWith('gcm2:')),
        isTrue,
      );
      expect(
        rows.any((row) => row.read<String>('payload').contains('Original uno')),
        isFalse,
      );
    }
    await db.close();
    db = OfflineStore(NativeDatabase(file), cipher);
    addTearDown(db.close);
    final raw = (await db.read(photoUser))!;
    final preview = projectPhotoChanges(
      raw,
      await db.photoChanges(photoUser, photoOwner, photoProject),
    );
    expect(AnimalPhoto.fromSnapshot(preview, 'a').first.crop.x, 82);
    expect(preview.photoSyncStates, {'a': 'pending'});
    expect(AnimalPhoto.fromSnapshot(raw, 'a').first.crop.x, 50);
    expect(
      await db.readPhotoOriginal(photoUser, photoOwner, photoProject, path),
      photoPng(),
    );
    expect(
      await db.readPhotoOriginal('other', photoOwner, photoProject, path),
      isNull,
    );
    expect(
      await db.readPhotoOriginal(photoUser, photoOwner, 'other-project', path),
      isNull,
    );
    expect(
      await db.readPhotoMetadata(
        photoUser,
        'other-ranch',
        photoProject,
        firstPhoto,
      ),
      isNull,
    );
    expect(
      await db.photoChanges(photoUser, photoOwner, 'other-project'),
      isEmpty,
    );
  });

  test(
    'one durable operation per animal is atomic under concurrent capture',
    () async {
      final db = OfflineStore(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db);
      final results = await Future.wait([
        capture(
          db,
          photoOperation(),
        ).then<bool>((_) => true, onError: (Object _, StackTrace _) => false),
        capture(
          db,
          photoOperation(
            id: '40000000-0000-4000-8000-000000000002',
            action: 'photo.primary',
            photoId: secondPhoto,
          ),
        ).then<bool>((_) => true, onError: (Object _, StackTrace _) => false),
      ]);
      expect(results.where((success) => success), hasLength(1));
      expect(await db.universalPending(photoUser, photoOwner), hasLength(1));
      expect(
        await db.photoChanges(photoUser, photoOwner, photoProject),
        hasLength(1),
      );
    },
  );

  test(
    'unknown, mismatched and expired revisions never invent a base revision',
    () async {
      final db = OfflineStore(NativeDatabase.memory());
      addTearDown(db.close);
      await db.save(photoSnapshot(), project: photoProject);
      await expectLater(capture(db, photoOperation()), throwsStateError);
      await seed(db);
      await db.savePhotoMetadata(
        photoUser,
        photoOwner,
        photoProject,
        firstPhoto,
        {
          ...photoEntity(firstPhoto),
          'data': {...photoData(firstPhoto, primary: true), 'cropX': 12},
        },
      );
      await expectLater(capture(db, photoOperation()), throwsStateError);
      await seed(db);
      await db.customStatement('UPDATE photo_metadata SET saved_at=0');
      await expectLater(capture(db, photoOperation()), throwsStateError);
      expect(await db.universalPending(photoUser, photoOwner), isEmpty);
    },
  );

  test(
    'scope change while awaiting insertion rolls back operation and projection',
    () async {
      final db = OfflineStore(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db);
      var checks = 0;
      await expectLater(
        db.enqueuePhotoOperation(
          photoUser,
          photoOwner,
          photoProject,
          photoOperation(),
          expected: photoData(firstPhoto, primary: true),
          verify: () {
            checks++;
            if (checks == 3) throw StateError('session changed');
          },
        ),
        throwsStateError,
      );
      expect(await db.universalPending(photoUser, photoOwner), isEmpty);
      expect(
        await db.photoChanges(photoUser, photoOwner, photoProject),
        isEmpty,
      );
    },
  );

  test('acknowledgement stays visible until a later successful snapshot; conflict stays explicit', () async {
    final db = OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final op = photoOperation();
    await capture(db, op);
    await db.settleUniversal(
      photoUser,
      photoOwner,
      op['operationId'] as String,
      'confirmed',
      {'revision': 8},
      0,
    );
    await db.acknowledgePhotoSnapshot(photoUser, photoOwner, photoProject, []);
    expect(
      (await db.photoChanges(
        photoUser,
        photoOwner,
        photoProject,
      )).single['state'],
      'confirmed',
    );
    await expectLater(
      capture(db, photoOperation(id: 'new-operation')),
      throwsStateError,
    );
    await db.acknowledgePhotoSnapshot(
      photoUser,
      photoOwner,
      photoProject,
      await db.confirmedPhotoOperations(photoUser, photoProject),
    );
    expect(await db.photoChanges(photoUser, photoOwner, photoProject), isEmpty);
    final other = photoOperation(id: 'other-operation');
    await capture(db, other);
    await db.settleUniversal(
      photoUser,
      photoOwner,
      'other-operation',
      'conflict',
      {'code': 'REVISION_MISMATCH'},
      0,
    );
    final preview = projectPhotoChanges(
      (await db.read(photoUser))!,
      await db.photoChanges(photoUser, photoOwner, photoProject),
    );
    expect(preview.photoSyncStates['a'], 'conflict');
    expect(AnimalPhoto.fromSnapshot(preview, 'a').first.crop.x, 50);
    await expectLater(
      capture(db, photoOperation(id: 'must-not-rebase')),
      throwsStateError,
    );
  });

  test('LRU bounds encrypted bytes globally and cache cleanup preserves pending metadata', () async {
    final db = OfflineStore(
      NativeDatabase.memory(),
      LocalCipher(Uint8List(32)),
    );
    addTearDown(db.close);
    await seed(db);
    final bytes = Uint8List.fromList(List.filled(128, 42));
    await db.savePhotoOriginal(
      photoUser,
      photoOwner,
      photoProject,
      '$photoOwner/a/one',
      bytes,
    );
    final size =
        (await db
                .customSelect('SELECT byte_length FROM photo_originals')
                .getSingle())
            .read<int>('byte_length');
    await db.savePhotoOriginal(
      photoUser,
      photoOwner,
      photoProject,
      '$photoOwner/a/two',
      bytes,
      budget: size * 2,
    );
    await db.readPhotoOriginal(
      photoUser,
      photoOwner,
      photoProject,
      '$photoOwner/a/one',
    );
    await db.savePhotoOriginal(
      photoUser,
      photoOwner,
      'other-project',
      '$photoOwner/a/three',
      bytes,
      budget: size * 2,
    );
    expect(
      await db.readPhotoOriginal(
        photoUser,
        photoOwner,
        photoProject,
        '$photoOwner/a/two',
      ),
      isNull,
    );
    expect(
      await db.readPhotoOriginal(
        photoUser,
        photoOwner,
        photoProject,
        '$photoOwner/a/one',
      ),
      bytes,
    );
    expect(
      (await db
              .customSelect(
                'SELECT SUM(byte_length) AS total FROM photo_originals',
              )
              .getSingle())
          .read<int>('total'),
      lessThanOrEqualTo(size * 2),
    );
    await capture(db, photoOperation());
    await db.invalidateOtherRanch(photoUser, 'new-ranch');
    expect(
      await db.readPhotoOriginal(
        photoUser,
        photoOwner,
        photoProject,
        '$photoOwner/a/one',
      ),
      isNull,
    );
    expect(
      await db.readPhotoMetadata(
        photoUser,
        photoOwner,
        photoProject,
        firstPhoto,
      ),
      isNull,
    );
    expect(await db.universalPending(photoUser, photoOwner), hasLength(1));
  });
}
