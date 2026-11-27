import 'dart:convert';

import '../../journeys/domain/journey.dart';
import 'inventory.dart';

String pendingLabel(String? state) => switch (state) {
  'waiting' => 'Guardado; espera una operación anterior',
  'blocked' => 'Dependencia bloqueada; revisa Sincronización',
  'conflict' => 'Conflicto; revisa Sincronización',
  'rejected' => 'Rechazado; revisa Sincronización',
  'confirmed' => 'Confirmado; actualizando datos',
  'pending' => 'Guardado en el dispositivo; pendiente de envío',
  _ => '',
};

bool projectsLocally(String state) =>
    ['waiting', 'pending', 'confirmed'].contains(state);

InventorySnapshot projectInventoryChanges(
  InventorySnapshot snapshot,
  List<Map<String, dynamic>> changes, {
  required bool offlineWritesEnabled,
}) {
  final records = (jsonDecode(jsonEncode(snapshot.records)) as List)
      .cast<Map<String, dynamic>>();
  var config = Map<String, dynamic>.from(snapshot.config);
  final states = <String, String>{};
  for (final entry in changes) {
    final op = entry['operation'] as Map,
        action = op['action'] as String,
        id = op['entityId'] as String,
        c = op['changes'] as Map,
        state = entry['state'] as String;
    if (op['ownerId'] != snapshot.ownerId) continue;
    final key = '${action.split('.').first}:$id';
    if (!['blocked', 'conflict', 'rejected'].contains(states[key])) {
      states[key] = state;
    }
    if (action.startsWith('event.') && c['animalId'] is String) {
      final history = 'history:${c['animalId']}';
      if (!['blocked', 'conflict', 'rejected'].contains(states[history])) {
        states[history] = state;
      }
    }
    if (!projectsLocally(state)) continue;
    if (action == 'config.update') {
      config = Map<String, dynamic>.from(c['config'] as Map);
      continue;
    }
    final animalId = action.startsWith('animal.') ? id : c['animalId'];
    var row = records
        .where((r) => r['animal_id'] == animalId && r['deleted_at'] == null)
        .firstOrNull;
    if (action == 'animal.create' && row == null) {
      row = {
        'animal_id': id,
        'deleted_at': null,
        'payload': {
          'animal': {
            'id': id,
            'status': 'Activo',
            ...(c['fields'] as Map),
            'createdAt': op['capturedAt'],
            'internalId': 'Por asignar',
          },
          'events': [],
          'photos': [],
          'forecasts': [],
        },
      };
      records.add(row);
    } else if (row != null) {
      final payload = row['payload'] as Map;
      if (action.startsWith('animal.')) {
        final animal = payload['animal'] as Map;
        if (action == 'animal.update') animal.addAll(c['fields'] as Map);
        if (action == 'animal.archive' || action == 'animal.restore') {
          animal.addAll(c);
          if (action == 'animal.restore') {
            animal.remove('exitReason');
            animal.remove('exitNotes');
          }
        }
      } else if (action.startsWith('event.')) {
        final events = (payload['events'] as List);
        final event = events
            .whereType<Map>()
            .where((e) => e['id'] == id)
            .firstOrNull;
        if (action == 'event.create' && event == null) {
          events.add({
            'id': id,
            'animalId': animalId,
            'type': c['type'],
            'date': c['date'],
            'createdAt': op['capturedAt'],
            if (c.containsKey('weight')) 'weight': c['weight'],
            if (c.containsKey('product')) 'label': c['product'],
            if (c.containsKey('notes')) 'notes': c['notes'],
          });
        }
        if (action == 'event.update' && event != null) {
          for (final field in ['date', 'weight', 'notes']) {
            if (c.containsKey(field)) event[field] = c[field];
          }
          if (c.containsKey('product')) event['label'] = c['product'];
        }
        if (action == 'event.delete') {
          events.removeWhere((e) => e is Map && e['id'] == id);
        }
      }
    }
  }
  final statuses = config['lists'] is Map
      ? (config['lists'] as Map)['status']
      : null;
  final options = Map<String, bool>.from(snapshot.statusOptions),
      labels = Map<String, String>.from(snapshot.statusLabels);
  if (statuses is List) {
    for (final status in statuses.whereType<Map>()) {
      if (status['value'] is String) {
        options[status['value'] as String] = status['active'] != false;
        labels[status['value'] as String] =
            status['label']?.toString() ?? status['value'] as String;
      }
    }
  }
  return InventorySnapshot(
    status: snapshot.status,
    ranchName: snapshot.ranchName,
    role: snapshot.role,
    records: records,
    statusOptions: options,
    statusLabels: labels,
    config: config,
    ownerId: snapshot.ownerId,
    userId: snapshot.userId,
    configRevision: snapshot.configRevision,
    offline: snapshot.offline,
    cachedAt: snapshot.cachedAt,
    photoSyncStates: snapshot.photoSyncStates,
    operationStates: states,
    offlineWritesEnabled: offlineWritesEnabled,
  );
}

List<Journey> projectJourneyChanges(
  List<Journey> confirmed,
  InventorySnapshot snapshot,
  List<Map<String, dynamic>> changes,
) {
  final rows = {
    for (final j in confirmed)
      j.id: Map<String, dynamic>.from(jsonDecode(jsonEncode(j.payload)) as Map),
  };
  final states = <String, String>{};
  for (final entry in changes) {
    final op = entry['operation'] as Map,
        action = op['action'] as String,
        id = op['entityId'] as String,
        c = op['changes'] as Map,
        state = entry['state'] as String;
    if (op['ownerId'] != snapshot.ownerId || !action.startsWith('journey.')) {
      continue;
    }
    if (!['blocked', 'conflict', 'rejected'].contains(states[id])) {
      states[id] = state;
    }
    if (!projectsLocally(state)) continue;
    List<Map<String, dynamic>> roster(List ids) => [
      for (final id in ids)
        Journey.rosterEntry(
          snapshot.animals.firstWhere(
            (a) => a.id == id,
            orElse: () => InventoryAnimal(
              id: id as String,
              fields: const {},
              active: true,
              statusLabel: '',
              events: const [],
            ),
          ),
        ),
    ];
    if (action == 'journey.create') {
      rows.putIfAbsent(
        id,
        () => {
          'id': id,
          ...c,
          'roster': roster(c['animalIds'] as List),
          'status': 'in_progress',
          'createdAt': op['capturedAt'],
          'updatedAt': op['capturedAt'],
          'completedAt': null,
        },
      );
    }
    final row = rows[id];
    if (row == null) continue;
    final animals = row['roster'] as List;
    if (action == 'journey.add_animals') {
      for (final animal in roster(c['animalIds'] as List)) {
        if (!animals.any((a) => (a as Map)['id'] == animal['id'])) {
          animals.add(animal);
        }
      }
    }
    if (action == 'journey.attend') {
      final animal = animals
          .whereType<Map>()
          .where((a) => a['id'] == c['animalId'])
          .firstOrNull;
      if (animal != null) {
        animal['attended'] = true;
        if (c.containsKey('weight')) animal['weight'] = c['weight'];
      }
    }
    if (action == 'journey.finish') {
      row['status'] = animals.every((a) => (a as Map)['attended'] == true)
          ? 'completed'
          : 'incomplete';
    }
    if (action == 'journey.resume') row['status'] = 'in_progress';
  }
  final result = [
    for (final row in rows.entries)
      Journey(
        row.key,
        confirmed.where((j) => j.id == row.key).firstOrNull?.version ?? '',
        row.value,
        revision: confirmed.where((j) => j.id == row.key).firstOrNull?.revision,
        syncState: states[row.key],
      ),
  ];
  result.sort((a, b) => b.date.compareTo(a.date));
  return result;
}
