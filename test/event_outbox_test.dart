import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/core/sync/event_outbox.dart';
import 'package:ganaderov/features/livestock/domain/event_draft.dart';
void main(){
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
