import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'core/sync/background_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/sync/event_outbox.dart';
import 'core/database/offline_store.dart';
import 'core/config/supabase_config.dart';
import 'features/auth/data/supabase_auth_gateway.dart';
import 'features/dashboard/data/supabase_dashboard_repository.dart';
import 'features/livestock/data/supabase_inventory_repository.dart';
import 'features/settings/data/supabase_ranch_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _StartupApp());
}

class _StartupApp extends StatefulWidget {
  const _StartupApp();

  @override
  State<_StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<_StartupApp> {
  late Future<Widget> _startup;
  SupabaseClient? _client;

  @override
  void initState() {
    super.initState();
    _startup = _initializeApp();
  }

  Future<Widget> _initializeApp() async {
    try {
      final client = await _initializeSupabase();
      final store = await OfflineStore.protected(provision: true);
      final currentUser = client.auth.currentUser;
      if (currentUser == null) {
        await store.purgeAll();
      } else {
        await store.retainOnly(currentUser.id);
      }

      final ranch = SupabaseRanchRepository(client);
      final inventory = SupabaseInventoryRepository(
        client,
        store: store,
        onSynced: ranch.invalidate,
        eventRpcEnabled: SupabaseConfig.eventRpcEnabled,
        journeyRpcEnabled: SupabaseConfig.journeyRpcEnabled,
        universalEnabled: SupabaseConfig.universalSyncEnabled,
        incrementalEnabled: SupabaseConfig.incrementalSyncEnabled,
        project: SupabaseConfig.url,
      );
      final sync = ForegroundSync(inventory.syncEvents);
      sync.start();
      // Scheduling failures must not prevent login or local data access.
      unawaited(configureBackgroundSync().catchError((Object _) {}));

      return ProviderScope(
        child: GanaderovApp(
          auth: SupabaseAuthGateway(
            client,
            clearCache: store.purgeAll,
            retainCacheFor: store.retainOnly,
          ),
          dashboardRepository: SupabaseDashboardRepository(inventory),
          inventoryRepository: inventory,
          ranchRepository: ranch,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Ganaderov startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<SupabaseClient> _initializeSupabase() async {
    if (_client != null) return _client!;
    await SupabaseConfig.initialize();
    return _client = Supabase.instance.client;
  }

  void _retry() {
    setState(() {
      _startup = _initializeApp();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
        future: _startup,
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return MaterialApp(
              title: 'Ganaderov',
              theme: ThemeData.light(),
              home: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'No se pudo iniciar Ganaderov',
                            style: ThemeData.light().textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Revisa tu conexión e inténtalo de nuevo. '
                            'Si el problema continúa, contacta con soporte.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          SelectableText(
                            'Detalle técnico: ${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return MaterialApp(
              title: 'Ganaderov',
              theme: ThemeData.light(),
              home: const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Iniciando Ganaderov…'),
                    ],
                  ),
                ),
              ),
            );
          }

          return snapshot.requireData;
        },
      );
}
