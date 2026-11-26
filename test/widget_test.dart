import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/app.dart';
import 'package:ganaderov/features/settings/presentation/pages/settings_page.dart';
import 'package:ganaderov/core/router/app_router.dart';
import 'package:ganaderov/features/auth/domain/auth_gateway.dart';

import 'package:ganaderov/features/dashboard/domain/dashboard_summary.dart';

import 'package:ganaderov/features/livestock/domain/inventory.dart';

import 'package:ganaderov/features/settings/domain/ranch.dart';

class FakeRanch extends RanchRepository {
  @override Future<RanchContext> load() async => const RanchContext(status:'unassigned');
  @override Future<void> create(String ranchName,String displayName) async {}
  @override Future<void> requestAccess(String code,String displayName) async {}
  @override Future<void> review(RanchContext original,String requestId,bool approve) async {}
  @override Future<void> revoke(RanchContext original,String workerId) async {}
}

class FakeInventory implements InventoryRepository {
  @override Future<InventorySnapshot> load() async => const InventorySnapshot(status: 'active', ranchName: 'Rancho de prueba');
}

class FakeDashboard implements DashboardRepository {
  @override Future<DashboardSummary> load() async => const DashboardSummary(status: 'active', ranchName: 'Rancho de prueba', total: 3);
}

class FakeAuth extends AuthGateway {
  bool active = false;
  @override bool get signedIn => active;
  @override bool get recovering => false;
  @override String? get email => active ? 'test@example.com' : null;
  @override String? get notice => null;
  @override Future<void> login(String email, String password) async { active = true; notifyListeners(); }
  @override Future<bool> register(String email, String password) async => false;
  @override Future<void> recover(String email) async {}
  @override Future<void> reset(String password) async {}
  @override Future<void> social(bool google) async {}
  @override Future<void> logout() async { active = false; notifyListeners(); }
}
void main() {
  test('unauthenticated dashboard is protected', () {
    for (final path in ['/', '/ganado', '/jornadas', '/analisis', '/ajustes']) {
      expect(authRedirect(signedIn: false, recovering: false, path: path), '/login');
    }
    expect(authRedirect(signedIn: true, recovering: true, path: '/'), '/reset');
    expect(authRedirect(signedIn: true, recovering: false, path: '/login'), '/');
  });
  testWidgets('login and logout change protected route', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(GanaderovApp(auth: auth, dashboardRepository: FakeDashboard(), inventoryRepository: FakeInventory(), ranchRepository: FakeRanch()));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsWidgets);
    await auth.login('test@example.com', 'password');
    await tester.pumpAndSettle();
    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('Rancho de prueba'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Ganado'));
    await tester.pumpAndSettle();
    expect(find.text('Inventario de ganado'), findsOneWidget);
    await tester.tap(find.text('Jornadas'));
    await tester.pumpAndSettle();
    expect(find.text('Jornadas de campo'), findsOneWidget);
    await tester.tap(find.text('Análisis'));
    await tester.pumpAndSettle();
    expect(find.text('Análisis ganadero'), findsOneWidget);
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.text('Rancho y usuarios'), findsOneWidget);
    final logout = find.widgetWithText(OutlinedButton, 'Cerrar sesión');
    final settingsScroll = find.descendant(
      of: find.byType(SettingsPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(logout, 200, scrollable: settingsScroll);
    await tester.pumpAndSettle();
    expect(logout.hitTestable(), findsOneWidget);
    expect(tester.widget<OutlinedButton>(logout).onPressed, isNotNull);
    await tester.tap(logout.hitTestable());
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(auth.signedIn, isTrue);
    final confirm = find.descendant(
      of: dialog,
      matching: find.widgetWithText(FilledButton, 'Salir'),
    );
    expect(confirm.hitTestable(), findsOneWidget);
    await tester.tap(confirm.hitTestable());
    await tester.pumpAndSettle();
    expect(auth.signedIn, isFalse);
    expect(find.text('Iniciar sesión'), findsWidgets);
  });
}
