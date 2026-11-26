// Pure reducer. The caller must persist records and cursor atomically.
// Not connected to the legacy inventory repository.
Map<String,dynamic> applyChangePage(Map<String,dynamic> snapshot,Map<String,dynamic> page,String ownerId){
  const maxSafe=9007199254740991;
  Never invalid()=>throw const FormatException('Página incremental inválida o requiere reinicio.');
  bool validInt(Object? v)=>v is int&&v>=0&&v<=maxSafe;
  if(snapshot['ownerId']!=ownerId||page['protocolVersion']!=1||page['status']!='ok')invalid();
  final epoch=page['epoch'];
  if(epoch is! String||epoch.isEmpty||(snapshot['epoch']!=null&&snapshot['epoch']!=epoch))invalid();
  final cursor=snapshot['cursor'],head=page['head'],changes=page['changes'];
  if(!validInt(cursor)||!validInt(head)||changes is! List||changes.length>100)invalid();
  var next=cursor as int;
  final upper=head as int;
  if(upper<next)invalid();
  final records=<(String,String),Map<String,dynamic>>{};
  for(final raw in snapshot['records'] as List){
    final row=Map<String,dynamic>.from(raw as Map);
    records[(row['kind'] as String,row['entity_id'] as String)]=row;
  }
  const keys={'animal':'animal_id','journey':'journey_id','config':'owner_id'};
  for(final raw in changes){
    if(raw is! Map)invalid();
    final kind=raw['kind'],id=raw['entity_id'],deleted=raw['deleted'];
    if(raw['revision']!=next+1||kind is! String||!keys.containsKey(kind)||id is! String||id.isEmpty||deleted is! bool)invalid();
    final key=(kind,id);
    if(deleted){
      if(raw['record']!=null)invalid();
      records.remove(key);
    }else{
      final record=raw['record'];
      if(record is! Map||record['owner_id']!=ownerId||record[keys[kind]]!=id)invalid();
      records[key]={'kind':kind,'entity_id':id,'record':Map<String,dynamic>.from(record)};
    }
    next++;
  }
  if(next!=page['nextCursor']||next>upper||page['hasMore']!=(next<upper)||(next<upper&&next==cursor))invalid();
  return {'ownerId':ownerId,'epoch':epoch,'cursor':next,'records':records.values.toList()};
}
