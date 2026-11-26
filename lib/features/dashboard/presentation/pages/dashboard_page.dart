import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/presentation/widgets/ranch_scene.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      top: false,
      child: ListView(
        key: const PageStorageKey('dashboard-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text('GESTIÓN GANADERA', style: theme.textTheme.labelMedium?.copyWith(color: colors.primary, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Mi rancho', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Resumen de tu operación ganadera.'),
          const SizedBox(height: 18),
          const RanchScene(hideEyes: false),
          const SizedBox(height: 20),
          Text('Resumen', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Los indicadores estarán disponibles al conectar el inventario.'),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 640 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final item in const [
                ('Animales', Icons.pets_outlined),
                ('Hembras', Icons.female),
                ('Machos', Icons.male),
                ('Con pesaje', Icons.monitor_weight_outlined),
              ]) SizedBox(width: width, child: _SummaryCard(label: item.$1, icon: item.$2)),
            ]);
          }),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () => context.go('/ganado'), icon: const Icon(Icons.pets_outlined), label: const Text('Consultar inventario')),
          const SizedBox(height: 24),
          Text('Actividad reciente', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Row(children: [
            Icon(Icons.event_note_outlined),
            SizedBox(width: 12),
            Expanded(child: Text('La actividad del rancho se mostrará cuando habilitemos los registros de campo.')),
          ]))),
        ],
      ),
    );
  }
}
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text('—', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(label),
      ]),
    ),
  );
}
