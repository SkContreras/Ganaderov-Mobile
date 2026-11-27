import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/local_cipher.dart';
import 'package:ganaderov/core/database/offline_store.dart';

const user = '11111111-1111-4111-8111-111111111111';
const owner = '22222222-2222-4222-8222-222222222222';
const project = 'https://staging.example.test';
Map<String, dynamic> operation(
  String id,
  String action, {
  String entity = 'animal',
  int? revision,
  Map<String, dynamic> changes = const {},
}) => {
  'protocolVersion': 1,
  'operationId': id,
  'ownerId': owner,
  'deviceId': '33333333-3333-4333-8333-333333333333',
  'action': action,
  'entityId': entity,
  'baseRevision': revision,
  'capturedAt': '2026-01-01T00:00:00Z',
  'changes': changes,
};
Map<String, dynamic> receipt(
  String id,
  int revision, {
  String status = 'applied',
}) => {
  'protocolVersion': 1,
  'operationId': id,
  'status': status,
  'revision': revision,
  'serverReceivedAt': '2026-01-01T01:00:00Z',
  'code': status == 'applied' ? 'OK' : 'REVISION_CONFLICT',
};

void main() {
  test('dependency remains separate until a confirmed receipt supplies its exact revision', () async {
    final db = OfflineStore(
      NativeDatabase.memory(),
      LocalCipher(Uint8List(32)),
    );
    addTearDown(db.close);
    await db.captureUniversalDraft(
      user,
      owner,
      project,
      operation(
        'create',
        'animal.create',
        changes: {
          'fields': {'tag': '1'},
        },
      ),
    );
    await db.captureUniversalDraft(
      user,
      owner,
      project,
      operation(
        'edit',
        'animal.update',
        changes: {
          'fields': {'name': 'Nuevo'},
        },
      ),
      dependencies: ['create'],
      revisionFrom: 'create',
    );
    expect((await db.universalPending(user, owner)).map((r) => r['id']), [
      'create',
    ]);
    expect(
      (await db.localUniversalChanges(user, owner, project)).last['state'],
      'waiting',
    );
    await db.settleUniversal(user, owner, 'create', 'pending', null, 0);
    await db.sealReadyDrafts(user, owner, project);
    expect((await db.universalPending(user, owner)).map((r) => r['id']), [
      'create',
    ]);
    await db.settleUniversal(
      user,
      owner,
      'create',
      'confirmed',
      receipt('create', 37),
      0,
    );
    await db.sealReadyDrafts(user, owner, project);
    final sealed =
        (await db.universalPending(user, owner)).single['operation'] as Map;
    expect(sealed['baseRevision'], 37);
    expect(sealed['operationId'], 'edit');
    expect(sealed['changes'], {
      'fields': {'name': 'Nuevo'},
    });
    await expectLater(
      db.enqueueUniversal(user, owner, {...sealed, 'baseRevision': 38}),
      throwsStateError,
    );
  });

  test(
    'encrypted drafts and sealed bodies survive reopening without rebase',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ganaderov-drafts-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/state.sqlite'),
          cipher = LocalCipher(Uint8List(32));
      var db = OfflineStore(NativeDatabase(file), cipher);
      await db.captureUniversalDraft(
        user,
        owner,
        project,
        operation(
          'journey',
          'journey.create',
          entity: 'j',
          changes: {
            'type': 'weight',
            'animalIds': ['a'],
          },
        ),
      );
      await db.captureUniversalDraft(
        user,
        owner,
        project,
        operation(
          'attend',
          'journey.attend',
          entity: 'j',
          changes: {'animalId': 'a', 'weight': 220},
        ),
        dependencies: ['journey'],
        revisionFrom: 'journey',
      );
      final raw = await db
          .customSelect('SELECT payload FROM universal_drafts')
          .get();
      expect(
        raw.every(
          (r) =>
              r.read<String>('payload').startsWith(LocalCipher.accountPrefix),
        ),
        isTrue,
      );
      expect(
        raw.any((r) => r.read<String>('payload').contains('weight')),
        isFalse,
      );
      await db.close();
      db = OfflineStore(NativeDatabase(file), cipher);
      await db.settleUniversal(
        user,
        owner,
        'journey',
        'confirmed',
        receipt('journey', 82),
        0,
      );
      await db.sealReadyDrafts(user, owner, project);
      final before = jsonEncode(
        (await db.universalPending(user, owner)).single['operation'],
      );
      await db.settleUniversal(user, owner, 'attend', 'pending', null, 500);
      await db.saveEntityRevision(user, owner, project, 'journey', 'j', {
        'revision': 99,
        'data': {},
        'parentId': null,
      });
      await db.close();
      db = OfflineStore(NativeDatabase(file), cipher);
      addTearDown(db.close);
      await db.sealReadyDrafts(user, owner, project);
      final after = (await db.universalPending(user, owner)).single;
      expect(jsonEncode(after['operation']), before);
      expect((after['operation'] as Map)['baseRevision'], 82);
      expect(after['attempts'], 1);
    },
  );

  test('terminal dependencies are visible and never follow a replacement automatically', () async {
    final db = OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    final first = operation(
      'first',
      'animal.update',
      revision: 5,
      changes: {
        'fields': {'name': 'Uno'},
      },
    );
    await db.captureUniversalDraft(user, owner, project, first);
    await db.captureUniversalDraft(
      user,
      owner,
      project,
      operation('dependent', 'animal.archive', changes: {'status': 'Vendido'}),
      dependencies: ['first'],
      revisionFrom: 'first',
    );
    await db.settleUniversal(
      user,
      owner,
      'first',
      'conflict',
      receipt('first', 6, status: 'conflict'),
      0,
    );
    await db.sealReadyDrafts(user, owner, project);
    var dependent = (await db.localUniversalChanges(user, owner, project)).last;
    expect(dependent['state'], 'blocked');
    expect(dependent['error'], contains('first'));
    await db.replaceConflict(
      user,
      owner,
      'first',
      first,
      operation(
        'replacement',
        'animal.update',
        revision: 6,
        changes: {
          'fields': {'name': 'Uno'},
        },
      ),
      project: project,
    );
    await db.settleUniversal(
      user,
      owner,
      'replacement',
      'confirmed',
      receipt('replacement', 7),
      0,
    );
    await db.sealReadyDrafts(user, owner, project);
    dependent = (await db.localUniversalChanges(
      user,
      owner,
      project,
    )).singleWhere((e) => e['id'] == 'dependent');
    expect(dependent['state'], 'blocked');
    expect(dependent['draft'], isTrue);
    await db.archiveUnsealedDraft(user, owner, project, 'dependent');
    expect(
      (await db.localUniversalChanges(
        user,
        owner,
        project,
        includeArchived: true,
      )).singleWhere((e) => e['id'] == 'dependent')['state'],
      'archived',
    );
  });

  test('dependencies and revision caches are isolated by project and transaction guards', () async {
    final db = OfflineStore(
      NativeDatabase.memory(),
      LocalCipher(Uint8List(32)),
    );
    addTearDown(db.close);
    await db.captureUniversalDraft(
      user,
      owner,
      project,
      operation('a', 'animal.create'),
    );
    await expectLater(
      db.captureUniversalDraft(
        user,
        owner,
        'https://other.example',
        operation('b', 'event.create'),
        dependencies: ['a'],
      ),
      throwsStateError,
    );
    await db.saveEntityRevision(user, owner, project, 'animal', 'a', {
      'revision': 9,
      'data': {'id': 'a'},
      'parentId': null,
    });
    expect(
      await db.readEntityRevision(
        user,
        owner,
        'https://other.example',
        'animal',
        'a',
      ),
      isNull,
    );
    var guards = 0;
    await expectLater(
      db.captureUniversalDraft(
        user,
        owner,
        project,
        operation('rollback', 'animal.create'),
        verify: () {
          if (++guards == 2) throw StateError('session changed');
        },
      ),
      throwsStateError,
    );
    expect(
      (await db.localUniversalChanges(
        user,
        owner,
        project,
      )).any((r) => r['id'] == 'rollback'),
      isFalse,
    );
  });

  test('only receipts already confirmed at snapshot start retire local projections', () async {
    final db = OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    await db.captureUniversalDraft(
      user,
      owner,
      project,
      operation('one', 'animal.create', entity: 'one'),
    );
    await db.captureUniversalDraft(
      user,
      owner,
      project,
      operation('two', 'animal.create', entity: 'two'),
    );
    await db.settleUniversal(
      user,
      owner,
      'one',
      'confirmed',
      receipt('one', 4),
      0,
    );
    final barrier = await db.confirmedDraftOperations(
      user,
      project,
      kinds: {'animal'},
    );
    await db.settleUniversal(
      user,
      owner,
      'two',
      'confirmed',
      receipt('two', 8),
      0,
    );
    await db.acknowledgeDraftSnapshot(user, owner, project, barrier);
    expect(
      (await db.localUniversalChanges(
        user,
        owner,
        project,
      )).map((e) => e['id']),
      ['two'],
    );
    expect(await db.draftOperationProject(user, owner, 'one'), project);
  });

  test(
    'version eleven migration preserves an existing immutable operation',
    () async {
      final original = operation(
        'legacy',
        'animal.update',
        revision: 8,
        changes: {
          'fields': {'name': 'Existente'},
        },
      );
      final db = OfflineStore(
        NativeDatabase.memory(
          setup: (sql) {
            sql.execute(
              "CREATE TABLE universal_outbox (user_id TEXT,owner_id TEXT,operation_id TEXT,payload TEXT,attachment TEXT,state TEXT DEFAULT 'pending',attempts INTEGER DEFAULT 0,next_at INTEGER DEFAULT 0,receipt TEXT,archived_from TEXT,resolved_by TEXT,resolves TEXT,PRIMARY KEY(user_id,owner_id,operation_id))",
            );
            sql.execute(
              'INSERT INTO universal_outbox(user_id,owner_id,operation_id,payload) VALUES(?,?,?,?)',
              [user, owner, 'legacy', jsonEncode(original)],
            );
            sql.userVersion = 11;
          },
        ),
      );
      addTearDown(db.close);
      expect(
        (await db.universalPending(user, owner)).single['operation'],
        original,
      );
      expect(await db.localUniversalChanges(user, owner, project), isEmpty);
      await db.captureUniversalDraft(
        user,
        owner,
        project,
        operation('new', 'animal.create', entity: 'new'),
      );
      expect(await db.universalPending(user, owner), hasLength(2));
    },
  );
}
