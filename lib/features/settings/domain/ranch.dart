import 'package:flutter/foundation.dart';

String ranchRoleLabel(String role) => switch(role) {
  'owner' => 'Propietario', 'admin' => 'Administrador', 'worker' => 'Trabajador', _ => 'Miembro',
};

class RanchMember {
  const RanchMember(this.id,this.name,this.role);
  final String id,name,role;
}
class RanchRequest {
  const RanchRequest(this.id,this.name,this.requestedAt);
  final String id,name,requestedAt;
}
class RanchContext {
  const RanchContext({required this.status,this.ownerId='',this.name='',this.displayName='',this.role='',this.joinCode='',this.members=const [],this.requests=const []});
  final String status,ownerId,name,displayName,role,joinCode;
  final List<RanchMember> members;
  final List<RanchRequest> requests;
  bool get canManage => status=='active' && (role=='owner'||role=='admin');
  factory RanchContext.fromJson(Map raw) {
    final status=raw['status'];
    if(status=='pending'||status=='unassigned') return RanchContext(status:status as String);
    if(status!='active'||raw['owner_id'] is! String||!['owner','admin','worker'].contains(raw['role'])) throw const FormatException('Contexto de rancho inválido');
    final manager=['owner','admin'].contains(raw['role']);
    final members=raw['members'];
    final requests=raw['requests'];
    return RanchContext(
      status:'active',ownerId:raw['owner_id'] as String,name:raw['ranch_name']?.toString()??'',displayName:raw['display_name']?.toString()??'',role:raw['role'] as String,
      joinCode:manager?raw['join_code']?.toString()??'':'',
      members:manager&&members is List?[for(final m in members.whereType<Map>()) if(m['user_id'] is String) RanchMember(m['user_id'] as String,m['display_name']?.toString()??'',m['role']?.toString()??'')]:[],
      requests:manager&&requests is List?[for(final r in requests.whereType<Map>()) if(r['id'] is String) RanchRequest(r['id'] as String,r['display_name']?.toString()??'',r['requested_at']?.toString()??'')]:[],
    );
  }
}
abstract class RanchRepository extends ChangeNotifier {
  Future<RanchContext> load();
  Future<void> create(String ranchName,String displayName);
  Future<void> requestAccess(String code,String displayName);
  Future<void> review(RanchContext original,String requestId,bool approve);
  Future<void> revoke(RanchContext original,String workerId);
  void invalidate()=>notifyListeners();
}
