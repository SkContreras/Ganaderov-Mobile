import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/auth_gateway.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell, required this.auth});
  final StatefulNavigationShell navigationShell;
  final AuthGateway auth;

  static const labels = ['Inicio', 'Ganado', 'Jornadas', 'Análisis', 'Ajustes'];
  static const icons = [Icons.home_outlined, Icons.pets_outlined, Icons.calendar_today_outlined, Icons.bar_chart_outlined, Icons.settings_outlined];
  static const selectedIcons = [Icons.home, Icons.pets, Icons.calendar_month, Icons.bar_chart, Icons.settings];

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    void select(int i) => navigationShell.goBranch(i, initialLocation: i == index);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.agriculture, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          const Text('Ganaderov', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Mi cuenta',
            onPressed: () => select(4),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: Row(children: [
        if (wide) NavigationRail(
          selectedIndex: index,
          onDestinationSelected: select,
          labelType: NavigationRailLabelType.all,
          destinations: [
            for (var i = 0; i < labels.length; i++)
              NavigationRailDestination(icon: Icon(icons[i]), selectedIcon: Icon(selectedIcons[i]), label: Text(labels[i])),
          ],
        ),
        Expanded(child: navigationShell),
      ]),
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: index,
        onDestinationSelected: select,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(icon: Icon(icons[i]), selectedIcon: Icon(selectedIcons[i]), label: labels[i]),
        ],
      ),
    );
  }
}
