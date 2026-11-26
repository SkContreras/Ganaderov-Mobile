import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/database/offline_store.dart';
import 'core/config/supabase_config.dart';
import 'features/auth/data/supabase_auth_gateway.dart';
import 'features/dashboard/data/supabase_dashboard_repository.dart';
import 'features/livestock/data/supabase_inventory_repository.dart';
import 'features/settings/data/supabase_ranch_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  final store=OfflineStore();
  final inventory=SupabaseInventoryRepository(Supabase.instance.client,store:store);
  runApp(ProviderScope(child: GanaderovApp(auth: SupabaseAuthGateway(Supabase.instance.client,clearCache:store.purgeAll), dashboardRepository: SupabaseDashboardRepository(inventory), inventoryRepository: inventory, ranchRepository: SupabaseRanchRepository(Supabase.instance.client))));
}
