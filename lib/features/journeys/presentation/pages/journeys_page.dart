import 'package:material_ui/material_ui.dart';
import '../../../../shared/widgets/module_placeholder.dart';

class JourneysPage extends StatelessWidget {
  const JourneysPage({super.key});
  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Jornadas de campo',
    description: 'Organiza las actividades y registros de tu rancho.',
    icon: Icons.calendar_today_outlined,
    planned: ['Crear jornadas', 'Registrar actividades', 'Consultar historial'],
  );
}
