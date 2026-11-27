class AnimalEvent {
  const AnimalEvent({required this.type, required this.date, this.id='',this.raw=const {},this.syncState,this.weight, this.notes = '', this.product = '', this.actor = '', this.createdAt});
  final String id;
  final Map<String,dynamic> raw;
  final String? syncState;
  bool get fromJourney=>raw['journeyId']!=null;
  final String type, notes, product, actor;
  final DateTime? createdAt;
  final DateTime? date;
  final double? weight;
  String get label => switch (type) {
    'weight' => 'Pesaje', 'bath' => 'Baño', 'vaccine' => 'Vacuna',
    'deworm' => 'Desparasitación', 'note' => 'Observación',
    'injection' => 'Inyección', 'medication' => 'Medicamento',
    'review' => 'Revisión veterinaria', _ => 'Otra actividad',
  };
}

class InventoryAnimal {
  const InventoryAnimal({required this.id, required this.fields, required this.active, required this.statusLabel, required this.events,this.syncState,this.historyState});
  final String? syncState,historyState;
  final String id, statusLabel;
  final Map<String, dynamic> fields;
  final bool active;
  final List<AnimalEvent> events;
  String value(String key) {
    final v = fields[key];
    return v is String || v is num ? v.toString().trim() : '';
  }
  String get title => value('name').isNotEmpty ? value('name') : value('tag').isNotEmpty ? 'Arete ${value('tag')}' : 'Animal sin nombre';
  AnimalEvent? get latestWeight {
    for (final event in events) {
      if (event.type == 'weight' && event.weight != null) return event;
    }
    return null;
  }
  bool matches(String query) {
    String fold(String text) {
      var result = text.toLowerCase();
      for (final pair in const [('á','a'),('é','e'),('í','i'),('ó','o'),('ú','u'),('ü','u')]) {
        result = result.replaceAll(pair.$1, pair.$2);
      }
      return result;
    }
    final text = fold([for (final key in ['tag','name','sex','breed','color','lot','paddock','pen','officialId']) value(key), statusLabel].join(' '));
    return fold(query.trim()).split(RegExp(r'\s+')).every(text.contains);
  }
}

class InventorySnapshot {
  const InventorySnapshot({required this.status, this.ranchName = '', this.role = '', this.records = const [], this.statusOptions = const {}, this.statusLabels = const {}, this.config = const {}, this.ownerId = '', this.userId = '', this.configRevision = 0, this.offline = false, this.cachedAt, this.photoSyncStates = const {},this.operationStates=const {},this.offlineWritesEnabled=false});
  final String status, ranchName, role, ownerId, userId;
  final Map<String, dynamic> config;
  final int configRevision;
  final bool offline;
  final DateTime? cachedAt;
  // Presentation only. Pending operations never become the authoritative cache.
  final Map<String, String> photoSyncStates;
  final Map<String,String> operationStates;
  final bool offlineWritesEnabled;
  bool get canManage => !offline && status == 'active' && (role == 'owner' || role == 'admin');
  bool get canCaptureAnimals {
    if(status!='active'||!['owner','admin'].contains(role))return false;
    if(!offline)return true;
    final age=cachedAt==null?null:DateTime.now().difference(cachedAt!);
    return offlineWritesEnabled&&age!=null&&!age.isNegative&&age<=const Duration(hours:24);
  }
  final List<Map<String, dynamic>> records;
  final Map<String, bool> statusOptions;
  final Map<String, String> statusLabels;

  List<InventoryAnimal> get animals {
    const inactive = {'Vendido','Fallecido','Baja','Otro','Otros','Desaparecido'};
    const labels = {'Fallecido':'Muerto','Desaparecido':'Extraviado','Baja':'Baja (legado)','Otros':'Otro (legado)'};
    final result = <InventoryAnimal>[];
    for (final row in records) {
      if (row['deleted_at'] != null) continue;
      final payload = row['payload'];
      if (payload is! Map || payload['animal'] is! Map) throw const FormatException('Ficha inválida');
      final fields = Map<String, dynamic>.from(payload['animal'] as Map);
      final id = row['animal_id'];
      if (id is! String || id.isEmpty || fields['id'] != id) throw const FormatException('Identificador inválido');
      final status = fields['status']?.toString() ?? '';
      final history = <AnimalEvent>[];
      final rawEvents = payload['events'];
      if (rawEvents is List) {
        for (final event in rawEvents.whereType<Map>()) {
          if (event['animalId'] != id || event['type'] is! String) continue;
          final weight = double.tryParse(event['weight']?.toString() ?? '');
          history.add(AnimalEvent(
            id:event['id']?.toString()??'',raw:Map<String,dynamic>.unmodifiable(event),syncState:operationStates['event:${event['id']}'],
            type: event['type'] as String,
            date: DateTime.tryParse(event['date']?.toString() ?? '') ?? DateTime.tryParse(event['performedAt']?.toString() ?? ''),
            weight: weight != null && weight.isFinite && weight >= 0 ? weight : null,
            notes: event['notes']?.toString() ?? '',
            product: event['label']?.toString() ?? '',
            actor: event['performedBy'] is Map ? (event['performedBy'] as Map)['label']?.toString() ?? '' : '',
            createdAt: DateTime.tryParse(event['createdAt']?.toString() ?? ''),
          ));
        }
      }
      history.sort((a,b) {
        final day=(b.date??DateTime(1900)).compareTo(a.date??DateTime(1900));
        return day!=0?day:(b.createdAt??DateTime(1900)).compareTo(a.createdAt??DateTime(1900));
      });
      result.add(InventoryAnimal(id: id, fields: Map.unmodifiable(fields), active: statusOptions[status] ?? !inactive.contains(status), statusLabel: statusLabels[status] ?? labels[status] ?? (status.isEmpty ? 'Sin estado' : status), events: List.unmodifiable(history),syncState:operationStates['animal:$id'],historyState:operationStates['history:$id']));
    }
    result.sort((a,b) {
      final aTag = a.value('tag'), bTag = b.value('tag');
      final an = int.tryParse(aTag), bn = int.tryParse(bTag);
      final comparison = an != null && bn != null ? an.compareTo(bn) : aTag.toLowerCase().compareTo(bTag.toLowerCase());
      return comparison != 0 ? comparison : a.id.compareTo(b.id);
    });
    return result;
  }
}

abstract interface class AnimalLifecycleWriter {
  Future<void> setAnimalStatus(InventorySnapshot snapshot,String animalId,String status);
}

abstract interface class AnimalWriter {
  Future<void> saveAnimal(InventorySnapshot original, String? id, Map<String, dynamic> changes,{String? operationId,String? createId});
}

abstract interface class OfflineInventory {
  bool get supportsOfflineInventory;
  Future<InventorySnapshot> refreshLocalInventory(InventorySnapshot snapshot);
  Future<void> prepareOfflineInventory(InventorySnapshot snapshot);
}

abstract interface class InventoryRepository {
  Future<InventorySnapshot> load();
}
