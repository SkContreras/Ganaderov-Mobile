bool sameConflictValue(Object? a,Object? b){
 if(a is Map&&b is Map)return a.length==b.length&&a.keys.every((k)=>b.containsKey(k)&&sameConflictValue(a[k],b[k]));
 if(a is List&&b is List)return a.length==b.length&&List.generate(a.length,(i)=>sameConflictValue(a[i],b[i])).every((x)=>x);
 return a==b;
}
List<Map<String,dynamic>> resolutionFields(Map<String,dynamic> op,Map<String,dynamic> remote){
 final revision=remote['revision'],data=remote['data'],c=op['changes'] as Map;
 if(revision is! int||revision<1||data is! Map)throw StateError('Entidad no disponible');
 switch(op['action']){
 case 'animal.update':
   return (c['fields'] as Map).entries.map((e)=><String,dynamic>{'key':e.key,'local':e.value,'remote':data[e.key]}).toList();
 case 'event.update':
   if(remote['parentId']!=c['animalId']||data['type']!='weight'||data.containsKey('journeyId'))throw StateError('Evento incompatible');
   return [{'key':'weight','local':c['weight'],'remote':data['weight']}];
 case 'config.update':return [{'key':'config','local':c['config'],'remote':data}];
 default:throw StateError('Revisa esta acción desde su formulario original');
 }
}
Map<String,dynamic> replacementOperation(Map<String,dynamic> op,Map<String,dynamic> reviewed,Map<String,dynamic> current,List<String> selected,String id,String stamp){
 if(!sameConflictValue(reviewed,current))throw StateError('La entidad volvió a cambiar');
 final fields=resolutionFields(op,current);
 if(selected.isEmpty||selected.toSet().length!=selected.length||selected.any((k)=>!fields.any((f)=>f['key']==k)))throw StateError('Selección inválida');
 return {...op,'operationId':id,'capturedAt':stamp,'baseRevision':current['revision'],'changes':op['action']=='animal.update'?{'fields':{for(final f in fields)if(selected.contains(f['key']))f['key']:f['local']}}:op['changes']};
}
