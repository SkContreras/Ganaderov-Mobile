import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import '../domain/auth_gateway.dart';
import '../../../core/sync/background_session.dart';

class SupabaseAuthGateway extends AuthGateway {
  SupabaseAuthGateway(this.client,{this.clearCache,this.retainCacheFor}) {
    _lastUserId=client.auth.currentUser?.id;
    unawaited(_background.update(client.auth.currentSession).catchError((Object _){}));
    _subscription = client.auth.onAuthStateChange.listen((state) {
      if(!_loggingOut)unawaited(_background.update(state.session).catchError((Object _){}));
      final userId=state.session?.user.id;
      if(userId!=_lastUserId){
        _lastUserId=userId;
        // Do not let a failed cleanup prevent the auth state change.
        final cleanup=userId==null?clearCache?.call():retainCacheFor?.call(userId);
        if(cleanup!=null)unawaited(cleanup.catchError((Object _){}));
      }
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
  final Future<void> Function(String)? retainCacheFor;
  String? _lastUserId;
  final _background=BackgroundSessionPublisher();
  bool _loggingOut=false;
  static const callback = appFlavor=='d4test'
      ? 'com.ganaderov.mobile.d4test://auth/callback'
      : 'com.ganaderov.mobile://auth/callback';
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
    _loggingOut=true;
    try{
      await _background.update(null);
      try{await clearCache?.call();}catch(_){}
      await client.auth.signOut(scope: SignOutScope.local);
    }finally{_loggingOut=false;await clearCache?.call();}
  }
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
