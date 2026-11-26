import 'package:material_ui/material_ui.dart';

class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({super.key, required this.title, required this.description, required this.icon, required this.planned});
  final String title, description;
  final IconData icon;
  final List<String> planned;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(top: false, child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(description),
        const SizedBox(height: 24),
        Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
          Icon(icon, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Módulo en preparación', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Todavía no se consultan ni se modifican datos.', textAlign: TextAlign.center),
        ]))),
        const SizedBox(height: 20),
        Text('Funciones previstas', style: theme.textTheme.titleMedium),
        for (final label in planned) ListTile(leading: const Icon(Icons.circle_outlined), title: Text(label)),
      ],
    ));
  }
}
