import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/auth_gateway.dart';

class SupabaseAuthGateway extends AuthGateway {
  SupabaseAuthGateway(this.client,{this.clearCache}) {
    _subscription = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
      if (state.event == AuthChangeEvent.signedOut) _recovering = false;
      _notice = null;
      notifyListeners();
    }, onError: (Object error, StackTrace stack) {
      _notice = 'No se pudo completar la autenticación. Revisa tu conexión e inténtalo de nuevo.';
      notifyListeners();
    });
  }
  final SupabaseClient client;
  final Future<void> Function()? clearCache;
  static const callback = 'com.ganaderov.mobile://auth/callback';
  late final StreamSubscription<AuthState> _subscription;
  bool _recovering = false;
  String? _notice;
  @override
  bool get signedIn => client.auth.currentSession != null;
  @override
  bool get recovering => _recovering;
  @override
  String? get email => client.auth.currentUser?.email;
  @override
  String? get notice => _notice;
  @override
  Future<void> login(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }
  @override
  Future<bool> register(String email, String password) async {
    final response = await client.auth.signUp(email: email, password: password, emailRedirectTo: callback);
    return response.session != null;
  }
  @override
  Future<void> recover(String email) => client.auth.resetPasswordForEmail(email, redirectTo: callback);
  @override
  Future<void> reset(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
    _recovering = false;
    notifyListeners();
  }
  @override
  Future<void> social(bool google) async {
    final launched = await client.auth.signInWithOAuth(
      google ? OAuthProvider.google : OAuthProvider.facebook,
      redirectTo: callback,
      authScreenLaunchMode: LaunchMode.externalApplication,
      scopes: google ? null : 'email,public_profile',
      queryParams: google ? {'prompt': 'select_account'} : null,
    );
    if (!launched) throw StateError('OAuth launch failed');
  }
  @override
  Future<void> logout() async {
    await clearCache?.call();
    await client.auth.signOut(scope: SignOutScope.local);
    await clearCache?.call();
  }
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
