import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/auth_gateway.dart';
import 'features/dashboard/domain/dashboard_summary.dart';
import 'features/livestock/domain/inventory.dart';
import 'features/settings/domain/ranch.dart';

class GanaderovApp extends StatefulWidget {
  const GanaderovApp({super.key, required this.auth, required this.dashboardRepository, required this.inventoryRepository, required this.ranchRepository});
  final AuthGateway auth;
  final DashboardRepository dashboardRepository;
  final InventoryRepository inventoryRepository;
  final RanchRepository ranchRepository;
  @override
  State<GanaderovApp> createState() => _GanaderovAppState();
}
class _GanaderovAppState extends State<GanaderovApp> {
  late final GoRouter _router = AppRouter.create(widget.auth, widget.dashboardRepository, widget.inventoryRepository, widget.ranchRepository);
  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Ganaderov',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    routerConfig: _router,
  );
}
