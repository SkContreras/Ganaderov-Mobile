import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/settings/domain/ranch.dart';
void main(){
  test('worker never sees join code or management lists',(){
    final r=RanchContext.fromJson({'status':'active','owner_id':'r','role':'worker','join_code':'secret','members':[{'user_id':'a'}],'requests':[{'id':'b'}]});
    expect(r.canManage,isFalse);
    expect(r.joinCode,isEmpty);
    expect(r.members,isEmpty);
    expect(r.requests,isEmpty);
  });
  test('manager sees members and pending requests',(){
    final r=RanchContext.fromJson({'status':'active','owner_id':'r','role':'admin','join_code':'ABC123','members':[{'user_id':'a','role':'worker'}],'requests':[{'id':'b'}]});
    expect(r.canManage,isTrue);
    expect(r.members.single.id,'a');
    expect(r.requests.single.id,'b');
  });
  test('pending is not active',()=>expect(RanchContext.fromJson({'status':'pending'}).canManage,isFalse));
}
