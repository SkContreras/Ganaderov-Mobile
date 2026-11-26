import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../../features/livestock/domain/inventory.dart';

class OfflineStore extends GeneratedDatabase {
  OfflineStore([QueryExecutor? executor]):super(executor??driftDatabase(name:'ganaderov_local'));
  @override int get schemaVersion=>1;
  @override Iterable<TableInfo<Table,Object?>> get allTables=>const [];
  @override List<DatabaseSchemaEntity> get allSchemaEntities=>const [];
  @override MigrationStrategy get migration=>MigrationStrategy(onCreate:(_)async{
    await customStatement('CREATE TABLE inventory_cache (user_id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, saved_at INTEGER NOT NULL, payload TEXT NOT NULL)');
  });
  Future<void> save(InventorySnapshot s)async{
    if(s.status!='active'||s.userId.isEmpty||s.ownerId.isEmpty||s.offline)throw StateError('Instantánea no válida');
    final json=jsonEncode({'ranchName':s.ranchName,'role':s.role,'records':s.records,'statusOptions':s.statusOptions,'statusLabels':s.statusLabels,'config':s.config,'configRevision':s.configRevision});
    await customStatement('INSERT INTO inventory_cache(user_id,owner_id,saved_at,payload) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET owner_id=excluded.owner_id,saved_at=excluded.saved_at,payload=excluded.payload',[s.userId,s.ownerId,DateTime.now().millisecondsSinceEpoch,json]);
  }
  Future<InventorySnapshot?> read(String userId)async{
    final row=await customSelect('SELECT owner_id,saved_at,payload FROM inventory_cache WHERE user_id = ?',variables:[Variable.withString(userId)]).getSingleOrNull();
    if(row==null)return null;
    final saved=DateTime.fromMillisecondsSinceEpoch(row.read<int>('saved_at'));
    final age=DateTime.now().difference(saved);
    if(age.isNegative||age>const Duration(hours:24)){await purge(userId);return null;}
    final p=jsonDecode(row.read<String>('payload')) as Map<String,dynamic>;
    final s=InventorySnapshot(status:'active',ranchName:p['ranchName'] as String,role:p['role'] as String,userId:userId,ownerId:row.read<String>('owner_id'),records:(p['records'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList(),statusOptions:Map<String,bool>.from(p['statusOptions'] as Map),statusLabels:Map<String,String>.from(p['statusLabels'] as Map),config:Map<String,dynamic>.from(p['config'] as Map),configRevision:p['configRevision'] as int,offline:true,cachedAt:saved);
    // Validate shape before exposing cached data.
    s.animals;
    return s;
  }
  Future<void> purge(String userId)=>customStatement('DELETE FROM inventory_cache WHERE user_id=?',[userId]);
  Future<void> purgeAll()=>customStatement('DELETE FROM inventory_cache');
}
