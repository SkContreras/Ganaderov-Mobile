part of 'supabase_inventory_repository.dart';

extension UniversalInventoryOperations on SupabaseInventoryRepository {
  void captureScope(InventorySnapshot snapshot, {bool manager = false}) {
    if (!supportsOfflineInventory) {
      throw StateError('La captura universal no está disponible');
    }
    _photoScope(snapshot, write: manager);
  }

  Future<InventorySnapshot> localInventory(InventorySnapshot snapshot) async {
    captureScope(snapshot);
    final cached = await store!.read(snapshot.userId, project: project);
    captureScope(snapshot);
    if (cached == null || cached.ownerId != snapshot.ownerId) {
      throw StateError('Descarga el inventario antes de continuar');
    }
    return _projectPhotoSnapshot(
      InventorySnapshot(
        status: cached.status,
        ranchName: cached.ranchName,
        role: cached.role,
        records: cached.records,
        statusOptions: cached.statusOptions,
        statusLabels: cached.statusLabels,
        config: cached.config,
        ownerId: cached.ownerId,
        userId: cached.userId,
        configRevision: cached.configRevision,
        offline: snapshot.offline,
        cachedAt: cached.cachedAt,
      ),
    );
  }

  Future<void> cacheInventoryRevisions(
    InventorySnapshot snapshot, {
    void Function()? verify,
  }) async {
    captureScope(snapshot);
    if (snapshot.offline) {
      throw StateError('Conéctate para descargar las revisiones');
    }
    final expected = <String, Object?>{
      'config:${snapshot.ownerId}': snapshot.config.isEmpty
          ? null
          : snapshot.config,
    };
    final parents = <String, String>{};
    for (final row in snapshot.records) {
      if (row['deleted_at'] != null) continue;
      final payload = row['payload'] as Map, id = row['animal_id'] as String;
      expected['animal:$id'] = payload['animal'];
      for (final event
          in (payload['events'] as List? ?? const []).whereType<Map>()) {
        if (event['id'] is String && event['journeyId'] == null) {
          expected['event:${event['id']}'] = event;
          parents['event:${event['id']}'] = id;
        }
      }
    }
    final entries = expected.keys.toList();
    final matched = <String>{};
    for (var offset = 0; offset < entries.length; offset += 100) {
      verify?.call();
      captureScope(snapshot);
      final keys = entries.skip(offset).take(100).toList();
      final rows = await client
          .rpc(
            'sync_read_entities',
            params: {
              'p_owner': snapshot.ownerId,
              'p_entities': [
                for (final key in keys)
                  {
                    'kind': key.substring(0, key.indexOf(':')),
                    'id': key.substring(key.indexOf(':') + 1),
                  },
              ],
            },
          )
          .timeout(const Duration(seconds: 20));
      verify?.call();
      captureScope(snapshot);
      if (rows is! List) throw const FormatException('Revisiones inválidas');
      for (final raw in rows.whereType<Map>()) {
        final key = '${raw['kind']}:${raw['id']}';
        if (!keys.contains(key) ||
            !_sameJson(raw['data'], expected[key]) ||
            (parents.containsKey(key) && raw['parentId'] != parents[key])) {
          continue;
        }
        await store!.saveEntityRevision(
          snapshot.userId,
          snapshot.ownerId,
          project,
          raw['kind'] as String,
          raw['id'] as String,
          Map<String, dynamic>.from(raw),
          verify: () {
            verify?.call();
            captureScope(snapshot);
          },
        );
        matched.add(key);
      }
    }
    if (matched.length != entries.length) {
      throw StateError(
        'Algunos datos cambiaron durante la descarga. Actualiza el inventario y vuelve a prepararlo',
      );
    }
  }

  Future<Map<String, dynamic>?> localPredecessor(
    InventorySnapshot s,
    String kind,
    String id,
  ) async {
    final prior = await store!.latestEntityChange(
      s.userId,
      s.ownerId,
      project,
      kind,
      id,
    );
    captureScope(s);
    if (prior != null && !projectsLocally(prior['state'] as String)) {
      throw StateError(
        'La operación anterior requiere revisión en Sincronización',
      );
    }
    return prior;
  }

  Future<List<String>> animalDependencies(
    InventorySnapshot s,
    Iterable<String> animals,
  ) async {
    final result = <String>{};
    for (final id in animals) {
      final prior = await localPredecessor(s, 'animal', id);
      if (prior != null) result.add(prior['id'] as String);
    }
    return result.toList();
  }

  Future<int> capturedRevision(
    InventorySnapshot s,
    String kind,
    String id,
    Object? expected, {
    String? parentId,
  }) async {
    final cached = await store!.readEntityRevision(
      s.userId,
      s.ownerId,
      project,
      kind,
      id,
    );
    captureScope(s);
    bool matches(Map<String, dynamic> entity) =>
        _sameJson(entity['data'], expected) &&
        (parentId == null || entity['parentId'] == parentId);
    if (cached != null && matches(cached)) return cached['revision'] as int;
    if (s.offline) {
      throw StateError(
        'Prepara este inventario con conexión para disponer de su revisión antes de editar',
      );
    }
    final entity = await _universal.entity(s.userId, s.ownerId, kind, id);
    captureScope(s);
    if (!matches(entity)) {
      throw StateError('La entidad cambió. Actualiza antes de editar');
    }
    await store!.saveEntityRevision(
      s.userId,
      s.ownerId,
      project,
      kind,
      id,
      entity,
      verify: () => captureScope(s),
    );
    return entity['revision'] as int;
  }

  Future<void> captureChange(
    InventorySnapshot s,
    String action,
    String id,
    Map<String, dynamic> changes, {
    Object? expected,
    String? parentId,
    List<String> dependencies = const [],
    String? operationId,
    bool managerOnly = false,
  }) async {
    final manager =
        managerOnly ||
        action.startsWith('animal.') ||
        action == 'config.update' ||
        [
          'event.update',
          'event.delete',
          'journey.finish',
          'journey.resume',
        ].contains(action) ||
        (action == 'event.create' &&
            ['note', 'other'].contains(changes['type'])) ||
        (action == 'journey.create' && changes['type'] == 'other');
    captureScope(s, manager: manager);
    final kind = action.split('.').first, create = action.endsWith('.create');
    final prior = create ? null : await localPredecessor(s, kind, id);
    final pending = <String>{...dependencies};
    String? revisionFrom;
    int? revision;
    if (prior != null) {
      revisionFrom = prior['id'] as String;
      pending.add(revisionFrom);
    } else if (!create) {
      revision = await capturedRevision(
        s,
        kind,
        id,
        expected,
        parentId: parentId,
      );
    }
    if (kind == 'animal') {
      final config = await localPredecessor(s, 'config', s.ownerId);
      if (config != null) pending.add(config['id'] as String);
    }
    await store!.transaction(() async {
      captureScope(s, manager: manager);
      if (!create) {
        final current = await localPredecessor(s, kind, id);
        if (current?['id'] != prior?['id']) {
          throw StateError(
            'Hay una captura nueva para esta entidad. Actualiza antes de guardar',
          );
        }
      }
      await _universal.enqueue(
        s.userId,
        s.ownerId,
        action,
        id,
        changes,
        revision: revision,
        dependencies: pending.toList(),
        revisionFrom: revisionFrom,
        operationId: operationId,
        verifyCapture: () => captureScope(s, manager: manager),
      );
      captureScope(s, manager: manager);
    });
    if (!s.offline) unawaited(syncEvents().catchError((Object _) {}));
  }

  Future<void> captureEventCorrection(
    InventorySnapshot s,
    String animalId,
    AnimalEvent event,
    Map<String, dynamic> fields,
    String reason, {
    bool remove = false,
    String? operationId,
  }) async {
    captureScope(s, manager: true);
    if (reason.trim().isEmpty || reason.trim().length > 2000) {
      throw StateError(
        'Indica el motivo de la corrección (máximo 2000 caracteres)',
      );
    }
    final row = s.records
        .where((r) => r['animal_id'] == animalId && r['deleted_at'] == null)
        .firstOrNull;
    final raw = row == null
        ? null
        : ((row['payload'] as Map)['events'] as List)
              .whereType<Map>()
              .where((e) => e['id'] == event.id)
              .firstOrNull;
    if (raw == null ||
        event.id.isEmpty ||
        raw['animalId'] != animalId ||
        raw['journeyId'] != null) {
      throw StateError(
        'Las actividades de jornada se corrigen desde su jornada',
      );
    }
    if (!s.animals.any((a) => a.id == animalId && a.active)) {
      throw StateError('Restaura el animal antes de corregir su historial');
    }
    if (!remove) {
      if (fields.isEmpty ||
          fields.keys.any(
            (k) => !['date', 'weight', 'product', 'notes'].contains(k),
          )) {
        throw StateError('Selecciona al menos un dato editable');
      }
      final date = (fields['date'] ?? raw['date'])?.toString() ?? '';
      final weight = fields.containsKey('weight')
          ? fields['weight']
          : raw['weight'];
      if (fields.containsKey('weight') && raw['type'] != 'weight') {
        throw StateError('Este evento no es un pesaje');
      }
      EventDraft(
        id: event.id,
        type: raw['type'] as String,
        date: date,
        weight: (weight as num?)?.toDouble(),
        product: (fields['product'] ?? raw['label'] ?? '').toString(),
        notes: (fields['notes'] ?? raw['notes'] ?? '').toString(),
      ).validate();
    }
    final dependencies = await animalDependencies(s, [animalId]);
    await captureChange(
      s,
      remove ? 'event.delete' : 'event.update',
      event.id,
      {'animalId': animalId, ...fields, 'reason': reason.trim()},
      expected: raw,
      parentId: animalId,
      dependencies: dependencies,
      operationId: operationId,
    );
  }

  Future<void> captureConfiguration(
    InventorySnapshot s,
    Map<String, dynamic> config, {
    String? operationId,
  }) async {
    captureScope(s, manager: true);
    validateAnimalConfiguration(config, s);
    await captureChange(
      s,
      'config.update',
      s.ownerId,
      {'config': config},
      expected: s.config.isEmpty ? null : s.config,
      operationId: operationId,
    );
  }

  Future<void> captureAnimal(
    InventorySnapshot s,
    String? id,
    Map<String, dynamic> incoming, {
    String? operationId,
    String? createId,
  }) async {
    captureScope(s, manager: true);
    final current = id == null
        ? null
        : s.records
              .where((r) => r['animal_id'] == id && r['deleted_at'] == null)
              .firstOrNull;
    if (id != null && current == null) throw StateError('Animal no disponible');
    final original = current == null
        ? <String, dynamic>{'status': 'Activo'}
        : Map<String, dynamic>.from(
            (current['payload'] as Map)['animal'] as Map,
          );
    final animal = {...original, ...incoming},
        config = AnimalFormConfig(s.config),
        animalId = id ?? createId ?? const Uuid().v4();
    final status = (animal['status'] ?? 'Activo').toString(),
        origin = (animal['originType'] ?? '').toString();
    for (final entry in incoming.entries) {
      final field = animalFields.where((f) => f.id == entry.key).firstOrNull;
      if (field == null ||
          !config.visible(field) ||
          !config.applies(field, status, origin)) {
        throw StateError('Campo no editable: ${entry.key}');
      }
      if (entry.value is String && (entry.value as String).length > 4000) {
        throw StateError('Texto demasiado largo');
      }
      if (field.kind == 'boolean' && entry.value is! bool) {
        throw StateError('Selecciona un valor válido para ${field.label}');
      }
      final options = config.choices(field.id);
      if (options.isNotEmpty &&
          entry.value is String &&
          (entry.value as String).isNotEmpty &&
          !options.containsKey(entry.value) &&
          entry.value != original[field.id]) {
        throw StateError('Opción no autorizada');
      }
    }
    for (final field in animalFields.where(
      (f) =>
          config.visible(f) &&
          config.applies(f, status, origin) &&
          config.requiredField(f),
    )) {
      if (field.id == 'estimatedAge' &&
          (animal['birthDate']?.toString() ?? '').isNotEmpty) {
        continue;
      }
      if (animal[field.id] == null || animal[field.id] == '') {
        throw StateError('Completa ${config.label(field)}');
      }
    }
    final birth = animal['birthDate']?.toString() ?? '';
    if (birth.isNotEmpty &&
        (DateTime.tryParse(birth) == null ||
            DateTime.parse(birth).isAfter(DateTime.now()))) {
      throw StateError('Fecha de nacimiento inválida');
    }
    if (birth.isNotEmpty && animal['estimatedAge'] is Map) {
      throw StateError('Indica fecha de nacimiento o edad estimada, no ambas');
    }
    final tag = (animal['tag'] ?? '').toString().trim().toLowerCase();
    if (id == null && tag.isEmpty) {
      throw StateError('Completa el número de arete');
    }
    if (tag.isNotEmpty &&
        s.animals.any(
          (a) => a.id != animalId && a.value('tag').toLowerCase() == tag,
        )) {
      throw StateError('Ya existe ese número de arete');
    }
    final parents = <String>[];
    for (final field in ['motherId', 'fatherId']) {
      final parent = animal[field]?.toString() ?? '';
      if (parent.isNotEmpty) {
        if (parent == animalId || !s.animals.any((a) => a.id == parent)) {
          throw StateError('Referencia de progenitor inválida');
        }
        parents.add(parent);
      }
    }
    final changes = {
      for (final entry in incoming.entries)
        if (id == null || !_sameJson(original[entry.key], entry.value))
          entry.key: entry.value,
    };
    if (changes.isEmpty) return;
    final dependencies = await animalDependencies(s, parents);
    if (id != null &&
        config.active(original['status']?.toString() ?? '') !=
            config.active(status)) {
      if (changes.keys.any(
        (key) => !['status', 'exitReason', 'exitNotes'].contains(key),
      )) {
        throw StateError(
          'Guarda los otros cambios de la ficha y después cambia su estado',
        );
      }
      final active = config.active(status);
      await captureChange(
        s,
        active ? 'animal.restore' : 'animal.archive',
        animalId,
        {
          'status': status,
          if (!active && changes.containsKey('exitReason'))
            'exitReason': changes['exitReason'],
          if (!active && changes.containsKey('exitNotes'))
            'exitNotes': changes['exitNotes'],
        },
        expected: original,
        dependencies: dependencies,
        operationId: operationId,
      );
    } else {
      if (id != null && !config.active(status)) {
        throw StateError('Restaura el animal antes de editar su ficha');
      }
      await captureChange(
        s,
        id == null ? 'animal.create' : 'animal.update',
        animalId,
        {'fields': changes},
        expected: id == null ? null : original,
        dependencies: dependencies,
        operationId: operationId,
      );
    }
  }

  Future<List<Journey>> projectedJourneys(
    InventorySnapshot s,
    List<Journey> confirmed,
  ) async {
    if (!supportsOfflineJourneys) return confirmed;
    final changes = await store!.localUniversalChanges(
      s.userId,
      s.ownerId,
      project,
    );
    captureScope(s);
    return projectJourneyChanges(confirmed, s, changes);
  }
}
