import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/local_cipher.dart';
import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/core/sync/universal_sync.dart';
import 'package:ganaderov/features/livestock/data/supabase_inventory_repository.dart';
import 'package:ganaderov/features/livestock/domain/event_draft.dart';
import 'package:ganaderov/features/settings/domain/animal_configuration.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'completion_test_fixtures.dart';

void main() {
  late OfflineStore db;
  late SupabaseClient client;
  late SupabaseInventoryRepository repository;
  late List<http.Request> network;
  late Future<http.Response> Function(http.Request) response;
  setUp(() async {
    db = OfflineStore(NativeDatabase.memory(), LocalCipher(Uint8List(32)));
    network = [];
    response = (_) async =>
        throw http.ClientException('Offline test must not request HTTP');
    client = SupabaseClient(
      completionProject,
      'sb_publishable_fixture',
      httpClient: MockClient((request) async {
        network.add(request);
        final result = await response(request);
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await completionSession(client);
    repository = SupabaseInventoryRepository(
      client,
      store: db,
      universalEnabled: true,
      project: completionProject,
    );
    await seedCompletion(db);
  });
  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  test('new animal, event, journey attendance, finish and resume persist offline then seal from receipts', () async {
    final directory = await Directory.systemTemp.createTemp('ganaderov-chain-');
    addTearDown(() => directory.delete(recursive: true));
    await db.close();
    final file = File('${directory.path}/chain.sqlite'),
        cipher = LocalCipher(Uint8List(32));
    db = OfflineStore(NativeDatabase(file), cipher);
    await seedCompletion(db);
    repository = SupabaseInventoryRepository(
      client,
      store: db,
      universalEnabled: true,
      project: completionProject,
    );
    var snapshot = completionSnapshot(offline: true);
    await repository.saveAnimal(
      snapshot,
      null,
      {'tag': '002', 'sex': 'Macho', 'name': 'Nuevo'},
      createId: newAnimal,
      operationId: '88888888-8888-4888-8888-888888888888',
    );
    snapshot = await repository.refreshLocalInventory(snapshot);
    expect(
      snapshot.animals
          .singleWhere((a) => a.id == newAnimal)
          .value('internalId'),
      'Por asignar',
    );
    await repository.addEvent(
      snapshot,
      newAnimal,
      const EventDraft(
        id: newEvent,
        type: 'weight',
        date: '2026-01-01',
        weight: 220,
      ),
    );
    await repository.createJourney(
      snapshot,
      newJourney,
      'weight',
      '2026-01-01',
      '',
      '',
      '',
      {newAnimal, 'a'},
    );
    var journey = (await repository.refreshLocalJourneys(snapshot)).single;
    await repository.attendJourney(snapshot, journey, newAnimal, 221);
    journey = (await repository.refreshLocalJourneys(snapshot)).single;
    expect(journey.attended, 1);
    await repository.finishJourney(snapshot, journey);
    journey = (await repository.refreshLocalJourneys(snapshot)).single;
    expect(journey.status, 'incomplete');
    await repository.resumeJourney(snapshot, journey);
    expect(network, isEmpty);
    final captured = await db.localUniversalChanges(
      completionUser,
      completionOwner,
      completionProject,
    );
    expect(captured, hasLength(6));
    expect(
      await db.universalPending(completionUser, completionOwner),
      hasLength(1),
    );
    expect(
      (await db.read(completionUser, project: completionProject))!.animals,
      hasLength(1),
    );
    await db.close();
    db = OfflineStore(NativeDatabase(file), cipher);
    repository = SupabaseInventoryRepository(
      client,
      store: db,
      universalEnabled: true,
      project: completionProject,
    );
    snapshot = await repository.refreshLocalInventory(snapshot);
    expect(snapshot.animals, hasLength(2));
    expect(
      (await repository.refreshLocalJourneys(snapshot)).single.status,
      'in_progress',
    );
    final delivered = <Map<String, dynamic>>[], revisions = <String, int>{};
    response = (request) async {
      expect(request.url.path, '/rest/v1/rpc/sync_apply_operation');
      final operation = Map<String, dynamic>.from(
        (jsonDecode(request.body) as Map)['p_operation'] as Map,
      );
      final id = operation['entityId'] as String,
          key = '${(operation['action'] as String).split('.').first}:$id';
      if (!(operation['action'] as String).endsWith('.create')) {
        expect(operation['baseRevision'], revisions[key]);
      }
      revisions[key] = (revisions[key] ?? 16) + 1;
      delivered.add(operation);
      return http.Response(
        jsonEncode({
          'protocolVersion': 1,
          'operationId': operation['operationId'],
          'status': 'applied',
          'revision': revisions[key],
          'serverReceivedAt': DateTime.now().toUtc().toIso8601String(),
          'code': 'OK',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    };
    await UniversalSync(
      client,
      db,
      completionProject,
    ).flush(completionUser, completionOwner, 'fixture', manual: true);
    expect(delivered.map((op) => op['action']), [
      'animal.create',
      'event.create',
      'journey.create',
      'journey.attend',
      'journey.finish',
      'journey.resume',
    ]);
    expect(delivered[3]['baseRevision'], 17);
    expect(delivered[4]['baseRevision'], 18);
    expect(delivered[5]['baseRevision'], 19);
    expect(
      (await db.localUniversalChanges(
        completionUser,
        completionOwner,
        completionProject,
      )).every((r) => r['state'] == 'confirmed'),
      isTrue,
    );
    expect(await db.universalPending(completionUser, completionOwner), isEmpty);
  });

  test('offline edit, archive and restore preserve confirmed cache and chain exact revisions', () async {
    var snapshot = completionSnapshot(offline: true);
    await repository.saveAnimal(snapshot, 'a', {'name': 'Corregida'});
    snapshot = await repository.refreshLocalInventory(snapshot);
    await repository.setAnimalStatus(snapshot, 'a', 'Vendido');
    snapshot = await repository.refreshLocalInventory(snapshot);
    expect(snapshot.animals.single.active, isFalse);
    await repository.setAnimalStatus(snapshot, 'a', 'Activo');
    snapshot = await repository.refreshLocalInventory(snapshot);
    expect(snapshot.animals.single.active, isTrue);
    expect(snapshot.animals.single.value('name'), 'Corregida');
    expect(
      (await db.read(
        completionUser,
        project: completionProject,
      ))!.animals.single.value('name'),
      'Primera',
    );
    final entries = await db.localUniversalChanges(
      completionUser,
      completionOwner,
      completionProject,
    );
    expect(entries.map((e) => (e['operation'] as Map)['action']), [
      'animal.update',
      'animal.archive',
      'animal.restore',
    ]);
    expect((entries.first['operation'] as Map)['baseRevision'], 7);
    expect(entries.skip(1).every((e) => e['state'] == 'waiting'), isTrue);
    expect(network, isEmpty);
  });

  test(
    'concurrent edits cannot both seal against the same cached revision',
    () async {
      final snapshot = completionSnapshot(offline: true);
      final outcomes = await Future.wait([
        for (final name in ['Primera edición', 'Segunda edición'])
          repository
              .saveAnimal(snapshot, 'a', {'name': name})
              .then<Object?>((_) => null, onError: (Object error) => error),
      ]);
      expect(outcomes.where((result) => result == null), hasLength(1));
      expect(outcomes.whereType<StateError>(), hasLength(1));
      final entries = await db.localUniversalChanges(
        completionUser,
        completionOwner,
        completionProject,
      );
      expect(entries, hasLength(1));
      expect((entries.single['operation'] as Map)['baseRevision'], 7);
      expect(network, isEmpty);
    },
  );

  test('historical corrections require reason, fixed type, correct parent, role and real cached revision', () async {
    final snapshot = completionSnapshot(offline: true),
        event = completionSnapshot().animals.single.events.single;
    await expectLater(
      repository.updateHistoricalEvent(snapshot, 'a', event, {
        'weight': 120,
      }, ''),
      throwsStateError,
    );
    await expectLater(
      repository.updateHistoricalEvent(snapshot, 'a', event, {
        'type': 'note',
      }, 'Corrección'),
      throwsStateError,
    );
    await expectLater(
      repository.updateHistoricalEvent(
        completionSnapshot(offline: true, role: 'worker'),
        'a',
        event,
        {'weight': 120},
        'Corrección',
      ),
      throwsStateError,
    );
    await repository.updateHistoricalEvent(snapshot, 'a', event, {
      'weight': 120,
      'notes': 'Corregido',
    }, 'Báscula revisada');
    final op =
        (await db.universalPending(
              completionUser,
              completionOwner,
            )).single['operation']
            as Map;
    expect(op['baseRevision'], 9);
    expect((op['changes'] as Map)['reason'], 'Báscula revisada');
    final preview = await repository.refreshLocalInventory(snapshot);
    expect(preview.animals.single.events.single.weight, 120);
    expect(
      (await db.read(
        completionUser,
        project: completionProject,
      ))!.animals.single.events.single.weight,
      100,
    );
    await repository.deleteHistoricalEvent(
      preview,
      'a',
      preview.animals.single.events.single,
      'Duplicado',
    );
    expect(
      (await repository.refreshLocalInventory(snapshot)).animals.single.events,
      isEmpty,
    );
    expect(
      (await db.localUniversalChanges(
        completionUser,
        completionOwner,
        completionProject,
      )).last['state'],
      'waiting',
    );
    expect(network, isEmpty);
  });

  test(
    'expired context and missing canonical revision fail closed offline',
    () async {
      await expectLater(
        repository.saveAnimal(
          completionSnapshot(
            offline: true,
            cachedAt: DateTime.now().subtract(const Duration(hours: 25)),
          ),
          'a',
          {'name': 'Tarde'},
        ),
        throwsStateError,
      );
      await db.customStatement('DELETE FROM entity_revisions');
      await expectLater(
        repository.saveAnimal(completionSnapshot(offline: true), 'a', {
          'name': 'Sin revisión',
        }),
        throwsStateError,
      );
      expect(
        await db.universalPending(completionUser, completionOwner),
        isEmpty,
      );
      expect(network, isEmpty);
    },
  );

  test(
    'worker cannot create manager-only note or other events offline',
    () async {
      final worker = completionSnapshot(offline: true, role: 'worker');
      for (final type in ['note', 'other']) {
        await expectLater(
          repository.addEvent(
            worker,
            'a',
            EventDraft(
              id: newEvent,
              type: type,
              date: '2026-01-02',
              notes: 'Observación',
            ),
          ),
          throwsStateError,
        );
      }
      expect(
        await db.universalPending(completionUser, completionOwner),
        isEmpty,
      );
      expect(network, isEmpty);
    },
  );

  test('offline configuration uses canonical config revision and stays a local projection', () async {
    final snapshot = completionSnapshot(offline: true),
        config = editableAnimalConfiguration(completionSnapshot().config);
    (config['fields'] as Map)['tag']['label'] = 'Identificador local';
    await repository.saveConfiguration(snapshot, config);
    final op =
        (await db.universalPending(
              completionUser,
              completionOwner,
            )).single['operation']
            as Map;
    expect(op['action'], 'config.update');
    expect(op['baseRevision'], 4);
    final preview = await repository.refreshLocalInventory(snapshot);
    expect(
      (preview.config['fields'] as Map)['tag']['label'],
      'Identificador local',
    );
    expect(
      ((await db.read(
            completionUser,
            project: completionProject,
          ))!.config['fields']
          as Map)['tag']['label'],
      'Número de arete',
    );
    expect(network, isEmpty);
  });

  test(
    'batch preparation only caches revisions whose data matches the inventory',
    () async {
      await db.customStatement('DELETE FROM entity_revisions');
      final snapshot = completionSnapshot();
      response = (request) async {
        expect(request.url.path, '/rest/v1/rpc/sync_read_entities');
        final entities =
            (jsonDecode(request.body) as Map)['p_entities'] as List;
        expect(entities, hasLength(3));
        final payload = snapshot.records.single['payload'] as Map;
        return http.Response(
          jsonEncode([
            {
              'kind': 'animal',
              'id': 'a',
              'revision': 45,
              'data': payload['animal'],
              'parentId': null,
            },
            {
              'kind': 'event',
              'id': existingEvent,
              'revision': 57,
              'data': {
                ...(payload['events'] as List).single as Map,
                'weight': 999,
              },
              'parentId': 'a',
            },
            {
              'kind': 'config',
              'id': completionOwner,
              'revision': 12,
              'data': snapshot.config,
              'parentId': null,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      await expectLater(
        repository.prepareOfflineInventory(snapshot),
        throwsStateError,
      );
      expect(
        (await db.readEntityRevision(
          completionUser,
          completionOwner,
          completionProject,
          'animal',
          'a',
        ))!['revision'],
        45,
      );
      expect(
        await db.readEntityRevision(
          completionUser,
          completionOwner,
          completionProject,
          'event',
          existingEvent,
        ),
        isNull,
      );
    },
  );
}
