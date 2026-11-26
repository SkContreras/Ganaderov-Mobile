import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';
import '../config/supabase_config.dart';
import '../database/offline_store.dart';
import 'background_session.dart';
import 'event_protocol.dart';

const backgroundTaskName='ganaderov.sync.wake.v1';
const backgroundWorkId='ganaderov-sync-periodic-v1';

// Headless worker sends only durable RPC operations with an unexpired access
// token. It never initializes Supabase Auth or rotates refresh tokens.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher(){
  Workmanager().executeTask((task,inputData)async{
    WidgetsFlutterBinding.ensureInitialized();
    if(task!=backgroundTaskName||!SupabaseConfig.backgroundSyncEnabled||!SupabaseConfig.eventRpcEnabled)return true;
    final db=OfflineStore();
    final holder=const Uuid().v4();
    final httpClient=http.Client();
    try{
      final session=await BackgroundSession.read();
      if(session==null)return true;
      final userId=session['userId'] as String;
      if(!await db.acquireDeliveryLease(holder,DateTime.now().millisecondsSinceEpoch))return true;
      // Bound each invocation; subsequent WorkManager runs drain the rest.
      final pending=(await db.pending(userId)).where((p)=>p.state=='pending'&&p.operation!=null&&p.nextAt<=DateTime.now().millisecondsSinceEpoch).take(8);
      for(final p in pending){
        final current=await BackgroundSession.read();
        if(current==null||current['userId']!=userId||current['accessToken']!=session['accessToken'])break;
        if(!await db.acquireDeliveryLease(holder,DateTime.now().millisecondsSinceEpoch))break;
        final operation=p.operation!,id=operation['operationId'];
        if(id is! String||operation['action']!='event.create'||operation['ownerId']!=p.ownerId||operation['entityId']!=p.draft.id)continue;
        try{
          final response=await httpClient.post(Uri.parse('${SupabaseConfig.url}/rest/v1/rpc/sync_apply_operation'),headers:{
            'apikey':SupabaseConfig.publishableKey,'Authorization':'Bearer ${current['accessToken']}','Content-Type':'application/json',
          },body:jsonEncode({'p_operation':operation})).timeout(const Duration(seconds:20));
          final after=await BackgroundSession.read();
          if(after==null||after['userId']!=userId||after['accessToken']!=session['accessToken'])break;
          if(response.statusCode==401||response.statusCode==403)break;
          if(response.statusCode!=200)throw StateError('RPC unavailable');
          final receipt=parseEventReceipt(jsonDecode(response.body),id);
          final status=receipt['status'] as String;
          if(status=='applied'||status=='duplicate'){await db.confirmRpc(p,receipt);}
          else if(status=='conflict'||status=='rejected'){await db.stopRpc(p,status,receipt['code'] as String);}
          else{throw StateError('Retry requested');}
        }catch(_){
          await db.retry(p,'Envío en segundo plano sin confirmar.',DateTime.now().add(Duration(seconds:math.min(900,30*(1<<math.min(p.attempts,5))))).millisecondsSinceEpoch);
        }
      }
      return true;
    }catch(_){return false;}
    finally{
      httpClient.close();
      try{await db.releaseDeliveryLease(holder);}finally{await db.close();}
    }
  });
}

Future<void> configureBackgroundSync()async{
  if(!Platform.isAndroid)return;
  await Workmanager().initialize(backgroundCallbackDispatcher);
  if(!SupabaseConfig.backgroundSyncEnabled||!SupabaseConfig.eventRpcEnabled){
    await Workmanager().cancelByUniqueName(backgroundWorkId);
    return;
  }
  await Workmanager().registerPeriodicTask(
    backgroundWorkId,backgroundTaskName,
    frequency:const Duration(minutes:15),
    constraints:Constraints(networkType:NetworkType.connected),
    existingWorkPolicy:ExistingPeriodicWorkPolicy.keep,
  );
}
