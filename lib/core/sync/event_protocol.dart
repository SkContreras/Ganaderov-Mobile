import 'event_outbox.dart';

Map<String,dynamic> buildEventOperation(PendingEvent p,{required String operationId,required String deviceId}){
  p.draft.validate();
  final captured=p.draft.capturedAt;
  if(captured==null)throw StateError('La operación requiere fecha de captura.');
  final uuid=RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',caseSensitive:false);
  if(![operationId,deviceId,p.ownerId,p.draft.id].every(uuid.hasMatch))throw StateError('Identificador inválido.');
  if(p.animalId.isEmpty||p.animalId.length>200)throw StateError('Animal inválido.');
  return {'protocolVersion':1,'operationId':operationId,'entityId':p.draft.id,'ownerId':p.ownerId,'deviceId':deviceId,'action':'event.create','baseRevision':null,'capturedAt':captured.toUtc().toIso8601String(),'changes':{
    'animalId':p.animalId,'type':p.draft.type,'date':p.draft.date,
    if(p.draft.type=='weight')'weight':p.draft.weight,
    if(p.draft.product.trim().isNotEmpty)'product':p.draft.product.trim(),
    if(p.draft.notes.trim().isNotEmpty)'notes':p.draft.notes.trim(),
  }};
}

Map<String,dynamic> parseEventReceipt(Object? raw,String operationId){
  if(raw is! Map||raw['protocolVersion']!=1||raw['operationId']!=operationId)throw const FormatException('Recibo inválido.');
  final result=Map<String,dynamic>.from(raw);
  if(!['applied','duplicate','conflict','rejected','retryable'].contains(result['status'])||result['code'] is! String||result['serverReceivedAt'] is! String||DateTime.tryParse(result['serverReceivedAt'] as String)==null)throw const FormatException('Recibo inválido.');
  if(['applied','duplicate'].contains(result['status'])){
    final rev=result['revision'];
    if(rev is! int||rev<1||rev>9007199254740991)throw const FormatException('Revisión inválida.');
  }
  return result;
}
