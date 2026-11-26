import 'package:material_ui/material_ui.dart';
import '../../../../shared/widgets/module_placeholder.dart';

class LivestockPage extends StatelessWidget {
  const LivestockPage({super.key});
  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Inventario de ganado',
    description: 'Consulta y organiza los animales de tu rancho.',
    icon: Icons.pets_outlined,
    planned: ['Buscar por arete o nombre', 'Registrar animales', 'Consultar historial de pesos', 'Consultar archivo'],
  );
}
