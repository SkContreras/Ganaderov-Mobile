import 'dart:convert';
import '../sync/event_outbox.dart';
import '../../features/livestock/domain/event_draft.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../../features/livestock/domain/inventory.dart';

class OfflineStore extends GeneratedDatabase {
  OfflineStore([QueryExecutor? executor]):super(executor??driftDatabase(name:'ganaderov_local'));
  @override int get schemaVersion=>2;
  @override Iterable<TableInfo<Table,Object?>> get allTables=>const [];
  @override List<DatabaseSchemaEntity> get allSchemaEntities=>const [];
  @override MigrationStrategy get migration=>MigrationStrategy(onCreate:(_)async{
    await customStatement('CREATE TABLE inventory_cache (user_id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, saved_at INTEGER NOT NULL, payload TEXT NOT NULL)');
    await _createOutbox();
  },onUpgrade:(m,from,to)async{if(from<2)await _createOutbox();});
  Future<void> _createOutbox()=>customStatement('CREATE TABLE event_outbox (user_id TEXT NOT NULL, owner_id TEXT NOT NULL, event_id TEXT NOT NULL, animal_id TEXT NOT NULL, payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_at INTEGER NOT NULL DEFAULT 0, error TEXT NOT NULL DEFAULT \'\', PRIMARY KEY(user_id,owner_id,event_id))');
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

  Future<void> enqueue(PendingEvent p)async{
    p.draft.validate();
    final json=jsonEncode(p.draft.toJson());
    await transaction(()async{
      final rows=await customSelect('SELECT animal_id,payload FROM event_outbox WHERE user_id=? AND owner_id=? AND event_id=?',variables:[Variable.withString(p.userId),Variable.withString(p.ownerId),Variable.withString(p.draft.id)]).get();
      if(rows.isNotEmpty){
        if(rows.first.read<String>('animal_id')!=p.animalId||rows.first.read<String>('payload')!=json)throw StateError('El registro pendiente contiene otros datos.');
        return;
      }
      await customStatement('INSERT INTO event_outbox(user_id,owner_id,event_id,animal_id,payload) VALUES(?,?,?,?,?)',[p.userId,p.ownerId,p.draft.id,p.animalId,json]);
    });
  }
  Future<List<PendingEvent>> pending(String userId)async{
    final rows=await customSelect('SELECT * FROM event_outbox WHERE user_id=? ORDER BY rowid',variables:[Variable.withString(userId)]).get();
    return [for(final row in rows)PendingEvent(userId:userId,ownerId:row.read<String>('owner_id'),animalId:row.read<String>('animal_id'),draft:EventDraft.fromJson(jsonDecode(row.read<String>('payload')) as Map<String,dynamic>),attempts:row.read<int>('attempts'),nextAt:row.read<int>('next_at'),error:row.read<String>('error'))];
  }
  Future<void> acknowledge(PendingEvent p)=>customStatement('DELETE FROM event_outbox WHERE user_id=? AND owner_id=? AND event_id=?',[p.userId,p.ownerId,p.draft.id]);
  Future<void> retry(PendingEvent p,String error,int nextAt)=>customStatement('UPDATE event_outbox SET attempts=attempts+1,error=?,next_at=? WHERE user_id=? AND owner_id=? AND event_id=?',[error,nextAt,p.userId,p.ownerId,p.draft.id]);
}
