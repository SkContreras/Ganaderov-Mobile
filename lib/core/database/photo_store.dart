part of 'offline_store.dart';

/// Scoped, authenticated local photo data. Originals are immutable; metadata and
/// UI projections are separate so a preview never becomes a server revision.
extension PhotoStore on OfflineStore {
  static const maxOriginalBytes = 10 * 1024 * 1024;
  static const originalCacheBudget = 50 * 1024 * 1024;

  Future<void> _createPhotoCache() async {
    await _addColumnIfMissing('inventory_cache', 'project', 'TEXT');
    await customStatement(
      'CREATE TABLE IF NOT EXISTS photo_metadata (user_id TEXT NOT NULL,owner_id TEXT NOT NULL,project TEXT NOT NULL,photo_id TEXT NOT NULL,saved_at INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(user_id,owner_id,project,photo_id))',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS photo_originals (user_id TEXT NOT NULL,owner_id TEXT NOT NULL,project TEXT NOT NULL,path TEXT NOT NULL,accessed_at INTEGER NOT NULL,byte_length INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(user_id,owner_id,project,path))',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS photo_local_changes (user_id TEXT NOT NULL,owner_id TEXT NOT NULL,project TEXT NOT NULL,animal_id TEXT NOT NULL,operation_id TEXT NOT NULL,PRIMARY KEY(user_id,owner_id,project,operation_id))',
    );
  }

  Future<void> _purgePhotoCache(String where, List<Object?> arguments) async {
    await customStatement('DELETE FROM photo_metadata WHERE $where', arguments);
    await customStatement(
      'DELETE FROM photo_originals WHERE $where',
      arguments,
    );
    // Outbox and its projection references survive logout/revocation. They are
    // inaccessible without a fresh scoped inventory and may need later review.
  }

  bool _samePhotoJson(Object? a, Object? b) {
    if (a is Map && b is Map)
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _samePhotoJson(a[key], b[key]),
          );
    if (a is List && b is List)
      return a.length == b.length &&
          List.generate(
            a.length,
            (i) => _samePhotoJson(a[i], b[i]),
          ).every((same) => same);
    return a == b;
  }

  Future<void> savePhotoMetadata(
    String user,
    String owner,
    String project,
    String photoId,
    Map<String, dynamic> entity, {
    void Function()? verify,
  }) async {
    final data = entity['data'],
        revision = entity['revision'],
        animalId = entity['parentId'];
    if (revision is! int ||
        revision < 1 ||
        revision > 9007199254740991 ||
        animalId is! String ||
        data is! Map ||
        data['id'] != photoId ||
        (data['animalId'] != null && data['animalId'] != animalId) ||
        data['storagePath'] != '$owner/$animalId/$photoId') {
      throw const FormatException('Revisión de fotografía inválida');
    }
    await transaction(() async {
      verify?.call();
      await customStatement(
        'INSERT INTO photo_metadata(user_id,owner_id,project,photo_id,saved_at,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(user_id,owner_id,project,photo_id) DO UPDATE SET saved_at=excluded.saved_at,payload=excluded.payload',
        [
          user,
          owner,
          project,
          photoId,
          DateTime.now().millisecondsSinceEpoch,
          _seal(jsonEncode(entity), [
            'photo-metadata',
            user,
            owner,
            project,
            photoId,
          ]),
        ],
      );
      verify?.call();
    });
  }

  Future<Map<String, dynamic>?> readPhotoMetadata(
    String user,
    String owner,
    String project,
    String photoId,
  ) async {
    final row = await customSelect(
      'SELECT saved_at,payload FROM photo_metadata WHERE user_id=? AND owner_id=? AND project=? AND photo_id=?',
      variables: [
        Variable.withString(user),
        Variable.withString(owner),
        Variable.withString(project),
        Variable.withString(photoId),
      ],
    ).getSingleOrNull();
    if (row == null) return null;
    final age =
        DateTime.now().millisecondsSinceEpoch - row.read<int>('saved_at');
    if (age < 0 || age > 86400000) return null;
    return Map<String, dynamic>.from(
      jsonDecode(
        _open(row.read<String>('payload'), [
          'photo-metadata',
          user,
          owner,
          project,
          photoId,
        ]),
      ) as Map,
    );
  }

  Future<void> savePhotoOriginal(
    String user,
    String owner,
    String project,
    String path,
    Uint8List bytes, {
    int budget = originalCacheBudget,
    void Function()? verify,
  }) async {
    if (!path.startsWith('$owner/') ||
        bytes.isEmpty ||
        bytes.length > maxOriginalBytes)
      throw ArgumentError('Original inválido');
    final payload = _seal(base64Encode(bytes), [
      'photo-original',
      user,
      owner,
      project,
      path,
    ]);
    if (payload.length > budget) return;
    await transaction(() async {
      verify?.call();
      await customStatement(
        'INSERT INTO photo_originals(user_id,owner_id,project,path,accessed_at,byte_length,payload) VALUES(?,?,?,?,?,?,?) ON CONFLICT(user_id,owner_id,project,path) DO UPDATE SET accessed_at=excluded.accessed_at,byte_length=excluded.byte_length,payload=excluded.payload',
        [
          user,
          owner,
          project,
          path,
          DateTime.now().microsecondsSinceEpoch,
          payload.length,
          payload,
        ],
      );
      var total = (await customSelect(
        'SELECT COALESCE(SUM(byte_length),0) AS total FROM photo_originals',
      ).getSingle()).read<int>('total');
      // Bound encrypted on-disk bytes globally, not once per ranch or account.
      final victims = await customSelect(
        'SELECT rowid,byte_length FROM photo_originals ORDER BY accessed_at,rowid',
      ).get();
      for (final victim in victims) {
        if (total <= budget) break;
        await customStatement('DELETE FROM photo_originals WHERE rowid=?', [
          victim.read<int>('rowid'),
        ]);
        total -= victim.read<int>('byte_length');
      }
      verify?.call();
    });
  }

  Future<Uint8List?> readPhotoOriginal(
    String user,
    String owner,
    String project,
    String path,
  ) async {
    final row = await customSelect(
      'SELECT payload FROM photo_originals WHERE user_id=? AND owner_id=? AND project=? AND path=?',
      variables: [
        Variable.withString(user),
        Variable.withString(owner),
        Variable.withString(project),
        Variable.withString(path),
      ],
    ).getSingleOrNull();
    if (row == null) return null;
    final bytes = base64Decode(
      _open(row.read<String>('payload'), [
        'photo-original',
        user,
        owner,
        project,
        path,
      ]),
    );
    if (bytes.isEmpty || bytes.length > maxOriginalBytes)
      throw const FormatException('Original inválido');
    await customStatement(
      'UPDATE photo_originals SET accessed_at=? WHERE user_id=? AND owner_id=? AND project=? AND path=?',
      [DateTime.now().microsecondsSinceEpoch, user, owner, project, path],
    );
    return bytes;
  }

  Future<void> enqueuePhotoOperation(
    String user,
    String owner,
    String project,
    Map<String, dynamic> operation, {
    Map<String, dynamic>? expected,
    String? attachment,
    required void Function() verify,
  }) => transaction(() async {
    verify();
    final animalId = (operation['changes'] as Map)['animalId'];
    final current = await read(user, project: project);
    if (current == null ||
        current.ownerId != owner ||
        !['owner', 'admin'].contains(current.role))
      throw StateError('Actualiza el inventario antes de editar fotografías.');
    final row = current.records
        .where((r) => r['animal_id'] == animalId && r['deleted_at'] == null)
        .firstOrNull;
    if (row == null) throw StateError('Animal no disponible.');
    // SQLite serializes this check with insertion across isolates/processes.
    final unsettled = await customSelect(
      "SELECT operation_id,payload FROM universal_outbox WHERE user_id=? AND owner_id=? AND state IN ('pending','conflict','rejected')",
      variables: [Variable.withString(user), Variable.withString(owner)],
    ).get();
    for (final pending in unsettled) {
      final id = pending.read<String>('operation_id');
      final op = jsonDecode(
        _open(pending.read<String>('payload'), ['universal', user, owner, id]),
      ) as Map;
      if ((op['action'] as String).startsWith('photo.') &&
          (op['changes'] as Map)['animalId'] == animalId)
        throw StateError(
          'Hay un cambio de fotografía pendiente para este animal. Sincronízalo o revísalo en Ajustes antes de otro cambio.',
        );
    }
    final waiting = await customSelect(
      "SELECT 1 FROM photo_local_changes p JOIN universal_outbox o ON o.user_id=p.user_id AND o.owner_id=p.owner_id AND o.operation_id=p.operation_id WHERE p.user_id=? AND p.owner_id=? AND p.project=? AND p.animal_id=? AND o.state='confirmed'",
      variables: [
        Variable.withString(user),
        Variable.withString(owner),
        Variable.withString(project),
        Variable.withString(animalId as String),
      ],
    ).get();
    if (waiting.isNotEmpty)
      throw StateError(
        'El cambio está confirmado. Actualiza la galería antes de otro cambio.',
      );
    if (operation['action'] != 'photo.create') {
      final photoId = operation['entityId'] as String;
      final metadata = await readPhotoMetadata(user, owner, project, photoId);
      final photos = (row['payload'] as Map)['photos'];
      final selected = photos is List
          ? photos.whereType<Map>().where((p) => p['id'] == photoId).firstOrNull
          : null;
      if (expected == null ||
          metadata == null ||
          metadata['parentId'] != animalId ||
          metadata['revision'] != operation['baseRevision'] ||
          !_samePhotoJson(metadata['data'], expected) ||
          !_samePhotoJson(selected, expected))
        throw StateError(
          'No hay una revisión local vigente. Abre la fotografía con conexión antes de editarla.',
        );
      if (operation['action'] == 'photo.primary') {
        final primary = (photos as List)
            .whereType<Map>()
            .where((p) => p['primary'] == true)
            .firstOrNull;
        if (primary?['id'] !=
            (operation['changes'] as Map)['previousPrimaryId'])
          throw StateError(
            'La fotografía principal cambió. Actualiza la galería.',
          );
      }
    }
    verify();
    await enqueueUniversal(user, owner, operation, attachment: attachment);
    await customStatement(
      'INSERT INTO photo_local_changes(user_id,owner_id,project,animal_id,operation_id) VALUES(?,?,?,?,?)',
      [user, owner, project, animalId, operation['operationId']],
    );
    verify();
  });

  Future<List<Map<String, dynamic>>> photoChanges(
    String user,
    String owner,
    String project,
  ) async {
    final rows = await customSelect(
      'SELECT o.operation_id,o.payload,o.state FROM photo_local_changes p JOIN universal_outbox o ON o.user_id=p.user_id AND o.owner_id=p.owner_id AND o.operation_id=p.operation_id WHERE p.user_id=? AND p.owner_id=? AND p.project=? ORDER BY o.rowid',
      variables: [
        Variable.withString(user),
        Variable.withString(owner),
        Variable.withString(project),
      ],
    ).get();
    return rows
        .map(
          (row) => <String, dynamic>{
            'operation': jsonDecode(
              _open(row.read<String>('payload'), [
                'universal',
                user,
                owner,
                row.read<String>('operation_id'),
              ]),
            ),
            'state': row.read<String>('state'),
          },
        )
        .toList();
  }

  Future<String?> photoOperationProject(
    String user,
    String owner,
    String id,
  ) async {
    final row = await customSelect(
      'SELECT project FROM photo_local_changes WHERE user_id=? AND owner_id=? AND operation_id=?',
      variables: [
        Variable.withString(user),
        Variable.withString(owner),
        Variable.withString(id),
      ],
    ).getSingleOrNull();
    return row?.read<String>('project');
  }

  Future<Uint8List?> pendingPhotoOriginal(
    String user,
    String owner,
    String project,
    String photoId,
  ) async {
    for (final entry in await photoChanges(user, owner, project)) {
      final operation = entry['operation'] as Map;
      if (operation['action'] == 'photo.create' &&
          operation['entityId'] == photoId &&
          entry['state'] == 'pending') {
        final encoded = await universalAttachment(
          user,
          owner,
          operation['operationId'] as String,
        );
        if (encoded == null) return null;
        final bytes = base64Decode(encoded);
        if (bytes.length > maxOriginalBytes)
          throw const FormatException('Original inválido');
        return bytes;
      }
    }
    return null;
  }

  Future<List<String>> confirmedPhotoOperations(
    String user,
    String project,
  ) async {
    final rows = await customSelect(
      "SELECT p.operation_id FROM photo_local_changes p JOIN universal_outbox o ON o.user_id=p.user_id AND o.owner_id=p.owner_id AND o.operation_id=p.operation_id WHERE p.user_id=? AND p.project=? AND o.state='confirmed'",
      variables: [Variable.withString(user), Variable.withString(project)],
    ).get();
    return rows.map((row) => row.read<String>('operation_id')).toList();
  }

  /// Only operations already acknowledged before requesting this successful
  /// snapshot may retire their preview. This does not depend on the wall clock.
  Future<void> acknowledgePhotoSnapshot(
    String user,
    String owner,
    String project,
    List<String> confirmedBeforeLoad,
  ) => transaction(() async {
    for (final id in confirmedBeforeLoad) {
      await customStatement(
        "DELETE FROM photo_local_changes WHERE user_id=? AND owner_id=? AND project=? AND operation_id=? AND EXISTS(SELECT 1 FROM universal_outbox o WHERE o.user_id=? AND o.owner_id=? AND o.operation_id=? AND o.state='confirmed')",
        [user, owner, project, id, user, owner, id],
      );
    }
  });
}
