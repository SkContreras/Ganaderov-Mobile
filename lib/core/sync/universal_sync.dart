import 'dart:convert';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/offline_store.dart';
import 'event_protocol.dart';
import 'incremental_v1.dart';
import 'manual_resolution.dart';

const universalActions = {
  'animal.create',
  'animal.update',
  'animal.archive',
  'animal.restore',
  'event.create',
  'event.update',
  'event.delete',
  'photo.create',
  'photo.delete',
  'journey.create',
  'journey.attend',
  'journey.finish',
  'journey.resume',
  'config.update',
  'forecast.create',
  'forecast.delete',
  'animal.target.update',
  'journey.add_animals',
  'photo.crop',
  'photo.primary',
};

class UniversalDeliveryPaused implements Exception {
  const UniversalDeliveryPaused([this.message = 'Entrega pausada']);
  final String message;
  @override
  String toString() => message;
}

class UniversalSync {
  UniversalSync(
    this.client,
    this.store,
    this.project, {
    this.verifySession,
    this.beforeSend,
    this.afterSend,
  });
  final SupabaseClient client;
  final OfflineStore store;
  final String project;
  final void Function(String user)? verifySession;
  final Future<void> Function(String user, String owner)? beforeSend, afterSend;
  void verify(String user) {
    if (verifySession != null) {
      verifySession!(user);
      return;
    }
    if (client.auth.currentUser?.id != user ||
        client.auth.currentSession == null) {
      throw const UniversalDeliveryPaused('La sesión cambió');
    }
  }

  Future<void> _before(String user, String owner) async {
    verify(user);
    await beforeSend?.call(user, owner);
    verify(user);
  }

  Future<void> _after(String user, String owner) async {
    await afterSend?.call(user, owner);
    verify(user);
  }

  Future<Map<String, dynamic>> entity(
    String user,
    String owner,
    String kind,
    String id,
  ) async {
    await _before(user, owner);
    final raw = await client
        .rpc(
          'sync_read_entity',
          params: {'p_owner': owner, 'p_kind': kind, 'p_id': id},
        )
        .timeout(const Duration(seconds: 20));
    await _after(user, owner);
    if (raw is! Map || raw['revision'] is! int) {
      throw const FormatException('Revisión inválida');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<String> enqueue(
    String user,
    String owner,
    String action,
    String id,
    Map<String, dynamic> changes, {
    int? revision,
    String? attachment,
    Map<String, dynamic>? expectedPhoto,
    void Function()? verifyPhoto,
    void Function()? verifyCapture,
    List<String> dependencies = const [],
    String? revisionFrom,
    String? operationId,
  }) async {
    verify(user);
    changes = Map<String, dynamic>.from(jsonDecode(jsonEncode(changes)) as Map);
    if (!universalActions.contains(action) ||
        id.isEmpty ||
        (action.endsWith('.create') &&
            (revision != null || revisionFrom != null)) ||
        (!action.endsWith('.create') &&
            revision == null &&
            revisionFrom == null)) {
      throw ArgumentError('Operación inválida');
    }
    if (!action.startsWith('photo.') &&
        (operationId != null || action.endsWith('.create'))) {
      final prior =
          (await store.localUniversalChanges(
            user,
            owner,
            project,
            includeArchived: true,
          )).where((entry) {
            final body = entry['operation'] as Map;
            return operationId != null
                ? entry['id'] == operationId
                : body['action'] == action && body['entityId'] == id;
          }).firstOrNull;
      if (prior != null) {
        final body = prior['operation'] as Map;
        if (body['action'] != action ||
            body['entityId'] != id ||
            !sameConflictValue(body['changes'], changes)) {
          throw StateError('Identificador reutilizado con otros datos');
        }
        return prior['id'] as String;
      }
    }
    final op = operationId ?? const Uuid().v4();
    final operation = <String, dynamic>{
      'protocolVersion': 1,
      'operationId': op,
      'action': action,
      'entityId': id,
      'ownerId': owner,
      'deviceId': await store.installationId(),
      'baseRevision': revision,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'changes': changes,
    };
    verify(user);
    if (action.startsWith('photo.')) {
      if (dependencies.isNotEmpty || revisionFrom != null) {
        throw StateError('Dependencia de fotografía no disponible');
      }
      await store.enqueuePhotoOperation(
        user,
        owner,
        project,
        operation,
        expected: expectedPhoto,
        attachment: attachment,
        verify: () {
          verify(user);
          verifyPhoto?.call();
        },
      );
    } else {
      if (attachment != null) throw StateError('Adjunto inesperado');
      await store.captureUniversalDraft(
        user,
        owner,
        project,
        operation,
        dependencies: dependencies,
        revisionFrom: revisionFrom,
        verify: () {
          verify(user);
          verifyCapture?.call();
        },
      );
    }
    return op;
  }

  Future<void> flush(
    String user,
    String owner,
    String holder, {
    bool manual = false,
    int maxOperations = 100,
    bool requireProject = false,
  }) async {
    final visited = <String>{};
    var sent = 0;
    while (sent < maxOperations) {
      verify(user);
      await store.sealReadyDrafts(
        user,
        owner,
        project,
        verify: () => verify(user),
      );
      final candidates = (await store.universalPending(user, owner)).where(
        (row) =>
            !visited.contains(row['id']) &&
            (manual ||
                (row['nextAt'] as int) <=
                    DateTime.now().millisecondsSinceEpoch),
      );
      final row = candidates.firstOrNull;
      if (row == null) break;
      if (!await store.acquireDeliveryLease(
        holder,
        DateTime.now().millisecondsSinceEpoch,
      )) {
        break;
      }
      final op = Map<String, dynamic>.from(row['operation'] as Map),
          id = row['id'] as String;
      visited.add(id);
      try {
        if (op['operationId'] != id ||
            op['ownerId'] != owner ||
            !universalActions.contains(op['action'])) {
          throw const FormatException('Ámbito inválido');
        }
        final operationProject = await store.draftOperationProject(
          user,
          owner,
          id,
        );
        if (operationProject != null && operationProject != project) continue;
        if (requireProject &&
            operationProject == null &&
            !(op['action'] as String).startsWith('photo.')) {
          throw const UniversalDeliveryPaused(
            'La operación antigua requiere verificar su proyecto en primer plano',
          );
        }
        if ((op['action'] as String).startsWith('photo.')) {
          final capturedProject = await store.photoOperationProject(
            user,
            owner,
            id,
          );
          if (capturedProject == null) {
            await store.settleUniversal(user, owner, id, 'rejected', {
              'protocolVersion': 1,
              'operationId': id,
              'status': 'rejected',
              'code': 'LOCAL_PHOTO_PROJECT_UNVERIFIED',
              'serverReceivedAt': DateTime.now().toUtc().toIso8601String(),
            }, 0);
            continue;
          }
          if (capturedProject != project) continue;
        }
        if (op['action'] == 'photo.create') {
          final c = op['changes'] as Map,
              path = '$owner/${c['animalId']}/${op['entityId']}';
          // Decode one pending original at a time, not the whole upload queue.
          final bytes = base64Decode(
            (await store.universalAttachment(user, owner, id)) ??
                (throw StateError('Original no disponible')),
          );
          await _before(user, owner);
          try {
            await client.storage
                .from('animal-photos')
                .uploadBinary(
                  path,
                  bytes,
                  fileOptions: FileOptions(
                    contentType: c['mime'] as String,
                    upsert: false,
                  ),
                )
                .timeout(const Duration(seconds: 20));
            await _after(user, owner);
          } on UniversalDeliveryPaused {
            rethrow;
          } catch (_) {
            await _before(user, owner);
            final old = await client.storage
                .from('animal-photos')
                .download(path)
                .timeout(const Duration(seconds: 20));
            await _after(user, owner);
            if (base64Encode(old) != base64Encode(bytes)) rethrow;
          }
        }
        await _before(user, owner);
        sent++;
        final raw = await client
            .rpc('sync_apply_operation', params: {'p_operation': op})
            .timeout(const Duration(seconds: 20));
        await _after(user, owner);
        final receipt = parseEventReceipt(raw, id), status = receipt['status'];
        if (status == 'applied' || status == 'duplicate') {
          await store.settleUniversal(user, owner, id, 'confirmed', receipt, 0);
        } else if (status == 'conflict' || status == 'rejected') {
          await store.settleUniversal(
            user,
            owner,
            id,
            status as String,
            receipt,
            0,
          );
        } else {
          throw StateError('Reintentar');
        }
      } on UniversalDeliveryPaused {
        rethrow;
      } catch (_) {
        await store.settleUniversal(
          user,
          owner,
          id,
          'pending',
          null,
          DateTime.now().millisecondsSinceEpoch +
              1000 *
                  math.min(
                    900,
                    30 * (1 << math.min(row['attempts'] as int, 5)),
                  ),
        );
        break;
      }
    }
    await store.sealReadyDrafts(
      user,
      owner,
      project,
      verify: () => verify(user),
    );
  }

  Future<Map<String, dynamic>> pull(String user, String owner) async {
    var previous = await store.readMirror(user, owner, project), resets = 0;
    Map<String, dynamic> empty() => {
      'ownerId': owner,
      'epoch': null,
      'cursor': 0,
      'records': [],
    };
    Future<Map<String, dynamic>> page(Map<String, dynamic> base) async {
      verify(user);
      final raw = await client
          .rpc(
            'sync_pull_changes',
            params: {
              'p_owner': owner,
              'p_after': base['cursor'],
              'p_epoch': base['epoch'],
              'p_limit': 50,
            },
          )
          .timeout(const Duration(seconds: 20));
      verify(user);
      return Map<String, dynamic>.from(raw as Map);
    }

    for (var count = 0; count < 2000; count++) {
      var base = previous ?? empty(), data = await page(base);
      if (data['status'] == 'reset_required') {
        if (previous == null || ++resets > 2) {
          throw StateError('No se pudo restablecer el cursor');
        }
        base = empty();
        data = await page(base);
      }
      final next = applyChangePage(base, data, owner);
      verify(user);
      if (await store.commitMirror(user, owner, project, previous, next)) {
        previous = next;
        if (data['hasMore'] == false) return next;
      } else {
        previous = await store.readMirror(user, owner, project);
      }
    }
    throw StateError('Descarga incompleta; cursor conservado');
  }
}
