part of 'offline_store.dart';

/// Captures may depend on local work. They are not protocol operations until all
/// dependencies have a durable successful receipt. A sealed body never changes.
extension UniversalDraftStore on OfflineStore {
  Future<void> _createUniversalDrafts() async {
    await customStatement(
      'CREATE TABLE universal_drafts (user_id TEXT NOT NULL, owner_id TEXT NOT NULL, project TEXT NOT NULL, operation_id TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'waiting\', visible INTEGER NOT NULL DEFAULT 1, error TEXT, PRIMARY KEY(user_id,owner_id,operation_id))',
    );
    await customStatement(
      'CREATE TABLE entity_revisions (user_id TEXT NOT NULL, owner_id TEXT NOT NULL, project TEXT NOT NULL, kind TEXT NOT NULL, entity_id TEXT NOT NULL, saved_at INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(user_id,owner_id,project,kind,entity_id))',
    );
  }

  List<String> _draftScope(
    String user,
    String owner,
    String project,
    String id,
  ) => ['draft', user, owner, project, id];

  Future<void> saveEntityRevision(
    String user,
    String owner,
    String project,
    String kind,
    String id,
    Map<String, dynamic> entity, {
    void Function()? verify,
  }) async {
    final revision = entity['revision'];
    if (!['animal', 'event', 'journey', 'config'].contains(kind) ||
        revision is! int ||
        revision < 0 ||
        revision > 9007199254740991 ||
        (entity['data'] != null && entity['data'] is! Map)) {
      throw const FormatException('Revisión inválida');
    }
    await transaction(() async {
      verify?.call();
      await customStatement(
        'INSERT INTO entity_revisions(user_id,owner_id,project,kind,entity_id,saved_at,payload) VALUES(?,?,?,?,?,?,?) ON CONFLICT(user_id,owner_id,project,kind,entity_id) DO UPDATE SET saved_at=excluded.saved_at,payload=excluded.payload',
        [
          user,
          owner,
          project,
          kind,
          id,
          DateTime.now().millisecondsSinceEpoch,
          _seal(jsonEncode(entity), ['entity', user, owner, project, kind, id]),
        ],
      );
      verify?.call();
    });
  }

  Future<Map<String, dynamic>?> readEntityRevision(
    String user,
    String owner,
    String project,
    String kind,
    String id,
  ) async {
    final row = await customSelect(
      'SELECT saved_at,payload FROM entity_revisions WHERE user_id=? AND owner_id=? AND project=? AND kind=? AND entity_id=?',
      variables: [
        Variable.withString(user),
        Variable.withString(owner),
        Variable.withString(project),
        Variable.withString(kind),
        Variable.withString(id),
      ],
    ).getSingleOrNull();
    if (row == null) return null;
    final age =
        DateTime.now().millisecondsSinceEpoch - row.read<int>('saved_at');
    if (age < 0 || age > 86400000) return null;
    return Map<String, dynamic>.from(
      jsonDecode(
        _open(row.read<String>('payload'), [
          'entity',
          user,
          owner,
          project,
          kind,
          id,
        ]),
      ) as Map,
    );
  }

  Future<String?> draftOperationProject(
    String user,
    String owner,
    String id,
  ) async {
    final row = await customSelect(
      'SELECT project,payload FROM universal_drafts WHERE user_id=? AND owner_id=? AND operation_id=?',
      variables: [
        Variable.withString(user),
        Variable.withString(owner),
        Variable.withString(id),
      ],
    ).getSingleOrNull();
    if (row == null) return null;
    final project = row.read<String>('project');
    _open(row.read<String>('payload'), _draftScope(user, owner, project, id));
    return project;
  }

  Future<void> captureUniversalDraft(
    String user,
    String owner,
    String project,
    Map<String, dynamic> operation, {
    List<String> dependencies = const [],
    String? revisionFrom,
    void Function()? verify,
  }) async {
    operation = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(operation)) as Map,
    );
    dependencies = List<String>.of(dependencies);
    final id = operation['operationId'] as String;
    final create = (operation['action'] as String).endsWith('.create');
    if (operation['ownerId'] != owner ||
        project.isEmpty ||
        dependencies.contains(id) ||
        dependencies.toSet().length != dependencies.length ||
        revisionFrom != null && !dependencies.contains(revisionFrom) ||
        create && revisionFrom != null ||
        !create && revisionFrom == null && operation['baseRevision'] is! int) {
      throw StateError('Dependencias o revisión inválidas');
    }
    final draft = {
      'operation': operation,
      'dependencies': dependencies,
      'revisionFrom': revisionFrom,
    };
    await transaction(() async {
      verify?.call();
      final old = await customSelect(
        'SELECT project,payload FROM universal_drafts WHERE user_id=? AND owner_id=? AND operation_id=?',
        variables: [
          Variable.withString(user),
          Variable.withString(owner),
          Variable.withString(id),
        ],
      ).getSingleOrNull();
      final body = jsonEncode(draft);
      if (old != null) {
        if (old.read<String>('project') != project ||
            _open(
                  old.read<String>('payload'),
                  _draftScope(user, owner, project, id),
                ) !=
                body) {
          throw StateError('UUID reutilizado con otros datos');
        }
        return;
      }
      for (final dependency in dependencies) {
        if (await draftOperationProject(user, owner, dependency) != project) {
          throw StateError('Dependencia de otro ámbito o no disponible');
        }
      }
      await customStatement(
        'INSERT INTO universal_drafts(user_id,owner_id,project,operation_id,payload) VALUES(?,?,?,?,?)',
        [
          user,
          owner,
          project,
          id,
          _seal(body, _draftScope(user, owner, project, id)),
        ],
      );
      verify?.call();
    });
    await sealReadyDrafts(user, owner, project, verify: verify);
  }

  Future<void> sealReadyDrafts(
    String user,
    String owner,
    String project, {
    void Function()? verify,
  }) async {
    await transaction(() async {
      verify?.call();
      final rows = await customSelect(
        "SELECT operation_id,payload FROM universal_drafts WHERE user_id=? AND owner_id=? AND project=? AND state='waiting' ORDER BY rowid",
        variables: [
          Variable.withString(user),
          Variable.withString(owner),
          Variable.withString(project),
        ],
      ).get();
      for (final row in rows) {
        final id = row.read<String>('operation_id');
        final draft = jsonDecode(
          _open(
            row.read<String>('payload'),
            _draftScope(user, owner, project, id),
          ),
        ) as Map;
        final operation = Map<String, dynamic>.from(draft['operation'] as Map);
        var ready = true;
        String? blocked;
        int? receiptRevision;
        for (final dependency
            in (draft['dependencies'] as List).cast<String>()) {
          final source = await customSelect(
            'SELECT d.project,d.state AS draft_state,o.state,o.payload,o.receipt FROM universal_drafts d LEFT JOIN universal_outbox o ON o.user_id=d.user_id AND o.owner_id=d.owner_id AND o.operation_id=d.operation_id WHERE d.user_id=? AND d.owner_id=? AND d.operation_id=?',
            variables: [
              Variable.withString(user),
              Variable.withString(owner),
              Variable.withString(dependency),
            ],
          ).getSingleOrNull();
          if (source == null || source.read<String>('project') != project) {
            blocked = 'Dependencia no disponible en este proyecto';
            break;
          }
          final state =
              source.readNullable<String>('state') ??
              source.read<String>('draft_state');
          if (['conflict', 'rejected', 'blocked', 'archived'].contains(state)) {
            blocked = 'La operación $dependency requiere revisión ($state)';
            break;
          }
          if (state != 'confirmed') {
            ready = false;
            continue;
          }
          final receiptRaw = source.readNullable<String>('receipt');
          if (receiptRaw == null) {
            blocked = 'Confirmación sin recibo';
            break;
          }
          final receipt = parseEventReceipt(
            jsonDecode(
              _open(receiptRaw, [
                'universal',
                user,
                owner,
                dependency,
                'receipt',
              ]),
            ),
            dependency,
          );
          if (!['applied', 'duplicate'].contains(receipt['status'])) {
            blocked = 'Recibo de dependencia inválido';
            break;
          }
          if (draft['revisionFrom'] == dependency) {
            final parent = jsonDecode(
              _open(source.read<String>('payload'), [
                'universal',
                user,
                owner,
                dependency,
              ]),
            ) as Map;
            if (parent['entityId'] != operation['entityId'] ||
                (parent['action'] as String).split('.').first !=
                    (operation['action'] as String).split('.').first) {
              blocked = 'La revisión pertenece a otra entidad';
              break;
            }
            receiptRevision = receipt['revision'] as int;
          }
        }
        if (blocked != null) {
          await customStatement(
            "UPDATE universal_drafts SET state='blocked',error=? WHERE user_id=? AND owner_id=? AND operation_id=? AND state='waiting'",
            [
              _seal(blocked, [
                ..._draftScope(user, owner, project, id),
                'error',
              ]),
              user,
              owner,
              id,
            ],
          );
          continue;
        }
        if (!ready) continue;
        if (draft['revisionFrom'] != null) {
          if (receiptRevision == null) {
            throw StateError('No se confirmó la revisión requerida');
          }
          operation['baseRevision'] = receiptRevision;
        }
        verify?.call();
        await enqueueUniversal(user, owner, operation);
        await customStatement(
          "UPDATE universal_drafts SET state='sealed' WHERE user_id=? AND owner_id=? AND operation_id=? AND state='waiting'",
          [user, owner, id],
        );
      }
      verify?.call();
    });
  }

  Future<List<Map<String, dynamic>>> localUniversalChanges(
    String user,
    String owner,
    String project, {
    bool includeArchived = false,
  }) async {
    final rows = await customSelect(
      'SELECT d.operation_id,d.payload AS draft,d.state AS draft_state,d.error,d.visible,o.payload,o.state,o.receipt,o.resolved_by FROM universal_drafts d LEFT JOIN universal_outbox o ON o.user_id=d.user_id AND o.owner_id=d.owner_id AND o.operation_id=d.operation_id WHERE d.user_id=? AND d.owner_id=? AND d.project=? ORDER BY d.rowid',
      variables: [
        Variable.withString(user),
        Variable.withString(owner),
        Variable.withString(project),
      ],
    ).get();
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = row.read<String>('operation_id'),
          draft = jsonDecode(
            _open(
              row.read<String>('draft'),
              _draftScope(
                user,
                owner,
                project,
                row.read<String>('operation_id'),
              ),
            ),
          ) as Map;
      final state =
          row.readNullable<String>('state') ?? row.read<String>('draft_state');
      if (!includeArchived &&
          (row.read<int>('visible') == 0 || state == 'archived')) {
        continue;
      }
      final payload = row.readNullable<String>('payload'),
          receipt = row.readNullable<String>('receipt'),
          error = row.readNullable<String>('error');
      result.add({
        'id': id,
        'operation': payload == null
            ? draft['operation']
            : jsonDecode(_open(payload, ['universal', user, owner, id])),
        'state': state,
        'draft': payload == null,
        'dependencies': draft['dependencies'],
        'revisionFrom': draft['revisionFrom'],
        'receipt': receipt == null
            ? null
            : jsonDecode(
                _open(receipt, ['universal', user, owner, id, 'receipt']),
              ),
        'error': error == null
            ? null
            : _open(error, [..._draftScope(user, owner, project, id), 'error']),
        'resolvedBy': row.readNullable<String>('resolved_by'),
      });
    }
    return result;
  }

  Future<Map<String, dynamic>?> latestEntityChange(
    String user,
    String owner,
    String project,
    String kind,
    String id,
  ) async {
    return (await localUniversalChanges(user, owner, project)).where((entry) {
      final operation = entry['operation'] as Map;
      return operation['entityId'] == id &&
          (operation['action'] as String).startsWith('$kind.');
    }).lastOrNull;
  }

  Future<List<String>> confirmedDraftOperations(
    String user,
    String project, {
    Set<String>? kinds,
  }) async {
    final rows = await customSelect(
      "SELECT d.owner_id,d.operation_id,d.payload FROM universal_drafts d JOIN universal_outbox o ON o.user_id=d.user_id AND o.owner_id=d.owner_id AND o.operation_id=d.operation_id WHERE d.user_id=? AND d.project=? AND d.visible=1 AND o.state='confirmed'",
      variables: [Variable.withString(user), Variable.withString(project)],
    ).get();
    return [
      for (final row in rows)
        if (kinds == null ||
            kinds.contains(
              ((jsonDecode(
                        _open(
                          row.read<String>('payload'),
                          _draftScope(
                            user,
                            row.read<String>('owner_id'),
                            project,
                            row.read<String>('operation_id'),
                          ),
                        ),
                      ) as Map)['operation']['action']
                      as String)
                  .split('.')
                  .first,
            ))
          row.read<String>('operation_id'),
    ];
  }

  Future<void> acknowledgeDraftSnapshot(
    String user,
    String owner,
    String project,
    List<String> ids,
  ) async {
    for (final id in ids) {
      await customStatement(
        "UPDATE universal_drafts SET visible=0 WHERE user_id=? AND owner_id=? AND project=? AND operation_id=? AND EXISTS (SELECT 1 FROM universal_outbox o WHERE o.user_id=universal_drafts.user_id AND o.owner_id=universal_drafts.owner_id AND o.operation_id=universal_drafts.operation_id AND o.state='confirmed')",
        [user, owner, project, id],
      );
    }
  }

  Future<void> archiveUnsealedDraft(
    String user,
    String owner,
    String project,
    String id,
  ) async {
    await transaction(() async {
      if (await draftOperationProject(user, owner, id) != project) {
        throw StateError('Proyecto modificado');
      }
      await customStatement(
        "UPDATE universal_drafts SET state='archived' WHERE user_id=? AND owner_id=? AND project=? AND operation_id=? AND state IN ('waiting','blocked')",
        [user, owner, project, id],
      );
    });
    await sealReadyDrafts(user, owner, project);
  }
}
