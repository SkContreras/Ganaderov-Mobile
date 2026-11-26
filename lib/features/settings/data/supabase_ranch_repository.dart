import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/ranch.dart';

class SupabaseRanchRepository extends RanchRepository {
  SupabaseRanchRepository(this.client);
  final SupabaseClient client;
  String _user() => client.auth.currentUser?.id ?? (throw StateError('Inicia sesión nuevamente.'));
  void _verify(String id){if(_user()!=id)throw StateError('La sesión cambió.');}
  Future<RanchContext> _load(String id) async {
    _verify(id);
    final raw=await client.rpc('get_my_ranch_context');
    _verify(id);
    if(raw is! Map)throw const FormatException('Contexto inválido');
    return RanchContext.fromJson(raw);
  }
  @override Future<RanchContext> load()=>_load(_user());
  String _name(String s){
    final value=s.trim();
    if(value.isEmpty||value.length>120)throw StateError('Introduce un nombre de 1 a 120 caracteres.');
    return value;
  }
  Future<void> _write(String user,String function,Map<String,dynamic> args) async {
    _verify(user);
    await client.rpc(function,params:args);
    _verify(user);
    invalidate();
  }
  @override Future<void> create(String ranchName,String displayName) async {
    final id=_user();
    if((await _load(id)).status!='unassigned')throw StateError('Ya tienes un rancho o solicitud pendiente.');
    await _write(id,'create_my_ranch',{'p_ranch_name':_name(ranchName),'p_display_name':_name(displayName)});
  }
  @override Future<void> requestAccess(String code,String displayName) async {
    final id=_user();
    if((await _load(id)).status!='unassigned')throw StateError('Ya tienes un rancho o solicitud pendiente.');
    final value=code.trim().toUpperCase();
    if(value.length<6||value.length>40)throw StateError('Introduce un código de rancho válido.');
    await _write(id,'request_ranch_access',{'p_join_code':value,'p_display_name':_name(displayName)});
  }
  Future<RanchContext> _manager(String user,RanchContext original) async {
    final current=await _load(user);
    if(!original.canManage||!current.canManage||current.ownerId!=original.ownerId)throw StateError('Los permisos cambiaron.');
    return current;
  }
  @override Future<void> review(RanchContext original,String requestId,bool approve) async {
    final id=_user();
    final current=await _manager(id,original);
    if(!current.requests.any((r)=>r.id==requestId))throw StateError('La solicitud ya no está pendiente.');
    await _write(id,'review_ranch_access_request',{'p_request_id':requestId,'p_approve':approve});
  }
  @override Future<void> revoke(RanchContext original,String workerId) async {
    final id=_user();
    final current=await _manager(id,original);
    if(!current.members.any((m)=>m.id==workerId&&m.role=='worker'))throw StateError('El trabajador ya no está activo.');
    await _write(id,'revoke_ranch_worker',{'p_user_id':workerId});
  }
}
