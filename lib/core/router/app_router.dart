import 'package:flutter/foundation.dart';
import '../sync/event_outbox.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/auth_gateway.dart';
import '../../features/auth/presentation/pages/auth_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/dashboard/domain/dashboard_summary.dart';
import '../../features/livestock/presentation/pages/livestock_page.dart';
import '../../features/livestock/domain/inventory.dart';
import '../../features/journeys/presentation/pages/journeys_page.dart';
import '../../features/analysis/presentation/pages/analysis_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/settings/domain/ranch.dart';
import '../../shared/widgets/main_shell.dart';

String? authRedirect({required bool signedIn, required bool recovering, required String path}) {
  if (recovering && signedIn) return path == '/reset' ? null : '/reset';
  final public = const ['/login', '/register', '/recovery'].contains(path);
  if (!signedIn) return public ? null : '/login';
  if (public || path == '/reset' || path == '/auth/callback' || path == '/callback') return '/';
  return null;
}

abstract final class AppRouter {
  static GoRouter create(AuthGateway auth, DashboardRepository dashboardRepository, InventoryRepository inventoryRepository, RanchRepository ranchRepository) => GoRouter(
    refreshListenable: auth,
    redirect: (context, state) => authRedirect(signedIn: auth.signedIn, recovering: auth.recovering, path: state.uri.path),
    routes: [
      for (final entry in {'/login': AuthMode.login, '/register': AuthMode.register, '/recovery': AuthMode.recovery, '/reset': AuthMode.reset}.entries)
        GoRoute(path: entry.key, builder: (context, state) => AuthPage(
          key: ValueKey(entry.key), auth: auth, mode: entry.value,
          onMode: (mode) => context.go(switch (mode) { AuthMode.login => '/login', AuthMode.register => '/register', AuthMode.recovery => '/recovery', AuthMode.reset => '/reset' }),
        )),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(navigationShell: shell, auth: auth),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (context, state) => DashboardPage(repository: dashboardRepository, auth: auth, ranchChanges: ranchRepository))]),
          StatefulShellBranch(routes: [GoRoute(path: '/ganado', builder: (context, state) => LivestockPage(repository: inventoryRepository, auth: auth, ranchChanges: ranchRepository))]),
          StatefulShellBranch(routes: [GoRoute(path: '/jornadas', builder: (context, state) => JourneysPage(inventory: inventoryRepository, auth: auth, changes: ranchRepository))]),
          StatefulShellBranch(routes: [GoRoute(path: '/analisis', builder: (context, state) => AnalysisPage(repository: inventoryRepository, auth: auth, changes: ranchRepository))]),
          StatefulShellBranch(routes: [GoRoute(path: '/ajustes', builder: (context, state) => SettingsPage(auth: auth, ranchRepository: ranchRepository, outbox: inventoryRepository is OutboxAccess ? inventoryRepository as OutboxAccess : null))]),
        ],
      ),
    ],
  );
}
