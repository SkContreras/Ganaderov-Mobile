import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';
void main(){
  test('isolates accounts and restores read-only snapshot',()async{
    final db=OfflineStore(NativeDatabase.memory());
    addTearDown(db.close);
    await db.save(const InventorySnapshot(status:'active',userId:'a',ownerId:'r',role:'owner',ranchName:'Rancho'));
    expect(await db.read('b'),isNull);
    final s=(await db.read('a'))!;
    expect(s.offline,isTrue);
    expect(s.canManage,isFalse);
    expect(s.ranchName,'Rancho');
    await db.purge('a');
    expect(await db.read('a'),isNull);
  });
}
