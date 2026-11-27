import 'dart:convert';
import 'local_cipher.dart';
import 'local_key.dart';
import 'package:uuid/uuid.dart';
import '../sync/event_protocol.dart';
import '../sync/event_outbox.dart';
import '../../features/livestock/domain/event_draft.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../../features/livestock/domain/inventory.dart';

class OfflineStore extends GeneratedDatabase {
  OfflineStore([QueryExecutor? executor, this.cipher]):super(executor??driftDatabase(name:'ganaderov_local'));
  LocalCipher? cipher;
  static Future<OfflineStore> protected({bool provision=false})async{
    final existing=await LocalKey.read();
    // A missing key is recoverable only when no encrypted data exists.
    final db=OfflineStore(null,existing);
    try{
      await db.customSelect('SELECT 1').get();
      if(existing==null){
        if(!provision||await db._hasEncryptedData())throw StateError('Clave local no disponible; conserva la base para recuperación.');
        db.cipher=await LocalKey.provision();
      }
      await db._protectExisting();
      return db;
    }catch(_){await db.close();rethrow;}
  }
  String _scope(List<String> parts)=>jsonEncode(parts);
  Future<bool> _hasEncryptedData()async{
    final rows=await customSelect("SELECT 1 FROM inventory_cache WHERE payload LIKE 'gcm1:%' OR payload LIKE 'gcm2:%' UNION ALL SELECT 1 FROM event_outbox WHERE payload LIKE 'gcm1:%' OR payload LIKE 'gcm2:%' LIMIT 1").get();
    return rows.isNotEmpty;
  }
  String _seal(String text,List<String> parts){
    if(cipher==null)return text;
    return LocalCipher.accountPrefix+cipher!.forAccount(parts[1]).seal(text,_scope(parts)).substring(LocalCipher.prefix.length);
  }
  String _open(String text,List<String> parts){
    if(text.startsWith(LocalCipher.accountPrefix)){
      if(cipher==null)throw StateError('Clave local no disponible');
      return cipher!.forAccount(parts[1]).open(LocalCipher.prefix+text.substring(LocalCipher.accountPrefix.length),_scope(parts));
    }
    if(text.startsWith(LocalCipher.prefix)){
      if(cipher==null)throw StateError('Clave local no disponible');
      return cipher!.open(text,_scope(parts));
    }
    if(cipher!=null)throw const FormatException('Contenido sin cifrar');
    return text;
  }
  List<String> _eventScope(String user,String owner,String event,String field)=>['outbox',user,owner,event,field];
  @override int get schemaVersion=>10;
  @override Iterable<TableInfo<Table,Object?>> get allTables=>const [];
  @override List<DatabaseSchemaEntity> get allSchemaEntities=>const [];
  @override MigrationStrategy get migration=>MigrationStrategy(onCreate:(_)async{
    await customStatement('CREATE TABLE inventory_cache (user_id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, saved_at INTEGER NOT NULL, payload TEXT NOT NULL)');
    await _createOutbox();
    await _upgradeProtocol();
    await _createDeliveryLease();
    await _createUniversal();
    await _upgradeConflictReview();
    await _createAnalysisPreferences();
    await _createJourneyCache();
    await _protectExisting();
  },onUpgrade:(m,from,to)async{if(from<2)await _createOutbox();if(from<3)await _upgradeProtocol();if(from<4)await _createDeliveryLease();if(from<6)await _protectExisting();if(from<7)await _createUniversal();if(from<8)await _upgradeConflictReview();if(from<9)await _createAnalysisPreferences();if(from<10)await _createJourneyCache();});
  Future<void> _createUniversal()async{
    await customStatement('CREATE TABLE universal_outbox (user_id TEXT NOT NULL,owner_id TEXT NOT NULL,operation_id TEXT NOT NULL,payload TEXT NOT NULL,attachment TEXT,state TEXT NOT NULL DEFAULT \'pending\',attempts INTEGER NOT NULL DEFAULT 0,next_at INTEGER NOT NULL DEFAULT 0,receipt TEXT,PRIMARY KEY(user_id,owner_id,operation_id))');
    await customStatement('CREATE TABLE incremental_mirror (user_id TEXT NOT NULL,owner_id TEXT NOT NULL,project TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(user_id,owner_id,project))');
  }
  Future<void> _createJourneyCache()=>customStatement('CREATE TABLE journey_cache (user_id TEXT NOT NULL,owner_id TEXT NOT NULL,project TEXT NOT NULL,saved_at INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(user_id,owner_id,project))');
  Future<void> saveJourneyCache(String user,String owner,String project,List<Map<String,dynamic>> rows)=>customStatement('INSERT INTO journey_cache(user_id,owner_id,project,saved_at,payload) VALUES(?,?,?,?,?) ON CONFLICT(user_id,owner_id,project) DO UPDATE SET saved_at=excluded.saved_at,payload=excluded.payload',[user,owner,project,DateTime.now().millisecondsSinceEpoch,_seal(jsonEncode(rows),['journeys',user,owner,project])]);
  Future<List<Map<String,dynamic>>> readJourneyCache(String user,String owner,String project)async{
    final row=await customSelect('SELECT saved_at,payload FROM journey_cache WHERE user_id=? AND owner_id=? AND project=?',variables:[Variable.withString(user),Variable.withString(owner),Variable.withString(project)]).getSingleOrNull();
    if(row==null)return [];
    final age=DateTime.now().millisecondsSinceEpoch-row.read<int>('saved_at');
    if(age<0||age>86400000)return [];
    return (jsonDecode(_open(row.read<String>('payload'),['journeys',user,owner,project])) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }
  Future<void> _createAnalysisPreferences()=>customStatement('CREATE TABLE analysis_preferences (user_id TEXT NOT NULL,owner_id TEXT NOT NULL,project TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(user_id,owner_id,project))');
  Future<List<Map<String,dynamic>>> readQuotes(String user,String owner,String project)async{
    final row=await customSelect('SELECT payload FROM analysis_preferences WHERE user_id=? AND owner_id=? AND project=?',variables:[Variable.withString(user),Variable.withString(owner),Variable.withString(project)]).getSingleOrNull();
    if(row==null)return [];
    return (jsonDecode(_open(row.read<String>('payload'),['quotes',user,owner,project])) as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
  }
  Future<void> changeQuote(String user,String owner,String project,Map<String,dynamic>? quote,String id)=>transaction(()async{
    final rows=await readQuotes(user,owner,project);
    rows.removeWhere((r)=>r['id']==id||(quote!=null&&r['category']==quote['category']&&r['date']==quote['date']));
    if(quote!=null)rows.insert(0,quote);
    await customStatement('INSERT INTO analysis_preferences(user_id,owner_id,project,payload) VALUES(?,?,?,?) ON CONFLICT(user_id,owner_id,project) DO UPDATE SET payload=excluded.payload',[user,owner,project,_seal(jsonEncode(rows.take(100).toList()),['quotes',user,owner,project])]);
  });
  Future<void> _upgradeConflictReview()async{
    await customStatement('ALTER TABLE universal_outbox ADD COLUMN archived_from TEXT');
    await customStatement('ALTER TABLE universal_outbox ADD COLUMN resolved_by TEXT');
    await customStatement('ALTER TABLE universal_outbox ADD COLUMN resolves TEXT');
    await customStatement('ALTER TABLE event_outbox ADD COLUMN archived_from TEXT');
  }
  Future<List<Map<String,dynamic>>> reviewUniversal(String user,String owner)async{
    final rows=await customSelect("SELECT operation_id,payload,state,receipt,archived_from,resolved_by,resolves FROM universal_outbox WHERE user_id=? AND owner_id=? AND state IN ('conflict','rejected','archived','pending') ORDER BY rowid DESC LIMIT 200",variables:[Variable.withString(user),Variable.withString(owner)]).get();
    return rows.map((row){
      final id=row.read<String>('operation_id'),scope=['universal',user,owner,row.read<String>('operation_id')],receipt=row.readNullable<String>('receipt');
      return <String,dynamic>{'id':id,'operation':jsonDecode(_open(row.read<String>('payload'),scope)),'state':row.read<String>('state'),'receipt':receipt==null?null:jsonDecode(_open(receipt,[...scope,'receipt'])),'archivedFrom':row.readNullable<String>('archived_from'),'resolvedBy':row.readNullable<String>('resolved_by'),'resolves':row.readNullable<String>('resolves')};
    }).toList();
  }
  Future<void> archiveUniversal(String user,String owner,String id,bool archive)async{
    if(archive){
      await customStatement("UPDATE universal_outbox SET archived_from=state,state='archived' WHERE user_id=? AND owner_id=? AND operation_id=? AND state IN ('conflict','rejected') AND resolved_by IS NULL",[user,owner,id]);
    }else{
      await customStatement("UPDATE universal_outbox SET state=archived_from WHERE user_id=? AND owner_id=? AND operation_id=? AND state='archived' AND archived_from IN ('conflict','rejected') AND resolved_by IS NULL",[user,owner,id]);
    }
  }
  Future<void> replaceConflict(String user,String owner,String original,Map<String,dynamic> expected,Map<String,dynamic> replacement)async{
    await transaction(()async{
      final old=await customSelect("SELECT payload,state,resolved_by FROM universal_outbox WHERE user_id=? AND owner_id=? AND operation_id=?",variables:[Variable.withString(user),Variable.withString(owner),Variable.withString(original)]).getSingleOrNull();
      if(old==null||!['conflict','rejected','archived'].contains(old.read<String>('state'))||old.readNullable<String>('resolved_by')!=null||_open(old.read<String>('payload'),['universal',user,owner,original])!=jsonEncode(expected))throw StateError('La operación cambió');
      if(replacement['operationId']==original||replacement['ownerId']!=owner||replacement['entityId']!=expected['entityId']||replacement['action']!=expected['action'])throw StateError('Resolución inválida');
      await enqueueUniversal(user,owner,replacement);
      await customStatement("UPDATE universal_outbox SET resolves=? WHERE user_id=? AND owner_id=? AND operation_id=?",[original,user,owner,replacement['operationId']]);
      await customStatement("UPDATE universal_outbox SET archived_from=state,state='archived',resolved_by=? WHERE user_id=? AND owner_id=? AND operation_id=?",[replacement['operationId'],user,owner,original]);
    });
  }
  Future<String> installationId()=>_deviceId();
  Future<void> enqueueUniversal(String user,String owner,Map<String,dynamic> operation,{String? attachment})async{
    final id=operation['operationId'] as String;
    if(operation['ownerId']!=owner)throw StateError('Ámbito inválido');
    await transaction(()async{
      final old=await customSelect('SELECT payload,attachment FROM universal_outbox WHERE user_id=? AND owner_id=? AND operation_id=?',variables:[Variable.withString(user),Variable.withString(owner),Variable.withString(id)]).getSingleOrNull();
      final scope=['universal',user,owner,id];
      final body=jsonEncode(operation);
      if(old!=null){
        final previous=old.readNullable<String>('attachment');
        if(_open(old.read<String>('payload'),scope)!=body||(previous==null?null:_open(previous,[...scope,'attachment']))!=attachment)throw StateError('UUID reutilizado');
        return;
      }
      await customStatement('INSERT INTO universal_outbox(user_id,owner_id,operation_id,payload,attachment) VALUES(?,?,?,?,?)',[user,owner,id,_seal(body,scope),attachment==null?null:_seal(attachment,[...scope,'attachment'])]);
    });
  }
  Future<List<Map<String,dynamic>>> universalPending(String user,String owner)async{
    final rows=await customSelect("SELECT * FROM universal_outbox WHERE user_id=? AND owner_id=? AND state='pending' ORDER BY rowid",variables:[Variable.withString(user),Variable.withString(owner)]).get();
    return rows.map((row){
      final id=row.read<String>('operation_id'),scope=['universal',user,owner,row.read<String>('operation_id')];
      final attachment=row.readNullable<String>('attachment');
      return <String,dynamic>{'id':id,'operation':jsonDecode(_open(row.read<String>('payload'),scope)),'attachment':attachment==null?null:_open(attachment,[...scope,'attachment']),'attempts':row.read<int>('attempts'),'nextAt':row.read<int>('next_at')};
    }).toList();
  }
  Future<void> settleUniversal(String user,String owner,String id,String state,Map<String,dynamic>? receipt,int nextAt)async{
    if(!['pending','confirmed','conflict','rejected'].contains(state))throw ArgumentError('Estado inválido');
    await customStatement("UPDATE universal_outbox SET state=?,receipt=?,attempts=attempts+1,next_at=? WHERE user_id=? AND owner_id=? AND operation_id=? AND state='pending'",[state,receipt==null?null:_seal(jsonEncode(receipt),['universal',user,owner,id,'receipt']),nextAt,user,owner,id]);
  }
  Future<Map<String,dynamic>?> readMirror(String user,String owner,String project)async{
    final row=await customSelect('SELECT payload FROM incremental_mirror WHERE user_id=? AND owner_id=? AND project=?',variables:[Variable.withString(user),Variable.withString(owner),Variable.withString(project)]).getSingleOrNull();
    return row==null?null:Map<String,dynamic>.from(jsonDecode(_open(row.read<String>('payload'),['mirror',user,owner,project])) as Map);
  }
  Future<bool> commitMirror(String user,String owner,String project,Map<String,dynamic>? expected,Map<String,dynamic> next) => transaction(()async{
    final old=await readMirror(user,owner,project);
    if(old?['epoch']!=expected?['epoch']||old?['cursor']!=expected?['cursor'])return false;
    await customStatement('INSERT INTO incremental_mirror(user_id,owner_id,project,payload) VALUES(?,?,?,?) ON CONFLICT(user_id,owner_id,project) DO UPDATE SET payload=excluded.payload',[user,owner,project,_seal(jsonEncode(next),['mirror',user,owner,project])]);
    return true;
  });
  Future<void> _protectExisting()async{
    if(cipher==null)return;
    await transaction(()async{
      String migrate(String raw,List<String> scope){
        if(raw.startsWith(LocalCipher.accountPrefix)){_open(raw,scope);return raw;}
        final plain=raw.startsWith(LocalCipher.prefix)?_open(raw,scope):raw;
        return _seal(plain,scope);
      }
      final rows=await customSelect('SELECT * FROM inventory_cache').get();
      for(final row in rows){
        final user=row.read<String>('user_id'),owner=row.read<String>('owner_id');
        await customStatement('UPDATE inventory_cache SET payload=? WHERE user_id=?',[migrate(row.read<String>('payload'),['inventory',user,owner]),user]);
      }
      for(final row in await customSelect('SELECT * FROM event_outbox').get()){
        final user=row.read<String>('user_id'),owner=row.read<String>('owner_id'),event=row.read<String>('event_id');
        String? protect(String field){final raw=row.readNullable<String>(field);return raw==null?null:migrate(raw,_eventScope(user,owner,event,field));}
        await customStatement('UPDATE event_outbox SET payload=?,operation=?,receipt=?,error=? WHERE user_id=? AND owner_id=? AND event_id=?',[protect('payload'),protect('operation'),protect('receipt'),protect('error'),user,owner,event]);
      }
    });
  }
  Future<void> _createDeliveryLease()=>customStatement('CREATE TABLE sync_delivery_lease (id INTEGER PRIMARY KEY CHECK(id=1), holder TEXT NOT NULL, expires_at INTEGER NOT NULL)');
  // All RPC senders share this lease. Expiry allows recovery after process death.
  Future<bool> acquireDeliveryLease(String holder,int now) => transaction(()async{
    await customStatement('INSERT INTO sync_delivery_lease(id,holder,expires_at) VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET holder=excluded.holder,expires_at=excluded.expires_at WHERE sync_delivery_lease.expires_at<=? OR sync_delivery_lease.holder=excluded.holder',[holder,now+60000,now]);
    final row=await customSelect('SELECT holder FROM sync_delivery_lease WHERE id=1').getSingle();
    return row.read<String>('holder')==holder;
  });
  Future<void> releaseDeliveryLease(String holder)=>customStatement('DELETE FROM sync_delivery_lease WHERE id=1 AND holder=?',[holder]);
  Future<void> _upgradeProtocol()async{
    await customStatement("ALTER TABLE event_outbox ADD COLUMN operation TEXT");
    await customStatement("ALTER TABLE event_outbox ADD COLUMN state TEXT NOT NULL DEFAULT 'pending'");
    await customStatement("ALTER TABLE event_outbox ADD COLUMN receipt TEXT");
    await customStatement('CREATE TABLE sync_installation (id INTEGER PRIMARY KEY CHECK(id=1), device_id TEXT NOT NULL)');
  }
  Future<String> _deviceId()async{
    await customStatement('INSERT OR IGNORE INTO sync_installation(id,device_id) VALUES(1,?)',[const Uuid().v4()]);
    return (await customSelect('SELECT device_id FROM sync_installation WHERE id=1').getSingle()).read<String>('device_id');
  }
  Future<void> _createOutbox()=>customStatement('CREATE TABLE event_outbox (user_id TEXT NOT NULL, owner_id TEXT NOT NULL, event_id TEXT NOT NULL, animal_id TEXT NOT NULL, payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_at INTEGER NOT NULL DEFAULT 0, error TEXT NOT NULL DEFAULT \'\', PRIMARY KEY(user_id,owner_id,event_id))');
  Future<void> save(InventorySnapshot s)async{
    if(s.status!='active'||s.userId.isEmpty||s.ownerId.isEmpty||s.offline)throw StateError('Instantánea no válida');
    final json=jsonEncode({'ranchName':s.ranchName,'role':s.role,'records':s.records,'statusOptions':s.statusOptions,'statusLabels':s.statusLabels,'config':s.config,'configRevision':s.configRevision});
    await customStatement('INSERT INTO inventory_cache(user_id,owner_id,saved_at,payload) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET owner_id=excluded.owner_id,saved_at=excluded.saved_at,payload=excluded.payload',[s.userId,s.ownerId,DateTime.now().millisecondsSinceEpoch,_seal(json,['inventory',s.userId,s.ownerId])]);
  }
  Future<InventorySnapshot?> read(String userId)async{
    final row=await customSelect('SELECT owner_id,saved_at,payload FROM inventory_cache WHERE user_id = ?',variables:[Variable.withString(userId)]).getSingleOrNull();
    if(row==null)return null;
    final saved=DateTime.fromMillisecondsSinceEpoch(row.read<int>('saved_at'));
    final age=DateTime.now().difference(saved);
    if(age.isNegative||age>const Duration(hours:24)){await purge(userId);return null;}
    final p=jsonDecode(_open(row.read<String>('payload'),['inventory',userId,row.read<String>('owner_id')])) as Map<String,dynamic>;
    if(!['owner','admin','worker'].contains(p['role'])||row.read<String>('owner_id').isEmpty){await purge(userId);return null;}
    final s=InventorySnapshot(status:'active',ranchName:p['ranchName'] as String,role:p['role'] as String,userId:userId,ownerId:row.read<String>('owner_id'),records:(p['records'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList(),statusOptions:Map<String,bool>.from(p['statusOptions'] as Map),statusLabels:Map<String,String>.from(p['statusLabels'] as Map),config:Map<String,dynamic>.from(p['config'] as Map),configRevision:p['configRevision'] as int,offline:true,cachedAt:saved);
    // Validate shape before exposing cached data.
    s.animals;
    return s;
  }
  Future<void> purge(String userId)=>transaction(()async{await customStatement('DELETE FROM inventory_cache WHERE user_id=?',[userId]);await customStatement('DELETE FROM incremental_mirror WHERE user_id=?',[userId]);await customStatement('DELETE FROM journey_cache WHERE user_id=?',[userId]);});
  Future<void> purgeAll()=>transaction(()async{await customStatement('DELETE FROM inventory_cache');await customStatement('DELETE FROM incremental_mirror');await customStatement('DELETE FROM journey_cache');});
  Future<void> retainOnly(String userId)=>transaction(()async{await customStatement('DELETE FROM inventory_cache WHERE user_id<>?',[userId]);await customStatement('DELETE FROM incremental_mirror WHERE user_id<>?',[userId]);await customStatement('DELETE FROM journey_cache WHERE user_id<>?',[userId]);});
  Future<void> invalidateOtherRanch(String userId,String ownerId)=>transaction(()async{await customStatement('DELETE FROM inventory_cache WHERE user_id=? AND owner_id<>?',[userId,ownerId]);await customStatement('DELETE FROM incremental_mirror WHERE user_id=? AND owner_id<>?',[userId,ownerId]);await customStatement('DELETE FROM journey_cache WHERE user_id=? AND owner_id<>?',[userId,ownerId]);});

  Future<void> enqueue(PendingEvent p,{bool rpc=false})async{
    p.draft.validate();
    final json=jsonEncode(p.draft.toJson());
    await transaction(()async{
      final rows=await customSelect('SELECT animal_id,payload FROM event_outbox WHERE user_id=? AND owner_id=? AND event_id=?',variables:[Variable.withString(p.userId),Variable.withString(p.ownerId),Variable.withString(p.draft.id)]).get();
      if(rows.isNotEmpty){
        if(rows.first.read<String>('animal_id')!=p.animalId||_open(rows.first.read<String>('payload'),_eventScope(p.userId,p.ownerId,p.draft.id,'payload'))!=json)throw StateError('El registro pendiente contiene otros datos.');
        return;
      }
      final operation=rpc?jsonEncode(buildEventOperation(p,operationId:const Uuid().v4(),deviceId:await _deviceId())):null;
      await customStatement('INSERT INTO event_outbox(user_id,owner_id,event_id,animal_id,payload,operation) VALUES(?,?,?,?,?,?)',[p.userId,p.ownerId,p.draft.id,p.animalId,_seal(json,_eventScope(p.userId,p.ownerId,p.draft.id,'payload')),operation==null?null:_seal(operation,_eventScope(p.userId,p.ownerId,p.draft.id,'operation'))]);
      await customStatement('UPDATE event_outbox SET error=? WHERE user_id=? AND owner_id=? AND event_id=?',[_seal('',_eventScope(p.userId,p.ownerId,p.draft.id,'error')),p.userId,p.ownerId,p.draft.id]);
    });
  }
  Future<List<PendingEvent>> pending(String userId)async{
    final rows=await customSelect('SELECT * FROM event_outbox WHERE user_id=? AND state NOT IN (\'confirmed\',\'archived\') ORDER BY rowid',variables:[Variable.withString(userId)]).get();
    String decode(QueryRow row,String field)=>_open(row.read<String>(field),_eventScope(userId,row.read<String>('owner_id'),row.read<String>('event_id'),field));
    return [for(final row in rows)PendingEvent(userId:userId,ownerId:row.read<String>('owner_id'),animalId:row.read<String>('animal_id'),draft:EventDraft.fromJson(jsonDecode(decode(row,'payload')) as Map<String,dynamic>),attempts:row.read<int>('attempts'),nextAt:row.read<int>('next_at'),error:decode(row,'error'),state:row.read<String>('state'),operation:row.readNullable<String>('operation')==null?null:Map<String,dynamic>.from(jsonDecode(decode(row,'operation')) as Map))];
  }
  Future<void> confirmRpc(PendingEvent p,Map<String,dynamic> receipt)=>customStatement("UPDATE event_outbox SET state='confirmed',receipt=?,error=? WHERE user_id=? AND owner_id=? AND event_id=? AND state='pending'",[_seal(jsonEncode(receipt),_eventScope(p.userId,p.ownerId,p.draft.id,'receipt')),_seal('',_eventScope(p.userId,p.ownerId,p.draft.id,'error')),p.userId,p.ownerId,p.draft.id]);
  Future<void> stopRpc(PendingEvent p,String state,String code)async{
    if(!['conflict','rejected'].contains(state))throw ArgumentError.value(state);
    await customStatement("UPDATE event_outbox SET state=?,error=? WHERE user_id=? AND owner_id=? AND event_id=? AND state='pending'",[state,_seal(code,_eventScope(p.userId,p.ownerId,p.draft.id,'error')),p.userId,p.ownerId,p.draft.id]);
  }
  Future<void> archiveConflict(PendingEvent p)async{
    await customStatement("UPDATE event_outbox SET state='archived' WHERE user_id=? AND owner_id=? AND event_id=? AND state IN ('conflict','rejected')",[p.userId,p.ownerId,p.draft.id]);
  }
  Future<void> acknowledge(PendingEvent p)=>customStatement('DELETE FROM event_outbox WHERE user_id=? AND owner_id=? AND event_id=?',[p.userId,p.ownerId,p.draft.id]);
  Future<void> retry(PendingEvent p,String error,int nextAt)=>customStatement('UPDATE event_outbox SET attempts=attempts+1,error=?,next_at=? WHERE user_id=? AND owner_id=? AND event_id=? AND state=\'pending\'',[_seal(error,_eventScope(p.userId,p.ownerId,p.draft.id,'error')),nextAt,p.userId,p.ownerId,p.draft.id]);
}
