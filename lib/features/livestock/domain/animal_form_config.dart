class AnimalField {
  const AnimalField(this.id, this.label, this.module, {this.kind = 'text', this.introduced = 1});
  final String id, label, module, kind;
  final int introduced;
}
const animalFields = [
  AnimalField('tag','Número de arete','identification'),
  AnimalField('name','Nombre','identification'),
  AnimalField('sex','Sexo','identification',kind:'select'),
  AnimalField('breed','Raza','identification',kind:'list',introduced:3),
  AnimalField('color','Color','identification'),
  AnimalField('cross','Cruza','identification',introduced:4),
  AnimalField('markings','Señas particulares','identification',introduced:4),
  AnimalField('officialId','Identificador oficial','identification',introduced:4),
  AnimalField('birthDate','Fecha de nacimiento','dates',kind:'date'),
  AnimalField('birthEstimated','Nacimiento estimado','dates',kind:'boolean',introduced:4),
  AnimalField('estimatedAge','Edad aproximada (meses)','dates',kind:'age'),
  AnimalField('entryDate','Fecha de ingreso','dates',kind:'date',introduced:4),
  AnimalField('originType','Procedencia','dates',kind:'select',introduced:4),
  AnimalField('originName','Rancho o vendedor de origen','dates',introduced:4),
  AnimalField('motherId','Madre','dates',kind:'parent',introduced:4),
  AnimalField('fatherId','Padre o semental','dates',kind:'parent',introduced:4),
  AnimalField('weaningDate','Fecha de destete','dates',kind:'date',introduced:4),
  AnimalField('status','Estado','location',kind:'list'),
  AnimalField('lot','Lote','location',kind:'list',introduced:4),
  AnimalField('paddock','Potrero','location',kind:'list',introduced:4),
  AnimalField('pen','Corral','location',kind:'list',introduced:4),
  AnimalField('locationSince','Fecha de entrada a ubicación','location',kind:'date',introduced:4),
  AnimalField('responsible','Responsable','location',introduced:4),
  AnimalField('exitReason','Motivo de baja','location',kind:'select',introduced:4),
  AnimalField('exitNotes','Observaciones de baja','location',introduced:4),
  AnimalField('generalNotes','Observaciones generales','tracking',introduced:4),
];
class AnimalFormConfig {
  const AnimalFormConfig(this.raw);
  final Map<String,dynamic> raw;
  static const inactive = {'Vendido','Fallecido','Baja','Otro','Otros','Desaparecido'};
  Map get _fields => raw['fields'] is Map ? raw['fields'] as Map : {};
  Map get _modules => raw['modules'] is Map ? raw['modules'] as Map : {};
  int get version => raw['configVersion'] is int ? raw['configVersion'] as int : raw['schemaVersion'] is int ? raw['schemaVersion'] as int : 4;
  Map _setting(String id) => _fields[id] is Map ? _fields[id] as Map : {};
  bool requiredField(AnimalField f) => _fields[f.id] is Map ? _setting(f.id)['required'] == true : ['tag','sex'].contains(f.id);
  bool visible(AnimalField f) {
    if (f.module != 'identification' && (_modules[f.module] == false || (version < 4 && !_modules.containsKey(f.module)))) return false;
    final s = _setting(f.id);
    if (!_fields.containsKey(f.id) && f.introduced > version) return false;
    return (f.id == 'status' || s['enabled'] != false) && (s['form'] != false || requiredField(f));
  }
  String label(AnimalField f) => _setting(f.id)['label'] is String && (_setting(f.id)['label'] as String).trim().isNotEmpty ? _setting(f.id)['label'] as String : f.label;
  Map<String,String> choices(String id) {
    if (id == 'sex') return {'Hembra':'Hembra','Macho':'Macho'};
    if (id == 'birthEstimated') return {'true':'Sí','false':'No'};
    if (id == 'originType') return {for(final s in ['Nacimiento propio','Compra','Donación','Otro']) s:s};
    if (id == 'exitReason') return {for(final s in ['Venta','Muerte','Extravío','Otro']) s:s};
    final lists = raw['lists'];
    final entries = lists is Map ? lists[id] : null;
    if (entries is List && entries.isNotEmpty) return {for(final e in entries.whereType<Map>()) if(e['enabled'] == true && e['value'] is String && e['label'] is String) e['value'] as String:e['label'] as String};
    if (id == 'status') return {'Activo':'Activo','Vendido':'Vendido','Fallecido':'Muerto','Desaparecido':'Extraviado','Otro':'Otro','Baja':'Baja (legado)','Otros':'Otro (legado)'};
    return {};
  }
  bool active(String status) {
    final lists = raw['lists'];
    final entries = lists is Map ? lists['status'] : null;
    if (entries is List) {
      for(final e in entries.whereType<Map>()) {
        if(e['value']==status && e['active'] is bool) return e['active'] as bool;
      }
    }
    return !inactive.contains(status);
  }
  bool applies(AnimalField f, String status, String origin) {
    if (['exitReason','exitNotes'].contains(f.id)) return !active(status);
    if (['lot','paddock','pen','locationSince','responsible'].contains(f.id)) return active(status);
    if (['originName','entryDate'].contains(f.id)) return origin.isEmpty || origin=='Compra';
    if (['motherId','fatherId'].contains(f.id)) return origin.isEmpty || origin=='Nacimiento propio';
    return true;
  }
}
