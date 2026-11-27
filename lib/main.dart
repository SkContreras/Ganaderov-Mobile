import 'dart:async';
import 'package:flutter/widgets.dart';
import 'core/sync/background_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/sync/event_outbox.dart';
import 'core/database/offline_store.dart';
import 'core/config/supabase_config.dart';
import 'features/auth/data/supabase_auth_gateway.dart';
import 'features/dashboard/data/supabase_dashboard_repository.dart';
import 'features/livestock/data/supabase_inventory_repository.dart';
import 'features/settings/data/supabase_ranch_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  final store=await OfflineStore.protected(provision:true);
  final currentUser=Supabase.instance.client.auth.currentUser;
  try{if(currentUser==null){await store.purgeAll();}else{await store.retainOnly(currentUser.id);}}catch(_){}
  final ranch=SupabaseRanchRepository(Supabase.instance.client);
  final inventory=SupabaseInventoryRepository(Supabase.instance.client,store:store,onSynced:ranch.invalidate,eventRpcEnabled:SupabaseConfig.eventRpcEnabled,journeyRpcEnabled:SupabaseConfig.journeyRpcEnabled);
  final sync=ForegroundSync(inventory.syncEvents);
  sync.start();
  // Scheduling failures must not prevent login or local data access.
  unawaited(configureBackgroundSync().catchError((Object _){}));
  runApp(ProviderScope(child: GanaderovApp(auth: SupabaseAuthGateway(Supabase.instance.client,clearCache:store.purgeAll,retainCacheFor:store.retainOnly), dashboardRepository: SupabaseDashboardRepository(inventory), inventoryRepository: inventory, ranchRepository: ranch)));
}
