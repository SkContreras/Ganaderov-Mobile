import 'package:material_ui/material_ui.dart';
import '../../../../shared/widgets/module_placeholder.dart';

class AnalysisPage extends StatelessWidget {
  const AnalysisPage({super.key});
  @override
  Widget build(BuildContext context) => const ModulePlaceholder(
    title: 'Análisis ganadero',
    description: 'Consulta los indicadores productivos de tu rancho.',
    icon: Icons.bar_chart_outlined,
    planned: ['Indicadores de inventario', 'Historial y evolución de pesos', 'Análisis productivo'],
  );
}
