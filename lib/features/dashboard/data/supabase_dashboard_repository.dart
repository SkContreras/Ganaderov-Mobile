import '../../livestock/domain/inventory.dart';
import '../domain/dashboard_summary.dart';

class SupabaseDashboardRepository implements DashboardRepository {
  const SupabaseDashboardRepository(this.repository);
  final InventoryRepository repository;

  @override
  Future<DashboardSummary> load() async {
    final inventory = await repository.load();
    if (inventory.status != 'active') return DashboardSummary(status: inventory.status);
    return DashboardSummary.fromRecords(
      ranchName: inventory.ranchName, role: inventory.role,
      records: inventory.records, statusOptions: inventory.statusOptions,
      cachedAt: inventory.cachedAt, offline: inventory.offline,
    );
  }
}
