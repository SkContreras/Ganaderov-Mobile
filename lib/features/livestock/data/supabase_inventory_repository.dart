import 'dart:typed_data';
import '../../analysis/domain/productive_analysis.dart';
import 'dart:convert';
import '../../../core/sync/universal_sync.dart';
import '../../../core/sync/manual_resolution.dart';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../core/database/offline_store.dart';
import '../../../core/sync/event_outbox.dart';
import '../../../core/sync/event_protocol.dart';
import 'dart:math' as math;
import '../domain/animal_photos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/inventory.dart';
import '../../journeys/domain/journey.dart';
import '../domain/event_draft.dart';
import '../domain/animal_form_config.dart';
import 'package:uuid/uuid.dart';

class SupabaseInventoryRepository implements InventoryRepository, AnimalWriter, AnimalLifecycleWriter, AnimalPhotos, AnimalPhotoRemoval, AnimalEventWriter, JourneyRepository, ExtendedJourneyRepository, OutboxAccess, ConflictAccess, AnalysisPreferences, ForecastWriter {
  SupabaseInventoryRepository(this.client,{this.store,this.onSynced,this.eventRpcEnabled=false,this.journeyRpcEnabled=false,this.universalEnabled=false,this.incrementalEnabled=false,this.project=''});
  final bool universalEnabled,incrementalEnabled;
  final String project;
  UniversalSync get _universal=>UniversalSync(client,store??(throw StateError('Almacenamiento no disponible')),project);
  Future<void> queueOperation(InventorySnapshot s,String action,String id,Map<String,dynamic> changes,{int? revision,String? attachment})async{
    if(!universalEnabled||s.status!='active'||s.userId!=client.auth.currentUser?.id)throw StateError('Operación no disponible');
    await _universal.enqueue(s.userId,s.ownerId,action,id,changes,revision:revision,attachment:attachment);
    unawaited(syncEvents().catchError((Object _){}));
  }
  Future<int> _revision(InventorySnapshot s,String kind,String id,Object? expected)async{
    final row=await _universal.entity(s.userId,s.ownerId,kind,id);
    if(!_sameJson(row['data'],expected))throw StateError('La entidad cambió. Actualiza antes de editar.');
    return row['revision'] as int;
  }
  bool _sameJson(Object? a,Object? b){
    if(a is Map&&b is Map)return a.length==b.length&&a.keys.every((k)=>b.containsKey(k)&&_sameJson(a[k],b[k]));
    if(a is List&&b is List)return a.length==b.length&&List.generate(a.length,(i)=>_sameJson(a[i],b[i])).every((v)=>v);
    return a==b;
  }
  Future<(String,String)> _reviewScope()async{
    final user=client.auth.currentUser?.id;
    if(user==null||client.auth.currentSession==null||store==null)throw StateError('Sesión no disponible');
    final raw=await client.rpc('get_my_ranch_context');
    if(client.auth.currentUser?.id!=user||raw is! Map||raw['status']!='active'||raw['owner_id'] is! String)throw StateError('Membresía no disponible');
    return (user,raw['owner_id'] as String);
  }
  @override Future<List<Map<String,dynamic>>> reviewOperations()async{
    if(!universalEnabled)return [];
    final (user,owner)=await _reviewScope();
    final rows=await store!.reviewUniversal(user,owner);
    _universal.verify(user);
    return rows.map((r)=>{...r,'reviewUser':user,'reviewOwner':owner}).toList();
  }
  void _verifyEntry(Map<String,dynamic> entry,String user,String owner){
    if(entry['reviewUser']!=user||entry['reviewOwner']!=owner||(entry['operation'] as Map)['ownerId']!=owner)throw StateError('Ámbito modificado');
  }
  @override Future<Map<String,dynamic>> currentConflictEntity(Map<String,dynamic> entry)async{
    final (user,owner)=await _reviewScope();_verifyEntry(entry,user,owner);
    final op=Map<String,dynamic>.from(entry['operation'] as Map);
    return _universal.entity(user,owner,(op['action'] as String).split('.').first,op['entityId'] as String);
  }
  @override Future<void> archiveOperation(Map<String,dynamic> entry,bool archive)async{
    final (user,owner)=await _reviewScope();_verifyEntry(entry,user,owner);
    await store!.archiveUniversal(user,owner,entry['id'] as String,archive);
  }
  @override Future<void> resolveOperation(Map<String,dynamic> entry,Map<String,dynamic> reviewed,List<String> selected)async{
    if(!universalEnabled)throw StateError('Motor universal desactivado');
    final (user,owner)=await _reviewScope();_verifyEntry(entry,user,owner);
    final op=Map<String,dynamic>.from(entry['operation'] as Map);
    final current=await _universal.entity(user,owner,(op['action'] as String).split('.').first,op['entityId'] as String);
    final replacement=replacementOperation(op,reviewed,current,selected,const Uuid().v4(),DateTime.now().toUtc().toIso8601String());
    _universal.verify(user);
    await store!.replaceConflict(user,owner,entry['id'] as String,op,replacement);
    unawaited(syncEvents().catchError((Object _){}));
  }
  void _quoteScope(InventorySnapshot s){
    if(s.status!='active'||s.userId.isEmpty||s.ownerId.isEmpty||s.userId!=client.auth.currentUser?.id||client.auth.currentSession==null||store==null)throw StateError('Sesión inválida');
  }
  @override Future<List<PriceQuote>> quotes(InventorySnapshot s)async{
    _quoteScope(s);
    final rows=await store!.readQuotes(s.userId,s.ownerId,project);
    _quoteScope(s);
    return rows.map(PriceQuote.fromJson).where((q)=>q.valid).toList();
  }
  @override Future<void> saveQuote(InventorySnapshot s,PriceQuote quote)async{
    _quoteScope(s);if(!quote.valid)throw ArgumentError('Cotización inválida');
    await store!.changeQuote(s.userId,s.ownerId,project,quote.toJson(),quote.id);
  }
  @override Future<void> deleteQuote(InventorySnapshot s,String id)async{
    _quoteScope(s);await store!.changeQuote(s.userId,s.ownerId,project,null,id);
  }
  @override bool get forecastWritesEnabled=>universalEnabled;
  Map<String,dynamic> _forecastPayload(InventorySnapshot s,String animalId){
    if(!s.canManage||!universalEnabled||s.userId!=client.auth.currentUser?.id)throw StateError('Operación no autorizada');
    final row=s.records.where((r)=>r['animal_id']==animalId&&r['deleted_at']==null).firstOrNull;
    if(row==null)throw StateError('Animal no disponible');
    return Map<String,dynamic>.from(row['payload'] as Map);
  }
  @override Future<void> createForecast(InventorySnapshot s,String animalId,String id,ForecastDraft draft)async{
    _forecastPayload(s,animalId);
    if(!draft.valid)throw ArgumentError('Pronóstico inválido');
    await queueOperation(s,'forecast.create',id,draft.changes(animalId));
  }
  @override Future<void> deleteForecast(InventorySnapshot s,String animalId,String id)async{
    final payload=_forecastPayload(s,animalId);
    final raw=(payload['forecasts'] as List).whereType<Map>().where((f)=>f['id']==id&&f['animalId']==animalId).firstOrNull;
    if(raw==null)throw StateError('Pronóstico no disponible');
    await queueOperation(s,'forecast.delete',id,{'animalId':animalId},revision:await _revision(s,'forecast',id,raw));
  }
  @override Future<void> setWeightTarget(InventorySnapshot s,String animalId,double? minimum,double? maximum)async{
    final payload=_forecastPayload(s,animalId);
    if((minimum==null)!=(maximum==null)||(minimum!=null&&(!minimum.isFinite||!maximum!.isFinite||minimum<0||maximum>100000||minimum>maximum)))throw ArgumentError('Rango inválido');
    await queueOperation(s,'animal.target.update',animalId,{'minimum':minimum,'maximum':maximum},revision:await _revision(s,'animal',animalId,payload['animal']));
  }
  final bool journeyRpcEnabled;
  @override bool get supportsJourneyResume=>journeyRpcEnabled||universalEnabled;
  final bool eventRpcEnabled;
  final void Function()? onSynced;
  bool _syncing=false;
  int _loadGeneration=0;
  @override Future<List<PendingEvent>> pendingEvents()async{
    final id=client.auth.currentUser?.id;
    if(id==null||client.auth.currentSession==null)return [];
    final result=await store?.pending(id)??[];
    return client.auth.currentUser?.id==id?result:[];
  }
  @override Future<void> discardPending(PendingEvent event)async{
    final id=client.auth.currentUser?.id;
    if(id==null||id!=event.userId||client.auth.currentSession==null||_syncing)throw StateError('Espera a que termine la sincronización.');
    _syncing=true;
    try{
      if(event.operation!=null){
        if(!['conflict','rejected'].contains(event.state))throw StateError('Una operación RPC sin confirmación no se puede descartar.');
        await store?.archiveConflict(event);
      }else{await store?.acknowledge(event);}
    }finally{_syncing=false;}
  }
  @override Future<void> syncEvents({bool manual=false})async{
    final db=store,id=client.auth.currentUser?.id;
    if(db==null||id==null||client.auth.currentSession==null||_syncing)return;
    _syncing=true;
    var changed=false;
    final holder=const Uuid().v4();
    try{
      if(!await db.acquireDeliveryLease(holder,DateTime.now().millisecondsSinceEpoch))return;
      if(universalEnabled){
        final c=await client.rpc('get_my_ranch_context');
        if(client.auth.currentUser?.id==id&&c is Map&&c['status']=='active'&&c['owner_id'] is String){await _universal.flush(id,c['owner_id'] as String,holder,manual:manual);changed=true;}
      }
      for(final p in await db.pending(id)){
        if(client.auth.currentUser?.id!=id||client.auth.currentSession==null)break;
        if(p.state!='pending')continue;
        if(p.operation!=null&&!eventRpcEnabled)continue;
        if(!manual&&p.nextAt>DateTime.now().millisecondsSinceEpoch)continue;
        try{
          if(!await db.acquireDeliveryLease(holder,DateTime.now().millisecondsSinceEpoch))break;
          if(p.operation!=null){
            final operation=p.operation!;
            final operationId=operation['operationId'];
            if(operationId is! String||operation['ownerId']!=p.ownerId||operation['entityId']!=p.draft.id)throw StateError('Operación local inválida.');
            final raw=await client.rpc('sync_apply_operation',params:{'p_operation':operation}).timeout(const Duration(seconds:20));
            if(client.auth.currentUser?.id!=id||client.auth.currentSession==null)break;
            final receipt=parseEventReceipt(raw,operationId);
            final status=receipt['status'] as String;
            if(status=='applied'||status=='duplicate'){
              await db.confirmRpc(p,receipt);
              changed=true;
            }else if(status=='conflict'||status=='rejected'){
              await db.stopRpc(p,status,receipt['code'] as String);
            }else{
              throw StateError('El servidor solicita reintentar.');
            }
          }else{
            // Never convert an already attempted legacy event to RPC:
            // a previous response could have been lost after server commit.
            await _sendEvent(outboxScope(p),p.animalId,p.draft);
            await db.acknowledge(p);
            changed=true;
          }
        }catch(e){
          final seconds=math.min(900,30*(1<<math.min(p.attempts,5)));
          final message=e is StateError?e.message.toString():e is PostgrestException&&e.code=='42501'?'Permiso denegado. Revisa tu membresía.':'No se confirmó el envío. Se reintentará.';
          await db.retry(p,message,DateTime.now().add(Duration(seconds:seconds)).millisecondsSinceEpoch);
        }
      }
    }finally{try{await db.releaseDeliveryLease(holder);}finally{_syncing=false;if(changed&&client.auth.currentUser?.id==id)onSynced?.call();}}
  }
  final OfflineStore? store;
  final SupabaseClient client;

  @override
  Future<InventorySnapshot> load() async {
    final id=client.auth.currentUser?.id;
    if(id==null||client.auth.currentSession==null)throw StateError('Sesión no disponible');
    final generation=++_loadGeneration;
    bool valid()=>generation==_loadGeneration&&client.auth.currentUser?.id==id&&client.auth.currentSession!=null;
    InventorySnapshot result;
    try {result=await _loadRemote(onMembership:(ownerId)async{
      if(!valid())throw StateError('Consulta reemplazada o sesión modificada.');
      if(ownerId==null){await store?.purge(id);}else{await store?.invalidateOtherRanch(id,ownerId);}
    }).timeout(const Duration(seconds:25));}
    catch(e){
      if(!valid())rethrow;
      final network=e is SocketException||e is TimeoutException||e is AuthRetryableFetchException||e is http.ClientException;
      if(!network){await store?.purge(id);rethrow;}
      final cached=await store?.read(id);
      if(cached==null||!valid())rethrow;
      return cached;
    }
    if(!valid())throw StateError('La consulta o sesión cambió');
    try{if(result.status=='active'){await store?.save(result);}else{await store?.purge(id);}}catch(_){}
    if(!valid()){
      if(client.auth.currentUser?.id!=id||client.auth.currentSession==null)await store?.purge(id);
      throw StateError('La consulta o sesión cambió');
    }
    return result;
  }
  Future<InventorySnapshot> _loadRemote({Future<void> Function(String?)? onMembership}) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sesión no disponible');
    void verifySession() {
      if (client.auth.currentUser?.id != userId) throw StateError('La sesión cambió');
    }
    final raw = await client.rpc('get_my_ranch_context');
    verifySession();
    if (raw is! Map) throw const FormatException('Contexto de rancho inválido');
    final status = raw['status'];
    if (status == 'pending' || status == 'unassigned') {
      await onMembership?.call(null);
      verifySession();
      return InventorySnapshot(status: status as String);
    }
    final ownerId = raw['owner_id'];
    if (status != 'active' || ownerId is! String || ownerId.isEmpty) {
      throw StateError('No se pudo verificar la membresía');
    }
    await onMembership?.call(ownerId);
    verifySession();
    final mirror=incrementalEnabled?await _universal.pull(userId,ownerId):null;
    final remoteRows=mirror==null?null:(mirror['records'] as List).cast<Map>();
    final config = remoteRows==null?await client.from('ranch_animal_configs')
        .select('config,revision').eq('owner_id', ownerId).maybeSingle():remoteRows.where((r)=>r['kind']=='config').map((r)=>Map<String,dynamic>.from(r['record'] as Map)).firstOrNull;
    verifySession();
    final options = <String, bool>{};
    final labels = <String, String>{};
    final settings = config?['config'];
    if (settings is Map && settings['lists'] is Map) {
      final statuses = (settings['lists'] as Map)['status'];
      if (statuses is List) {
        for (final item in statuses.whereType<Map>()) {
          final value = item['value'];
          if (value is String) {
            options.putIfAbsent(value, () => item['active'] != false);
            if (item['label'] is String) labels.putIfAbsent(value, () => item['label'] as String);
          }
        }
      }
    }
    const pageSize = 200;
    final records = <Map<String, dynamic>>[];
    // Stable keyset pagination avoids the default PostgREST row limit.
    String? lastId;
    if(remoteRows!=null){records.addAll(remoteRows.where((r)=>r['kind']=='animal'&&(r['record'] as Map)['deleted_at']==null).map((r)=>Map<String,dynamic>.from(r['record'] as Map)));}
    while (remoteRows==null) {
      verifySession();
      var query = client.from('animal_sync_records')
          .select('animal_id,deleted_at,modified_at,payload')
          .eq('owner_id', ownerId).isFilter('deleted_at', null);
      if (lastId != null) query = query.gt('animal_id', lastId);
      final page = await query.order('animal_id', ascending: true).limit(pageSize);
      verifySession();
      if (page.isEmpty) break;
      records.addAll(page);
      final next = page.last['animal_id'];
      if (next is! String || next == lastId) throw const FormatException('Paginación inválida');
      lastId = next;
    }
    // Recheck membership before exposing results, including revocation mid-load.
    final current = await client.rpc('get_my_ranch_context');
    verifySession();
    if (current is! Map || current['status'] != 'active' || current['owner_id'] != ownerId) {
      throw StateError('La membresía cambió');
    }
    return InventorySnapshot(
      status: 'active',
      ranchName: current['ranch_name']?.toString() ?? 'Mi rancho',
      role: current['role']?.toString() ?? '',
      records: records,
      statusOptions: options,
      statusLabels: labels,
      ownerId: ownerId, userId: userId,
      config: settings is Map ? Map<String,dynamic>.from(settings) : {},
      configRevision: config?['revision'] as int? ?? 0,
    );
  }

  @override
  Future<void> saveAnimal(InventorySnapshot original, String? id, Map<String,dynamic> changes) async {
    final current = await _loadRemote();
    if (!original.canManage || !current.canManage || current.ownerId != original.ownerId || current.userId != original.userId || current.configRevision != original.configRevision) {
      throw StateError('La sesión, permisos o configuración cambiaron. Actualiza el inventario.');
    }
    final config = AnimalFormConfig(current.config);
    final existing = id == null ? null : current.records.where((r)=>r['animal_id']==id).firstOrNull;
    final prior = id == null ? null : original.records.where((r)=>r['animal_id']==id).firstOrNull;
    if(id != null && (existing == null || prior == null || existing['modified_at'] == null || existing['modified_at'] != prior['modified_at'])) {
      throw StateError('La ficha cambió en otro dispositivo. Actualiza antes de editar.');
    }
    final payload = existing == null ? <String,dynamic>{'events':[], 'photos':[], 'forecasts':[]} : Map<String,dynamic>.from(existing['payload'] as Map);
    final animal = existing == null ? <String,dynamic>{'status':'Activo'} : Map<String,dynamic>.from(payload['animal'] as Map);
    final animalId = id ?? const Uuid().v4();
    final status = (changes['status'] ?? animal['status'] ?? 'Activo').toString();
    final origin = (changes['originType'] ?? animal['originType'] ?? '').toString();
    for(final entry in changes.entries) {
      final field = animalFields.where((f)=>f.id==entry.key).firstOrNull;
      if(field == null || !config.visible(field) || !config.applies(field,status,origin)) throw StateError('Campo no editable: ${entry.key}');
      final value = entry.value;
      if(value is String && value.length > 4000) throw StateError('Texto demasiado largo.');
      final options = config.choices(field.id);
      if(options.isNotEmpty && value is String && value.isNotEmpty && !options.containsKey(value) && value != animal[field.id]) throw StateError('Opción no autorizada.');
      animal[entry.key]=value;
    }
    for(final field in animalFields.where((f)=>config.visible(f)&&config.applies(f,status,origin)&&config.requiredField(f))) {
      final value = animal[field.id];
      if(field.id=='estimatedAge' && (animal['birthDate']?.toString()??'').isNotEmpty) continue;
      if(value==null || value=='') throw StateError('Completa ${config.label(field)}.');
    }
    final birth = animal['birthDate']?.toString()??'';
    if(birth.isNotEmpty && (DateTime.tryParse(birth)==null || DateTime.parse(birth).isAfter(DateTime.now()))) throw StateError('Fecha de nacimiento inválida.');
    if(birth.isNotEmpty && animal['estimatedAge'] is Map) throw StateError('Indica fecha de nacimiento o edad estimada, no ambas.');
    final tag = (animal['tag']??'').toString().trim().toLowerCase();
    if(tag.isNotEmpty && current.animals.any((a)=>a.id!=animalId&&a.value('tag').toLowerCase()==tag)) throw StateError('Ya existe ese número de arete.');
    for(final key in ['motherId','fatherId']) {
      final parent=animal[key]?.toString()??'';
      if(parent.isNotEmpty && (parent==animalId || !current.animals.any((a)=>a.id==parent))) throw StateError('Referencia de progenitor inválida.');
    }
    final actor = await client.rpc('get_my_ranch_context');
    if(client.auth.currentUser?.id!=current.userId || actor is! Map || actor['owner_id']!=current.ownerId || actor['status']!='active' || !['owner','admin'].contains(actor['role'])) throw StateError('Permisos cambiaron.');
    final label=actor['display_name']?.toString()??client.auth.currentUser?.email??'Usuario autenticado';
    final now=DateTime.now().toUtc();
    final previous=DateTime.tryParse(animal['updatedAt']?.toString()??'');
    final stamp=(previous!=null&&!now.isAfter(previous)?previous.add(const Duration(milliseconds:1)):now).toIso8601String();
    animal['id']=animalId;
    animal['updatedAt']=stamp;
    animal['updatedBy']=label;
    if(existing==null) {
      var maximum=0;
      for(final a in current.animals) {
        final m=RegExp(r'^ANM-(\d{5,})$').firstMatch(a.value('internalId'));
        final n=int.tryParse(m?.group(1)??'')??0;
        if(n>maximum) maximum=n;
      }
      animal['internalId']='ANM-${(maximum+1).toString().padLeft(5,'0')}';
      animal['createdAt']=stamp;
      animal['createdBy']=label;
    }
    payload['animal']=animal;
    if(universalEnabled){
      final old=existing==null?null:(existing['payload'] as Map)['animal'];
      final revision=existing==null?null:await _revision(current,'animal',animalId,old);
      final oldStatus=old is Map?old['status']?.toString():null;
      if(oldStatus!=null&&config.active(oldStatus)!=config.active(status)){
        final active=config.active(status);
        await queueOperation(current,active?'animal.restore':'animal.archive',animalId,{'status':status,if(!active&&changes.containsKey('exitReason'))'exitReason':changes['exitReason'],if(!active&&changes.containsKey('exitNotes'))'exitNotes':changes['exitNotes']},revision:revision);
      }else{await queueOperation(current,existing==null?'animal.create':'animal.update',animalId,{'fields':changes},revision:revision);}
      return;
    }
    if(existing==null) {
      await client.from('animal_sync_records').insert({'owner_id':current.ownerId,'animal_id':animalId,'payload':payload}).select('animal_id').single();
    } else {
      final result=await client.from('animal_sync_records').update({'payload':payload}).eq('owner_id',current.ownerId).eq('animal_id',animalId).eq('modified_at',existing['modified_at'] as String).isFilter('deleted_at',null).select('animal_id').maybeSingle();
      if(result==null) throw StateError('La ficha cambió durante el guardado. Actualiza e inténtalo otra vez.');
    }
  }

  @override
  Future<void> setAnimalStatus(InventorySnapshot snapshot,String animalId,String status) async {
    if(!snapshot.canManage)throw StateError('Solo administradores pueden modificar el estado.');
    final before=snapshot.animals.where((a)=>a.id==animalId).firstOrNull;
    if(before==null)throw StateError('Animal no encontrado.');
    final config=AnimalFormConfig(snapshot.config);
    if(!config.choices('status').containsKey(status)||before.active==config.active(status))throw StateError('Selecciona un estado válido para esta transición.');
    // Reuse configured required fields, version and membership checks. Do not
    // bypass the form if a reason for archiving is required.
    await saveAnimal(snapshot,animalId,{'status':status});
    onSynced?.call();
  }

  Future<Map<dynamic,dynamic>> _photoContext(InventorySnapshot snapshot,{required bool write}) async {
    if(snapshot.ownerId.isEmpty || snapshot.userId.isEmpty || client.auth.currentUser?.id!=snapshot.userId) throw StateError('La sesión cambió.');
    final context=await client.rpc('get_my_ranch_context');
    if(client.auth.currentUser?.id!=snapshot.userId || context is! Map || context['status']!='active' || context['owner_id']!=snapshot.ownerId || (write && !['owner','admin'].contains(context['role']))) throw StateError('No tienes permiso para esta operación.');
    return context;
  }

  @override
  Future<Uint8List> readPhoto(InventorySnapshot snapshot,String animalId,AnimalPhoto photo) async {
    await _photoContext(snapshot,write:false);
    if(!AnimalPhoto.fromSnapshot(snapshot,animalId).any((p)=>p.id==photo.id&&p.path==photo.path)) throw StateError('Fotografía inválida.');
    final bytes=await client.storage.from('animal-photos').download(photo.path);
    if(client.auth.currentUser?.id!=snapshot.userId) throw StateError('La sesión cambió.');
    return bytes;
  }
  Future<Map<String,dynamic>> _photoRow(InventorySnapshot snapshot,String animalId) async {
    if(!snapshot.canManage) throw StateError('No tienes permiso.');
    await _photoContext(snapshot,write:true);
    final prior=snapshot.records.where((r)=>r['animal_id']==animalId).firstOrNull;
    final row=await client.from('animal_sync_records').select('modified_at,payload').eq('owner_id',snapshot.ownerId).eq('animal_id',animalId).isFilter('deleted_at',null).maybeSingle();
    if(row==null||prior==null||row['modified_at']!=prior['modified_at']||row['modified_at'] is! String) throw StateError('La ficha cambió. Actualiza el inventario.');
    return row;
  }
  Future<void> _writePhotos(InventorySnapshot snapshot,String animalId,Map<String,dynamic> row,List<Map<String,dynamic>> photos) async {
    final actor=await _photoContext(snapshot,write:true);
    final payload=Map<String,dynamic>.from(row['payload'] as Map);
    final animal=Map<String,dynamic>.from(payload['animal'] as Map);
    final now=DateTime.now().toUtc();
    final previous=DateTime.tryParse(animal['updatedAt']?.toString()??'');
    animal['updatedAt']=(previous!=null&&!now.isAfter(previous)?previous.add(const Duration(milliseconds:1)):now).toIso8601String();
    animal['updatedBy']=actor['display_name']?.toString()??'Usuario autenticado';
    payload['animal']=animal;
    payload['photos']=photos;
    final result=await client.from('animal_sync_records').update({'payload':payload}).eq('owner_id',snapshot.ownerId).eq('animal_id',animalId).eq('modified_at',row['modified_at'] as String).isFilter('deleted_at',null).select('animal_id').maybeSingle();
    if(result==null) throw StateError('La ficha cambió durante el guardado. Actualiza el inventario.');
  }
  List<Map<String,dynamic>> _photoList(Map<String,dynamic> row) {
    final raw=(row['payload'] as Map)['photos'];
    if(raw is! List || raw.any((p)=>p is! Map)) throw StateError('Galería inválida.');
    return raw.map((p)=>Map<String,dynamic>.from(p as Map)).toList();
  }
  @override
  Future<void> addPhoto(InventorySnapshot snapshot,String animalId,Uint8List bytes,String name) async {
    final mime=imageMime(bytes);
    if(mime==null||bytes.length>10*1024*1024) throw StateError('Selecciona JPEG, PNG o WebP de hasta 10 MB.');
    final row=await _photoRow(snapshot,animalId);
    final photos=_photoList(row);
    final id=const Uuid().v4();
    final path='${snapshot.ownerId}/$animalId/$id';
    await _photoContext(snapshot,write:true);
    if(universalEnabled){await queueOperation(snapshot,'photo.create',id,{'animalId':animalId,'mime':mime,'name':name,'primary':photos.isEmpty},attachment:base64Encode(bytes));return;}
    await client.storage.from('animal-photos').uploadBinary(path,bytes,fileOptions:FileOptions(contentType:mime,upsert:false));
    photos.add({'id':id,'animalId':animalId,'name':name,'mime':mime,'primary':photos.isEmpty,'createdAt':DateTime.now().toUtc().toIso8601String(),'cropX':50,'cropY':50,'storagePath':path});
    // Never delete after an ambiguous network failure: the row may have committed.
    await _writePhotos(snapshot,animalId,row,photos);
  }
  @override
  Future<void> primaryPhoto(InventorySnapshot snapshot,String animalId,String photoId) async {
    final row=await _photoRow(snapshot,animalId);
    final photos=_photoList(row);
    if(!photos.any((p)=>p['id']==photoId&&p['animalId']==animalId)) throw StateError('Fotografía no encontrada.');
    for(final p in photos){p['primary']=p['id']==photoId;}
    await _writePhotos(snapshot,animalId,row,photos);
  }

  @override
  Future<void> removePhoto(InventorySnapshot snapshot,String animalId,String photoId) async {
    final row=await _photoRow(snapshot,animalId);
    final photos=_photoList(row);
    final matches=photos.where((p)=>p['id']==photoId&&p['animalId']==animalId&&p['storagePath']=='${snapshot.ownerId}/$animalId/$photoId').toList();
    if(matches.length!=1)throw StateError('Fotografía no encontrada o inválida.');
    if(universalEnabled){await queueOperation(snapshot,'photo.delete',photoId,{'animalId':animalId},revision:await _revision(snapshot,'photo',photoId,matches.single));return;}
    final wasPrimary=matches.single['primary']==true;
    photos.remove(matches.single);
    if(wasPrimary&&photos.isNotEmpty){
      for(var i=0;i<photos.length;i++){photos[i]['primary']=i==0;}
    }
    // Only unlink metadata with CAS. Do not delete bytes: a stale client may
    // still refer to them, and a separate GC policy is required.
    await _writePhotos(snapshot,animalId,row,photos);
  }

  @override
  Future<void> addEvent(InventorySnapshot snapshot,String animalId,EventDraft draft) async {
    draft.validate();
    final db=store;
    if(db==null){if(eventRpcEnabled)throw StateError('Almacenamiento local no disponible.');await _sendEvent(snapshot,animalId,draft);return;}
    if(snapshot.status!='active'||!['owner','admin','worker'].contains(snapshot.role)||snapshot.userId.isEmpty||snapshot.ownerId.isEmpty||client.auth.currentSession==null||client.auth.currentUser?.id!=snapshot.userId||!snapshot.animals.any((a)=>a.id==animalId&&a.active))throw StateError('Sesión o animal inválido.');
    if(snapshot.offline&&(snapshot.cachedAt==null||DateTime.now().difference(snapshot.cachedAt!).isNegative||DateTime.now().difference(snapshot.cachedAt!)>const Duration(hours:24)))throw StateError('Actualiza el inventario antes de registrar.');
    if(universalEnabled){await queueOperation(snapshot,'event.create',draft.id,{'animalId':animalId,'type':draft.type,'date':draft.date,if(draft.type=='weight')'weight':draft.weight,if(draft.product.trim().isNotEmpty)'product':draft.product.trim(),if(draft.notes.trim().isNotEmpty)'notes':draft.notes.trim()});return;}
    await db.enqueue(PendingEvent(userId:snapshot.userId,ownerId:snapshot.ownerId,animalId:animalId,draft:draft),rpc:eventRpcEnabled);
    unawaited(syncEvents().catchError((Object _){ }));
  }
  Future<void> _sendEvent(InventorySnapshot snapshot,String animalId,EventDraft draft) async {
    draft.validate();
    if(snapshot.status!='active'||!['owner','admin','worker'].contains(snapshot.role)||snapshot.userId.isEmpty||client.auth.currentUser?.id!=snapshot.userId)throw StateError('Sesión o permisos inválidos.');
    final fresh=await _loadRemote();
    if(fresh.status!='active'||fresh.ownerId!=snapshot.ownerId||fresh.userId!=snapshot.userId||!['owner','admin','worker'].contains(fresh.role))throw StateError('La membresía cambió.');
    final animal=fresh.animals.where((a)=>a.id==animalId).firstOrNull;
    final row=fresh.records.where((r)=>r['animal_id']==animalId).firstOrNull;
    if(animal==null||!animal.active||row==null||row['modified_at'] is! String)throw StateError('El animal ya no está activo.');
    final payload=Map<String,dynamic>.from(row['payload'] as Map);
    final raw=payload['events'];
    if(raw is! List||raw.any((e)=>e is! Map))throw StateError('Historial inválido.');
    final events=raw.map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    final actorContext=await client.rpc('get_my_ranch_context');
    final user=client.auth.currentUser;
    if(user==null||user.id!=snapshot.userId||actorContext is! Map||actorContext['owner_id']!=snapshot.ownerId||actorContext['status']!='active'||!['owner','admin','worker'].contains(actorContext['role'])||actorContext['display_name'] is! String)throw StateError('Permisos cambiaron.');
    final actor=<String,dynamic>{'authUserId':user.id,'email':user.email??'','label':actorContext['display_name']};
    final prior=events.where((e)=>e['id']==draft.id).firstOrNull;
    if(prior!=null){
      if(prior['animalId']==animalId&&prior['type']==draft.type&&prior['date']==draft.date&&(draft.type!='weight'||prior['weight']==draft.weight)&&(prior['label']??'')==draft.product.trim()&&(prior['notes']??'')==draft.notes.trim()&&prior['performedBy'] is Map&&(prior['performedBy'] as Map)['authUserId']==user.id)return;
      throw StateError('El identificador ya existe con otros datos.');
    }
    final now=DateTime.now().toUtc();
    events.add(draft.toEvent(animalId,actor,now));
    payload['events']=events;
    // Worker trigger requires the animal and all other payload fields unchanged.
    if(actorContext['role']!='worker'){
      final fields=Map<String,dynamic>.from(payload['animal'] as Map);
      final previous=DateTime.tryParse(fields['updatedAt']?.toString()??'');
      fields['updatedAt']=(previous!=null&&!now.isAfter(previous)?previous.add(const Duration(milliseconds:1)):now).toIso8601String();
      fields['updatedBy']=actor['label'];
      payload['animal']=fields;
    }
    final result=await client.from('animal_sync_records').update({'payload':payload}).eq('owner_id',snapshot.ownerId).eq('animal_id',animalId).eq('modified_at',row['modified_at'] as String).isFilter('deleted_at',null).select('animal_id').maybeSingle();
    if(result==null)throw StateError('El historial cambió durante el guardado. Reintenta sin cerrar el formulario.');
  }

  Future<Map<dynamic,dynamic>> _journeyContext(InventorySnapshot s)async{
    if(s.status!='active'||s.userId.isEmpty||client.auth.currentUser?.id!=s.userId)throw StateError('Sesión inválida.');
    final c=await client.rpc('get_my_ranch_context');
    if(client.auth.currentUser?.id!=s.userId||c is! Map||c['status']!='active'||c['owner_id']!=s.ownerId||!['owner','admin','worker'].contains(c['role']))throw StateError('La membresía cambió.');
    return c;
  }
  @override bool get supportsOfflineJourneys=>universalEnabled&&store!=null;
  void _journeyCaptureScope(InventorySnapshot s){
    if(!supportsOfflineJourneys||s.status!='active'||s.userId!=client.auth.currentUser?.id||client.auth.currentSession==null||!['owner','admin','worker'].contains(s.role))throw StateError('Sesión o membresía no disponible');
    if(s.offline&&(s.cachedAt==null||DateTime.now().difference(s.cachedAt!).isNegative||DateTime.now().difference(s.cachedAt!)>const Duration(hours:24)))throw StateError('Actualiza la membresía con conexión');
  }
  Future<int> _journeyRevision(InventorySnapshot s,Journey j)async{
    _journeyCaptureScope(s);
    if(!s.offline)return _revision(s,'journey',j.id,j.payload);
    final cached=await store!.readJourneyCache(s.userId,s.ownerId,project);
    final row=cached.where((r)=>r['id']==j.id).firstOrNull;
    if(row==null||row['revision'] is! int||!_sameJson(row['payload'],j.payload))throw StateError('Descarga la revisión de la jornada antes de capturar');
    return row['revision'] as int;
  }
  Future<void> _queueJourneyChange(InventorySnapshot s,Journey j,String action,Map<String,dynamic> changes)async{
    final revision=await _journeyRevision(s,j);
    final pending=await store!.universalPending(s.userId,s.ownerId);
    if(pending.any((r){
      final op=r['operation'] as Map;
      return op['entityId']==j.id&&(op['action'] as String).startsWith('journey.')&&(action!='journey.attend'||op['action']!='journey.attend'||(op['changes'] as Map)['animalId']==changes['animalId']);
    }))throw StateError('Hay una operación pendiente para esta jornada o animal');
    await queueOperation(s,action,j.id,changes,revision:revision);
  }
  @override Future<Set<String>> pendingJourneyAnimals(InventorySnapshot s,String journeyId)async{
    if(!supportsOfflineJourneys)return {};
    _journeyCaptureScope(s);
    return (await store!.universalPending(s.userId,s.ownerId)).map((r)=>r['operation'] as Map).where((op)=>op['action']=='journey.attend'&&op['entityId']==journeyId).map((op)=>(op['changes'] as Map)['animalId'] as String).toSet();
  }
  Future<void> _cacheJourneys(InventorySnapshot s,List<Journey> result)async{
    if(!supportsOfflineJourneys)return;
    final rows=<Map<String,dynamic>>[];
    for(final j in result){
      int? revision;
      try{revision=await _revision(s,'journey',j.id,j.payload);}catch(_){_universal.verify(s.userId);}
      rows.add({'id':j.id,'version':j.version,'payload':j.payload,'revision':revision});
    }
    await _journeyContext(s);
    await store!.saveJourneyCache(s.userId,s.ownerId,project,rows);
  }
  @override Future<void> createCustomJourney(InventorySnapshot s,String id,String name,String date,String product,String dose,String notes,Set<String> animalIds)async{
    _journeyCaptureScope(s);
    if(!['owner','admin'].contains(s.role)||name.trim().isEmpty||name.length>120)throw StateError('Actividad personalizada no autorizada');
    if(!s.offline)await _journeyContext(s);
    if(animalIds.isEmpty||!animalIds.every((id)=>s.animals.any((a)=>a.id==id&&a.active)))throw StateError('Selección inválida');
    await queueOperation(s,'journey.create',id,{'type':'other','name':name.trim(),'date':date,'product':product,'dose':dose,'notes':notes,'animalIds':animalIds.toList()});
  }
  @override Future<void> addJourneyAnimals(InventorySnapshot s,Journey j,Set<String> animalIds)async{
    _journeyCaptureScope(s);
    if(!j.open||(j.type=='other'&&s.role=='worker')||animalIds.isEmpty||!animalIds.every((id)=>s.animals.any((a)=>a.id==id&&a.active)&&!j.roster.any((a)=>a['id']==id)))throw StateError('Selección no disponible');
    await _queueJourneyChange(s,j,'journey.add_animals',{'animalIds':animalIds.toList()});
  }
  @override Future<List<Journey>> journeys(InventorySnapshot s)async{
    if(s.offline){
      _journeyCaptureScope(s);
      final cached=await store!.readJourneyCache(s.userId,s.ownerId,project);
      _universal.verify(s.userId);
      return cached.map((r)=>Journey(r['id'] as String,r['version'] as String,Map<String,dynamic>.from(r['payload'] as Map),revision:r['revision'] as int?)).toList();
    }
    await _journeyContext(s);
    final result=<Journey>[];
    if(incrementalEnabled){
      final mirror=await _universal.pull(s.userId,s.ownerId);
      for(final raw in (mirror['records'] as List).where((r)=>r['kind']=='journey')){final row=raw['record'] as Map;result.add(Journey(row['journey_id'] as String,row['updated_at'] as String,Map<String,dynamic>.from(row['payload'] as Map)));}
      await _journeyContext(s);result.sort((a,b)=>b.date.compareTo(a.date));await _cacheJourneys(s,result);return result;
    }
    String? last;
    while(true){
      var q=client.from('journey_sync_records').select('journey_id,updated_at,payload').eq('owner_id',s.ownerId);
      if(last!=null)q=q.gt('journey_id',last);
      final rows=await q.order('journey_id').limit(200);
      if(rows.isEmpty)break;
      for(final row in rows){
        result.add(Journey(row['journey_id'] as String,row['updated_at'] as String,Map<String,dynamic>.from(row['payload'] as Map)));
      }
      last=rows.last['journey_id'] as String;
    }
    await _journeyContext(s);
    result.sort((a,b)=>b.date.compareTo(a.date));
    await _cacheJourneys(s,result);
    return result;
  }
  @override Future<void> createJourney(InventorySnapshot s,String id,String type,String date,String product,String dose,String notes,Set<String> animalIds)async{
    EventDraft(id:id,type:type,date:date,weight:type=='weight'?0:null).validate();
    if(s.offline){_journeyCaptureScope(s);if(animalIds.isEmpty||!animalIds.every((id)=>s.animals.any((a)=>a.id==id&&a.active)))throw StateError('Selección inválida');await queueOperation(s,'journey.create',id,{'type':type,'date':date,'animalIds':animalIds.toList(),'product':product,'dose':dose,'notes':notes});return;}
    await _journeyContext(s);
    final fresh=await _loadRemote();
    if(fresh.ownerId!=s.ownerId||fresh.userId!=s.userId||fresh.status!='active')throw StateError('La membresía cambió.');
    final roster=fresh.animals.where((a)=>a.active&&animalIds.contains(a.id)).map(Journey.rosterEntry).toList();
    if(roster.isEmpty||roster.length!=animalIds.length)throw StateError('Actualiza la selección de animales.');
    if(universalEnabled){await queueOperation(s,'journey.create',id,{'type':type,'date':date,'animalIds':animalIds.toList(),'product':product,'dose':dose,'notes':notes});return;}
    final prior=await client.from('journey_sync_records').select('journey_id').eq('owner_id',s.ownerId).eq('journey_id',id).maybeSingle();
    if(prior!=null)return;
    final now=DateTime.now().toUtc().toIso8601String();
    await _journeyContext(s);
    await client.from('journey_sync_records').insert({'owner_id':s.ownerId,'journey_id':id,'payload':{'id':id,'type':type,'name':'','date':date,'product':product,'dose':dose,'notes':notes,'roster':roster,'status':'in_progress','createdAt':now,'updatedAt':now,'completedAt':null}}).select('journey_id').single();
  }
  @override Future<void> attendJourney(InventorySnapshot s,Journey j,String animalId,double? weight)async{
    if(universalEnabled){
      _journeyCaptureScope(s);
      if(!j.open||(j.type=='other'&&s.role=='worker')||!j.roster.any((a)=>a['id']==animalId)||!s.animals.any((a)=>a.id==animalId&&a.active))throw StateError('Animal o jornada no disponible');
      if(j.type=='weight'?(weight==null||!weight.isFinite||weight<0||weight>100000):weight!=null)throw StateError('Peso inválido');
      await _queueJourneyChange(s,j,'journey.attend',{'animalId':animalId,if(weight!=null)'weight':weight});
      return;
    }
    final fresh=await _loadRemote();
    if(fresh.ownerId!=s.ownerId||fresh.userId!=s.userId||!fresh.animals.any((a)=>a.id==animalId&&a.active))throw StateError('El animal ya no está activo.');
    final c=await _journeyContext(s);
    final row=await client.from('journey_sync_records').select('updated_at,payload').eq('owner_id',s.ownerId).eq('journey_id',j.id).maybeSingle();
    if(row==null||row['updated_at']!=j.version)throw StateError('La jornada cambió. Actualiza antes de continuar.');
    final current=Journey(j.id,j.version,Map<String,dynamic>.from(row['payload'] as Map));
    if(!current.open||!eventTypes.containsKey(current.type))throw StateError('Jornada no editable.');
    final roster=current.roster;
    final a=roster.where((a)=>a['id']==animalId).firstOrNull;
    if(a==null)throw StateError('Animal no incluido.');
    if(current.type=='weight'&&(weight==null||!weight.isFinite||weight<0||weight>100000))throw StateError('Peso inválido.');
    final user=client.auth.currentUser;
    if(user==null||user.id!=s.userId||c['display_name'] is! String)throw StateError('Sesión inválida.');
    final actor={'authUserId':user.id,'email':user.email??'','label':c['display_name']};
    final now=DateTime.now().toUtc().toIso8601String();
    if(a['attended']!=true){a['attended']=true;a['attendedAt']=now;a['attendedBy']=actor;}
    if(current.type=='weight'){a['weight']=weight;a['weightUpdatedAt']=now;a['weightUpdatedBy']=actor;}
    final payload={...current.payload,'roster':roster,'updatedAt':now};
    final saved=await client.from('journey_sync_records').update({'payload':payload}).eq('owner_id',s.ownerId).eq('journey_id',j.id).eq('updated_at',j.version).select('journey_id').maybeSingle();
    if(saved==null)throw StateError('La jornada cambió durante el guardado.');
  }

  @override Future<void> resumeJourney(InventorySnapshot s,Journey j)async{
    if(!supportsJourneyResume||s.offline||j.status!='incomplete'||j.pending==0)throw StateError('La jornada no se puede reanudar.');
    final c=await _journeyContext(s);
    if(!['owner','admin'].contains(c['role']))throw StateError('Solo administradores pueden reanudar jornadas.');
    if(universalEnabled){await _queueJourneyChange(s,j,'journey.resume',{});return;}
    await client.rpc('resume_ranch_journey_v1',params:{'p_owner_id':s.ownerId,'p_journey_id':j.id,'p_expected_version':j.version});
    if(client.auth.currentUser?.id==s.userId)onSynced?.call();
  }

  @override Future<void> finishJourney(InventorySnapshot s,Journey j)async{
    final c=await _journeyContext(s);
    if(!['owner','admin'].contains(c['role'])||s.offline)throw StateError('Solo administradores pueden finalizar jornadas.');
    if(universalEnabled){await _queueJourneyChange(s,j,'journey.finish',{'allowIncomplete':j.pending>0});return;}
    if(journeyRpcEnabled){
      await client.rpc('finish_ranch_journey_v1',params:{'p_owner_id':s.ownerId,'p_journey_id':j.id,'p_expected_version':j.version,'p_allow_incomplete':j.pending>0});
    }else{
      await client.rpc('finish_mobile_journey',params:{'p_owner_id':s.ownerId,'p_journey_id':j.id,'p_expected_version':j.version});
    }
    if(client.auth.currentUser?.id==s.userId)onSynced?.call();
  }
}
