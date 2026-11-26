import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/auth_gateway.dart';
import '../../features/auth/presentation/pages/auth_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';

String? authRedirect({required bool signedIn, required bool recovering, required String path}) {
  if (recovering && signedIn) return path == '/reset' ? null : '/reset';
  final public = const ['/login', '/register', '/recovery'].contains(path);
  if (!signedIn) return public ? null : '/login';
  if (public || path == '/reset' || path == '/auth/callback' || path == '/callback') return '/';
  return null;
}
abstract final class AppRouter {
  static GoRouter create(AuthGateway auth) => GoRouter(
    refreshListenable: auth,
    redirect: (context, state) => authRedirect(signedIn: auth.signedIn, recovering: auth.recovering, path: state.uri.path),
    routes: [
      for (final entry in { '/login': AuthMode.login, '/register': AuthMode.register, '/recovery': AuthMode.recovery, '/reset': AuthMode.reset }.entries)
        GoRoute(path: entry.key, builder: (context, state) => AuthPage(
          key: ValueKey(entry.key), auth: auth, mode: entry.value,
          onMode: (mode) => context.go(switch (mode) { AuthMode.login => '/login', AuthMode.register => '/register', AuthMode.recovery => '/recovery', AuthMode.reset => '/reset' }),
        )),
      GoRoute(path: '/', builder: (context, state) => DashboardPage(auth: auth)),
    ],
  );
}
