import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import '../config/supabase_config.dart';
import '../database/offline_store.dart';
import 'background_session.dart';
import 'event_protocol.dart';
import 'universal_sync.dart';

const backgroundTaskName = 'ganaderov.sync.wake.v1';
const backgroundWorkId = 'ganaderov-sync-periodic-v1';

/// Guards both the RPC and Storage transports, including reads after a duplicate
/// upload. No headless Auth session, refresh token, redirect or foreign origin.
class _BackgroundHttpClient extends http.BaseClient {
  _BackgroundHttpClient(this.inner, this.origin, this.check, this.limit);
  final http.Client inner;
  final String origin;
  final Future<void> Function() check;
  final int limit;
  int operations = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await check();
    final path = request.url.path;
    final rpc = const {
      '/rest/v1/rpc/get_my_ranch_context',
      '/rest/v1/rpc/sync_read_entity',
      '/rest/v1/rpc/sync_apply_operation',
    }.contains(path);
    final storage =
        path.startsWith('/storage/v1/object/animal-photos/') ||
        path.startsWith('/storage/v1/object/authenticated/animal-photos/');
    if (request.url.origin != origin || (!rpc && !storage)) {
      throw const UniversalDeliveryPaused('Destino de entrega inválido');
    }
    if (path == '/rest/v1/rpc/sync_apply_operation') {
      if (operations >= limit) {
        throw const UniversalDeliveryPaused('Límite de entrega alcanzado');
      }
      operations++;
    }
    request.followRedirects = false;
    final response = await inner.send(request);
    await check();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const UniversalDeliveryPaused('Autorización de entrega revocada');
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const UniversalDeliveryPaused('Redirección de entrega rechazada');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

/// Runs the same encrypted queue and attachment/dependency processor as the UI.
/// The caller owns [store]; this function owns and closes [httpClient]. Keeping
/// the platform callback thin also permits adversarial transport tests on Linux.
Future<bool> deliverBackgroundQueues({
  required OfflineStore store,
  required String project,
  required String publishableKey,
  required Future<BackgroundCredential?> Function() readCredential,
  required bool universalEnabled,
  required bool eventRpcEnabled,
  http.Client? httpClient,
  DateTime Function()? clock,
  int maxOperations = 8,
}) async {
  final now = clock ?? DateTime.now;
  final initial = await readCredential();
  if (initial == null || initial.url != project || !initial.usableAt(now())) {
    httpClient?.close();
    return true;
  }
  if (!universalEnabled && !eventRpcEnabled) {
    httpClient?.close();
    return true;
  }
  final holder = const Uuid().v4();
  final deadline = now().add(const Duration(seconds: 110));
  var stopped = false;
  Future<void> check() async {
    final current = await readCredential();
    if (stopped ||
        current == null ||
        !initial.sameGrant(current) ||
        !current.usableAt(now()) ||
        !now().isBefore(deadline)) {
      stopped = true;
      throw const UniversalDeliveryPaused(
        'La sesión de entrega cambió o venció',
      );
    }
  }

  final transport = _BackgroundHttpClient(
    httpClient ?? http.Client(),
    Uri.parse(project).origin,
    check,
    math.max(1, math.min(8, maxOperations)),
  );
  final client = SupabaseClient(
    project,
    publishableKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    accessToken: () async {
      await check();
      return initial.accessToken;
    },
    httpClient: transport,
  );
  String? owner, role;
  Future<void> checkMembership(String user, String ranch) async {
    await check();
    if (user != initial.userId || (owner != null && owner != ranch)) {
      throw const UniversalDeliveryPaused('El ámbito de entrega cambió');
    }
    final context = await client
        .rpc('get_my_ranch_context')
        .timeout(const Duration(seconds: 20));
    await check();
    if (context is! Map ||
        context['status'] != 'active' ||
        context['owner_id'] != ranch ||
        !const ['owner', 'admin', 'worker'].contains(context['role']) ||
        (role != null && context['role'] != role)) {
      stopped = true;
      throw const UniversalDeliveryPaused('La membresía de entrega cambió');
    }
    if (!await store.acquireDeliveryLease(
      holder,
      now().millisecondsSinceEpoch,
    )) {
      throw const UniversalDeliveryPaused('Otra entrega conserva el bloqueo');
    }
  }

  try {
    if (!await store.acquireDeliveryLease(
      holder,
      now().millisecondsSinceEpoch,
    )) {
      return true;
    }
    await check();
    final context = await client
        .rpc('get_my_ranch_context')
        .timeout(const Duration(seconds: 20));
    await check();
    if (context is! Map ||
        context['status'] != 'active' ||
        context['owner_id'] is! String ||
        (context['owner_id'] as String).isEmpty ||
        !const ['owner', 'admin', 'worker'].contains(context['role'])) {
      return true;
    }
    owner = context['owner_id'] as String;
    role = context['role'] as String;
    if (universalEnabled) {
      final sync = UniversalSync(
        client,
        store,
        project,
        verifySession: (user) {
          if (stopped || user != initial.userId || !initial.usableAt(now())) {
            throw const UniversalDeliveryPaused('La sesión de entrega cambió');
          }
        },
        beforeSend: checkMembership,
        afterSend: (_, _) => check(),
      );
      await sync.flush(
        initial.userId,
        owner,
        holder,
        maxOperations: math.max(1, math.min(8, maxOperations)),
        requireProject: true,
      );
    }
    if (eventRpcEnabled && transport.operations < transport.limit) {
      final pending = await store.pending(initial.userId);
      for (final entry in pending) {
        if (transport.operations >= transport.limit) break;
        if (entry.ownerId != owner ||
            entry.state != 'pending' ||
            entry.operation == null ||
            entry.nextAt > now().millisecondsSinceEpoch) {
          continue;
        }
        final operation = entry.operation!, id = operation['operationId'];
        if (id is! String ||
            operation['action'] != 'event.create' ||
            operation['ownerId'] != owner ||
            operation['entityId'] != entry.draft.id) {
          continue;
        }
        try {
          await checkMembership(initial.userId, owner);
          final raw = await client
              .rpc('sync_apply_operation', params: {'p_operation': operation})
              .timeout(const Duration(seconds: 20));
          await check();
          final receipt = parseEventReceipt(raw, id),
              status = receipt['status'];
          if (status == 'applied' || status == 'duplicate') {
            await store.confirmRpc(entry, receipt);
          } else if (status == 'conflict' || status == 'rejected') {
            await store.stopRpc(
              entry,
              status as String,
              receipt['code'] as String,
            );
          } else {
            throw StateError('Entrega sin confirmar');
          }
        } on UniversalDeliveryPaused {
          rethrow;
        } catch (_) {
          await store.retry(
            entry,
            'Envío en segundo plano sin confirmar.',
            now()
                .add(
                  Duration(
                    seconds: math.min(
                      900,
                      30 * (1 << math.min(entry.attempts, 5)),
                    ),
                  ),
                )
                .millisecondsSinceEpoch,
          );
          return false;
        }
      }
    }
    return true;
  } on UniversalDeliveryPaused {
    // Expiry/logout/revocation is a pause, not a rejection of a valid operation.
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      await store.releaseDeliveryLease(holder);
    } finally {
      await client.dispose();
      transport.close();
    }
  }
}

@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != backgroundTaskName || !BackgroundSession.enabled) return true;
    final OfflineStore store;
    try {
      store = await OfflineStore.protected();
    } catch (_) {
      return false;
    }
    try {
      return await deliverBackgroundQueues(
        store: store,
        project: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
        readCredential: BackgroundSession.read,
        universalEnabled: SupabaseConfig.universalSyncEnabled,
        eventRpcEnabled: SupabaseConfig.eventRpcEnabled,
      );
    } finally {
      await store.close();
    }
  });
}

Future<void> configureBackgroundSync() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(backgroundCallbackDispatcher);
  if (!BackgroundSession.enabled) {
    await Workmanager().cancelByUniqueName(backgroundWorkId);
    await BackgroundSession.clear();
    return;
  }
  await Workmanager().registerPeriodicTask(
    backgroundWorkId,
    backgroundTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
