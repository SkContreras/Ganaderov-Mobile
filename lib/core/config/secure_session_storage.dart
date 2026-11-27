import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase owns session serialization and rotation. Store that exact value
// in secure storage instead of shared preferences. Import the previous value
// once via the library's legacy LocalStorage, then remove it.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this.project):_legacy=SharedPreferencesLocalStorage(persistSessionKey:'sb-${Uri.parse(project).host.split('.').first}-auth-token');
  final String project;
  final LocalStorage _legacy;
  static const _secure=FlutterSecureStorage();
  String get _key=>'ganaderov.auth.session.v1:$project';
  @override Future<void> initialize()async{
    await _legacy.initialize();
    final current=await _secure.read(key:_key);
    if(current==null&&await _legacy.hasAccessToken()){
      final old=await _legacy.accessToken();
      if(old!=null)await _secure.write(key:_key,value:old);
    }
    await _legacy.removePersistedSession();
  }
  @override Future<bool> hasAccessToken()async=>(await _secure.read(key:_key))!=null;
  @override Future<String?> accessToken()=>_secure.read(key:_key);
  @override Future<void> persistSession(String persistSessionString)=>_secure.write(key:_key,value:persistSessionString);
  @override Future<void> removePersistedSession()async{await _secure.delete(key:_key);await _legacy.removePersistedSession();}
}
