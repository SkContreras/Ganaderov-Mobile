import 'dart:convert';

import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';
import 'package:ganaderov/features/settings/domain/animal_configuration.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const completionUser = '11111111-1111-4111-8111-111111111111';
const completionOwner = '22222222-2222-4222-8222-222222222222';
const completionProject = 'https://completion.example.test';
const existingEvent = '44444444-4444-4444-8444-444444444444';
const newAnimal = '55555555-5555-4555-8555-555555555555';
const newJourney = '66666666-6666-4666-8666-666666666666';
const newEvent = '77777777-7777-4777-8777-777777777777';

InventorySnapshot completionSnapshot({
  bool offline = false,
  String role = 'owner',
  DateTime? cachedAt,
}) => InventorySnapshot(
  status: 'active',
  ranchName: 'Rancho de prueba',
  role: role,
  userId: completionUser,
  ownerId: completionOwner,
  offline: offline,
  cachedAt: cachedAt ?? DateTime.now(),
  offlineWritesEnabled: true,
  configRevision: 1,
  config: editableAnimalConfiguration({}),
  records: [
    {
      'animal_id': 'a',
      'modified_at': '2026-01-01T00:00:00Z',
      'deleted_at': null,
      'payload': {
        'animal': {
          'id': 'a',
          'tag': '001',
          'sex': 'Hembra',
          'status': 'Activo',
          'name': 'Primera',
          'internalId': 'ANM-00001',
        },
        'events': [
          {
            'id': existingEvent,
            'animalId': 'a',
            'type': 'weight',
            'date': '2026-01-01',
            'weight': 100,
            'notes': 'Pesaje inicial',
          },
        ],
        'photos': [],
        'forecasts': [],
      },
    },
  ],
);

Future<void> completionSession(SupabaseClient client) async {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final jwt =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': completionUser, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7200})}.fixture';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': jwt,
      'token_type': 'bearer',
      'expires_in': 7200,
      'refresh_token': 'fixture-refresh',
      'user': {
        'id': completionUser,
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

Future<void> seedCompletion(OfflineStore db) async {
  final snapshot = completionSnapshot();
  await db.save(snapshot, project: completionProject);
  final payload = snapshot.records.single['payload'] as Map;
  await db.saveEntityRevision(
    completionUser,
    completionOwner,
    completionProject,
    'animal',
    'a',
    {'revision': 7, 'data': payload['animal'], 'parentId': null},
  );
  await db.saveEntityRevision(
    completionUser,
    completionOwner,
    completionProject,
    'event',
    existingEvent,
    {
      'revision': 9,
      'data': (payload['events'] as List).single,
      'parentId': 'a',
    },
  );
  await db.saveEntityRevision(
    completionUser,
    completionOwner,
    completionProject,
    'config',
    completionOwner,
    {'revision': 4, 'data': snapshot.config, 'parentId': null},
  );
}
