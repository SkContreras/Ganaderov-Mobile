import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/core/sync/event_outbox.dart';
import 'package:ganaderov/core/sync/event_protocol.dart';
import 'package:ganaderov/features/livestock/domain/event_draft.dart';
void main(){
  test('archiving conflict preserves original identity and prevents resend',()async{
    final db=OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    final p=PendingEvent(userId:'u',ownerId:'10000000-0000-4000-8000-000000000001',animalId:'a',draft:EventDraft(id:'20000000-0000-4000-8000-000000000001',type:'weight',date:'2025-01-01',weight:300,capturedAt:DateTime.utc(2025,1,1)));
    await db.enqueue(p,rpc:true);
    final first=(await db.pending('u')).single;
    await db.archiveConflict(first);
    expect((await db.pending('u')).single.state,'pending');
    await db.stopRpc(first,'conflict','ENTITY_ID_REUSED');
    final stopped=(await db.pending('u')).single;
    await db.archiveConflict(stopped);
    expect(await db.pending('u'),isEmpty);
    await db.enqueue(p,rpc:true);
    expect(await db.pending('u'),isEmpty);
  });
  test('RPC operation is persisted and reuses identity',()async{
    final db=OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    final p=PendingEvent(userId:'u',ownerId:'10000000-0000-4000-8000-000000000001',animalId:'a',draft:EventDraft(id:'20000000-0000-4000-8000-000000000001',type:'weight',date:'2025-01-01',weight:300,capturedAt:DateTime.utc(2025,1,1)));
    await db.enqueue(p,rpc:true);
    final first=(await db.pending('u')).single;
    await db.enqueue(p,rpc:true);
    await db.retry(first,'timeout',100);
    final second=(await db.pending('u')).single;
    expect(second.operation,first.operation);
    expect(second.operation!['operationId'],isNot(p.draft.id));
    expect(second.operation!['changes'],{'animalId':'a','type':'weight','date':'2025-01-01','weight':300});
    expect(await db.pending('other'),isEmpty);
    final receipt=parseEventReceipt({'protocolVersion':1,'operationId':second.operation!['operationId'],'status':'duplicate','revision':1,'serverReceivedAt':'2025-01-01T00:00:00Z','code':'OK'},second.operation!['operationId'] as String);
    await db.confirmRpc(second,receipt);
    expect(await db.pending('u'),isEmpty);
    await db.enqueue(p,rpc:true);
    expect(await db.pending('u'),isEmpty);
  });
  test('invalid receipt cannot confirm an operation',(){
    expect(()=>parseEventReceipt({'protocolVersion':1,'operationId':'other'},'expected'),throwsFormatException);
  });

  test('queue deduplicates and survives cache purge',()async{
    final db=OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    const p=PendingEvent(userId:'u',ownerId:'r',animalId:'a',draft:EventDraft(id:'e',type:'weight',date:'2025-01-01',weight:300));
    await db.enqueue(p);await db.enqueue(p);
    expect((await db.pending('u')).length,1);
    expect(await db.pending('other'),isEmpty);
    await db.purgeAll();
    expect((await db.pending('u')).single.draft.weight,300);
    await db.retry(p,'error',100);
    expect((await db.pending('u')).single.attempts,1);
    await db.acknowledge(p);
    expect(await db.pending('u'),isEmpty);
  });
}
