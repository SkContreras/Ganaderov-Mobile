import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

// Only a short-lived access token; never copy the refresh token or password.
// Foreground Supabase Auth remains the sole session refresh authority.
class BackgroundSession {
  static const _storage=FlutterSecureStorage();
  static const _key='ganaderov.background.access.v1';
  static Future<void> clear()=>_storage.delete(key:_key);
  static Future<void> publish(Session? session)async{
    if(!SupabaseConfig.backgroundSyncEnabled||!SupabaseConfig.eventRpcEnabled||session==null){await clear();return;}
    final expires=session.expiresAt;
    if(expires==null||expires*1000<=DateTime.now().millisecondsSinceEpoch+60000){await clear();return;}
    await _storage.write(key:_key,value:jsonEncode({'userId':session.user.id,'accessToken':session.accessToken,'expiresAt':expires,'url':SupabaseConfig.url}));
  }
  static Future<Map<String,dynamic>?> read()async{
    final raw=await _storage.read(key:_key);
    if(raw==null)return null;
    final p=jsonDecode(raw);
    if(p is! Map||p['url']!=SupabaseConfig.url||p['userId'] is! String||p['accessToken'] is! String||p['expiresAt'] is! int||(p['expiresAt'] as int)*1000<=DateTime.now().millisecondsSinceEpoch+60000)return null;
    return Map<String,dynamic>.from(p);
  }
}
// Serialize foreground credential writes; logout waits for deletion.
class BackgroundSessionPublisher {
  Future<void> _tail=Future.value();
  Future<void> update(Session? session){
    final next=_tail.catchError((Object _){}).then((_)=>BackgroundSession.publish(session));
    _tail=next;
    return next;
  }
}
