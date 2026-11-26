import 'dart:typed_data';
import '../domain/animal_photos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/inventory.dart';
import '../../journeys/domain/journey.dart';
import '../domain/event_draft.dart';
import '../domain/animal_form_config.dart';
import 'package:uuid/uuid.dart';

class SupabaseInventoryRepository implements InventoryRepository, AnimalWriter, AnimalPhotos, AnimalEventWriter, JourneyRepository {
  const SupabaseInventoryRepository(this.client);
  final SupabaseClient client;

  @override
  Future<InventorySnapshot> load() async {
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
      return InventorySnapshot(status: status as String);
    }
    final ownerId = raw['owner_id'];
    if (status != 'active' || ownerId is! String || ownerId.isEmpty) {
      throw StateError('No se pudo verificar la membresía');
    }
    final config = await client.from('ranch_animal_configs')
        .select('config,revision').eq('owner_id', ownerId).maybeSingle();
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
    while (true) {
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
    final current = await load();
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
    if(existing==null) {
      await client.from('animal_sync_records').insert({'owner_id':current.ownerId,'animal_id':animalId,'payload':payload}).select('animal_id').single();
    } else {
      final result=await client.from('animal_sync_records').update({'payload':payload}).eq('owner_id',current.ownerId).eq('animal_id',animalId).eq('modified_at',existing['modified_at'] as String).isFilter('deleted_at',null).select('animal_id').maybeSingle();
      if(result==null) throw StateError('La ficha cambió durante el guardado. Actualiza e inténtalo otra vez.');
    }
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
  Future<void> addEvent(InventorySnapshot snapshot,String animalId,EventDraft draft) async {
    draft.validate();
    if(snapshot.status!='active'||!['owner','admin','worker'].contains(snapshot.role)||snapshot.userId.isEmpty||client.auth.currentUser?.id!=snapshot.userId)throw StateError('Sesión o permisos inválidos.');
    final fresh=await load();
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
  @override Future<List<Journey>> journeys(InventorySnapshot s)async{
    await _journeyContext(s);
    final result=<Journey>[];
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
    return result;
  }
  @override Future<void> createJourney(InventorySnapshot s,String id,String type,String date,String product,String dose,String notes,Set<String> animalIds)async{
    EventDraft(id:id,type:type,date:date,weight:type=='weight'?0:null).validate();
    await _journeyContext(s);
    final fresh=await load();
    if(fresh.ownerId!=s.ownerId||fresh.userId!=s.userId||fresh.status!='active')throw StateError('La membresía cambió.');
    final roster=fresh.animals.where((a)=>a.active&&animalIds.contains(a.id)).map(Journey.rosterEntry).toList();
    if(roster.isEmpty||roster.length!=animalIds.length)throw StateError('Actualiza la selección de animales.');
    final prior=await client.from('journey_sync_records').select('journey_id').eq('owner_id',s.ownerId).eq('journey_id',id).maybeSingle();
    if(prior!=null)return;
    final now=DateTime.now().toUtc().toIso8601String();
    await _journeyContext(s);
    await client.from('journey_sync_records').insert({'owner_id':s.ownerId,'journey_id':id,'payload':{'id':id,'type':type,'name':'','date':date,'product':product,'dose':dose,'notes':notes,'roster':roster,'status':'in_progress','createdAt':now,'updatedAt':now,'completedAt':null}}).select('journey_id').single();
  }
  @override Future<void> attendJourney(InventorySnapshot s,Journey j,String animalId,double? weight)async{
    final fresh=await load();
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
}
