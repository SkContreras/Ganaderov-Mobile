import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/inventory.dart';
import '../domain/animal_form_config.dart';
import 'package:uuid/uuid.dart';

class SupabaseInventoryRepository implements InventoryRepository, AnimalWriter {
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
}
