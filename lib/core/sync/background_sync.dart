import 'dart:io';
import 'package:workmanager/workmanager.dart';
import '../config/supabase_config.dart';

const backgroundTaskName='ganaderov.sync.wake.v1';
const backgroundWorkId='ganaderov-sync-periodic-v1';

// No database, authentication or network mutation in the headless isolate.
// Until a safe cross-isolate session and lease protocol exists, this is a
// scheduling probe only. Foreground recovery remains the actual sender.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher(){
  Workmanager().executeTask((task,inputData)async{
    if(task!=backgroundTaskName)return true;
    return true;
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
