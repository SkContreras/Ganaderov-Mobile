import 'package:supabase_flutter/supabase_flutter.dart';
import '../../livestock/data/supabase_inventory_repository.dart';
import '../domain/dashboard_summary.dart';

class SupabaseDashboardRepository implements DashboardRepository {
  const SupabaseDashboardRepository(this.client);
  final SupabaseClient client;

  @override
  Future<DashboardSummary> load() async {
    final inventory = await SupabaseInventoryRepository(client).load();
    if (inventory.status != 'active') return DashboardSummary(status: inventory.status);
    return DashboardSummary.fromRecords(
      ranchName: inventory.ranchName, role: inventory.role,
      records: inventory.records, statusOptions: inventory.statusOptions,
    );
  }
}
