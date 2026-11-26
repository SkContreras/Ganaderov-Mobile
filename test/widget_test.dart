import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/app.dart';
import 'package:ganaderov/core/router/app_router.dart';
import 'package:ganaderov/features/auth/domain/auth_gateway.dart';

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
    expect(authRedirect(signedIn: false, recovering: false, path: '/'), '/login');
    expect(authRedirect(signedIn: true, recovering: true, path: '/'), '/reset');
    expect(authRedirect(signedIn: true, recovering: false, path: '/login'), '/');
  });
  testWidgets('login and logout change protected route', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(GanaderovApp(auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsWidgets);
    await auth.login('test@example.com', 'password');
    await tester.pumpAndSettle();
    expect(find.text('Resumen'), findsOneWidget);
    await auth.logout();
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsWidgets);
  });
}
