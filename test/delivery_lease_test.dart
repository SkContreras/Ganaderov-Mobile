import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/offline_store.dart';
void main(){
  test('lease excludes second sender, expires, and rejects stale release',()async{
    final db=OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await db.acquireDeliveryLease('foreground',1000),isTrue);
    expect(await db.acquireDeliveryLease('worker',1001),isFalse);
    expect(await db.acquireDeliveryLease('worker',61000),isTrue);
    await db.releaseDeliveryLease('foreground');
    expect(await db.acquireDeliveryLease('other',61001),isFalse);
    await db.releaseDeliveryLease('worker');
    expect(await db.acquireDeliveryLease('other',61001),isTrue);
  });
}
