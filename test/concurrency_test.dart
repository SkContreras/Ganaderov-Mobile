import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/core/sync/event_outbox.dart';
import 'package:ganaderov/features/livestock/domain/event_draft.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';

PendingEvent fixture(String user,{double weight=300})=>PendingEvent(
  userId:user,ownerId:'10000000-0000-4000-8000-000000000001',animalId:'a',
  draft:EventDraft(id:'20000000-0000-4000-8000-000000000001',type:'weight',date:'2025-01-01',weight:weight,capturedAt:DateTime.utc(2025,1,1)),
);
void main(){
  test('concurrent enqueue retains one immutable operation',()async{
    final db=OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    final p=fixture('a');
    await Future.wait(List.generate(20,(_)=>db.enqueue(p,rpc:true)));
    final first=(await db.pending('a')).single;
    await expectLater(db.enqueue(fixture('a',weight:301),rpc:true),throwsStateError);
    expect((await db.pending('a')).single.operation,first.operation);
  });
  test('late retry cannot regress confirmed receipt',()async{
    final db=OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    await db.enqueue(fixture('a'),rpc:true);
    final p=(await db.pending('a')).single;
    await db.confirmRpc(p,{'operationId':p.operation!['operationId'],'status':'applied'});
    await db.retry(p,'late timeout',100);
    await db.stopRpc(p,'conflict','late response');
    expect(await db.pending('a'),isEmpty);
    final row=await db.customSelect('SELECT state,attempts FROM event_outbox').getSingle();
    expect(row.read<String>('state'),'confirmed');
    expect(row.read<int>('attempts'),0);
  });
  test('file-backed queue survives close and account cache cleanup',()async{
    final directory=await Directory.systemTemp.createTemp('ganaderov-test-');
    addTearDown(()=>directory.delete(recursive:true));
    final file=File('${directory.path}/queue.sqlite');
    final first=OfflineStore(NativeDatabase(file));
    Map<String,dynamic>? original;
    try{
      await first.enqueue(fixture('a'),rpc:true);
      await first.enqueue(fixture('b'),rpc:true);
      original=(await first.pending('a')).single.operation;
      await first.save(const InventorySnapshot(status:'active',userId:'a',ownerId:'r',role:'owner'));
      await first.retainOnly('b');
      expect(await first.read('a'),isNull);
    }finally{await first.close();}
    final second=OfflineStore(NativeDatabase(file));
    addTearDown(second.close);
    expect((await second.pending('a')).single.operation,original);
    expect((await second.pending('b')).single.userId,'b');
    expect(await second.pending('outsider'),isEmpty);
  });
}
