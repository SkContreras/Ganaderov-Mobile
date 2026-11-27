import 'dart:convert';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../database/offline_store.dart';
import 'event_protocol.dart';
import 'incremental_v1.dart';

const universalActions={'animal.create','animal.update','animal.archive','animal.restore','event.create','event.update','event.delete','photo.create','photo.delete','journey.create','journey.attend','journey.finish','journey.resume','config.update','forecast.create','forecast.delete','animal.target.update','journey.add_animals','photo.crop','photo.primary'};
class UniversalSync {
  UniversalSync(this.client,this.store,this.project);
  final SupabaseClient client;
  final OfflineStore store;
  final String project;
  void verify(String user){if(client.auth.currentUser?.id!=user||client.auth.currentSession==null)throw StateError('La sesión cambió');}
  Future<Map<String,dynamic>> entity(String user,String owner,String kind,String id)async{
    verify(user);
    final raw=await client.rpc('sync_read_entity',params:{'p_owner':owner,'p_kind':kind,'p_id':id}).timeout(const Duration(seconds:20));
    verify(user);
    if(raw is! Map||raw['revision'] is! int)throw const FormatException('Revisión inválida');
    return Map<String,dynamic>.from(raw);
  }
  Future<String> enqueue(String user,String owner,String action,String id,Map<String,dynamic> changes,{int? revision,String? attachment})async{
    verify(user);
    if(!universalActions.contains(action)||id.isEmpty||action.endsWith('.create')!=(revision==null))throw ArgumentError('Operación inválida');
    final op=const Uuid().v4();
    final operation=<String,dynamic>{'protocolVersion':1,'operationId':op,'action':action,'entityId':id,'ownerId':owner,'deviceId':await store.installationId(),'baseRevision':revision,'capturedAt':DateTime.now().toUtc().toIso8601String(),'changes':changes};
    verify(user);
    await store.enqueueUniversal(user,owner,operation,attachment:attachment);
    return op;
  }
  Future<void> flush(String user,String owner,String holder,{bool manual=false})async{
    for(final row in await store.universalPending(user,owner)){
      verify(user);
      if(!manual&&(row['nextAt'] as int)>DateTime.now().millisecondsSinceEpoch)break;
      if(!await store.acquireDeliveryLease(holder,DateTime.now().millisecondsSinceEpoch))break;
      final op=Map<String,dynamic>.from(row['operation'] as Map),id=row['id'] as String;
      try{
        if(op['operationId']!=id||op['ownerId']!=owner||!universalActions.contains(op['action']))throw const FormatException('Ámbito inválido');
        if(op['action']=='photo.create'){
          final c=op['changes'] as Map,path='$owner/${c['animalId']}/${op['entityId']}';
          final bytes=base64Decode(row['attachment'] as String);
          try{await client.storage.from('animal-photos').uploadBinary(path,bytes,fileOptions:FileOptions(contentType:c['mime'] as String,upsert:false)).timeout(const Duration(seconds:20));}
          catch(_){final old=await client.storage.from('animal-photos').download(path).timeout(const Duration(seconds:20));if(base64Encode(old)!=base64Encode(bytes))rethrow;}
        }
        verify(user);
        final raw=await client.rpc('sync_apply_operation',params:{'p_operation':op}).timeout(const Duration(seconds:20));
        verify(user);
        final receipt=parseEventReceipt(raw,id),status=receipt['status'];
        if(status=='applied'||status=='duplicate'){await store.settleUniversal(user,owner,id,'confirmed',receipt,0);}
        else if(status=='conflict'||status=='rejected'){await store.settleUniversal(user,owner,id,status as String,receipt,0);break;}
        else{throw StateError('Reintentar');}
      }catch(_){
        await store.settleUniversal(user,owner,id,'pending',null,DateTime.now().millisecondsSinceEpoch+1000*math.min(900,30*(1<<math.min(row['attempts'] as int,5))));
        break;
      }
    }
  }
  Future<Map<String,dynamic>> pull(String user,String owner)async{
    var previous=await store.readMirror(user,owner,project),resets=0;
    Map<String,dynamic> empty()=>{'ownerId':owner,'epoch':null,'cursor':0,'records':[]};
    Future<Map<String,dynamic>> page(Map<String,dynamic> base)async{
      verify(user);
      final raw=await client.rpc('sync_pull_changes',params:{'p_owner':owner,'p_after':base['cursor'],'p_epoch':base['epoch'],'p_limit':50}).timeout(const Duration(seconds:20));
      verify(user);
      return Map<String,dynamic>.from(raw as Map);
    }
    for(var count=0;count<2000;count++){
      var base=previous??empty(),data=await page(base);
      if(data['status']=='reset_required'){
        if(previous==null||++resets>2)throw StateError('No se pudo restablecer el cursor');
        base=empty();data=await page(base);
      }
      final next=applyChangePage(base,data,owner);
      verify(user);
      if(await store.commitMirror(user,owner,project,previous,next)){
        previous=next;
        if(data['hasMore']==false)return next;
      }else{previous=await store.readMirror(user,owner,project);}
    }
    throw StateError('Descarga incompleta; cursor conservado');
  }
}
