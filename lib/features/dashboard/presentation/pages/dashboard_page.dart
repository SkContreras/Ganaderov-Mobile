import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../auth/domain/auth_gateway.dart';
import '../../../auth/presentation/widgets/ranch_scene.dart';
import '../../domain/dashboard_summary.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.repository, required this.auth, required this.ranchChanges});
  final DashboardRepository repository;
  final AuthGateway auth;
  final Listenable ranchChanges;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage> {
  DashboardSummary? _summary;
  DateTime? _loadedAt;
  bool _loading = true, _failed = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_authChanged);
    widget.ranchChanges.addListener(_authChanged);
    _load();
  }
  void _authChanged() {
    if (!mounted) return;
    if (!widget.auth.signedIn || widget.auth.recovering) {
      _request++;
      setState(() { _summary = null; _loadedAt = null; _loading = false; _failed = false; });
    } else {
      _load();
    }
  }
  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    widget.ranchChanges.removeListener(_authChanged);
    super.dispose();
  }
  Future<void> _load() async {
    final request = ++_request;
    if (!widget.auth.signedIn || widget.auth.recovering) return;
    setState(() { _loading = true; _failed = false; _summary = null; _loadedAt = null; });
    try {
      final summary = await widget.repository.load().timeout(const Duration(seconds: 45));
      if (!mounted || request != _request || !widget.auth.signedIn) return;
      setState(() { _summary = summary; _loadedAt = DateTime.now(); _loading = false; });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() { _loading = false; _failed = true; });
    }
  }
  String _eventLabel(String type) => switch (type) {
    'weight' => 'Pesaje', 'bath' => 'Baño', 'vaccine' => 'Vacunación',
    'deworm' => 'Desparasitación', 'injection' => 'Inyección',
    'medication' => 'Medicamento', 'review' => 'Revisión',
    _ => 'Registro de campo',
  };
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summary = _summary;
    final active = summary?.status == 'active';
    return SafeArea(top: false, child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey('dashboard-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text('GESTIÓN GANADERA', style: theme.textTheme.labelMedium?.copyWith(color: colors.primary, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(active ? summary!.ranchName : 'Mi rancho', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (active) Text(switch (summary!.role) {'owner' => 'Propietario', 'admin' => 'Administrador', 'worker' => 'Trabajador', _ => 'Miembro'}),
          const SizedBox(height: 16),
          const RanchScene(hideEyes: false),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Text('Resumen', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            IconButton(tooltip: 'Actualizar dashboard', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ]),
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Consultando tu rancho…'),
          ] else if (_failed) ...[
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('No se pudieron consultar los datos.', style: theme.textTheme.titleMedium),
              const Text('Comprueba tu conexión y vuelve a intentar. No se mostrarán cifras sin verificar.'),
              TextButton(onPressed: _load, child: const Text('Reintentar')),
            ]))),
          ] else if (!active) ...[
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(summary?.status == 'pending' ? 'Solicitud pendiente' : 'Aún no perteneces a un rancho', style: theme.textTheme.titleMedium),
              Text(summary?.status == 'pending' ? 'Espera la aprobación de un administrador y actualiza esta pantalla.' : 'Crea un rancho o solicita acceso desde Ajustes.'),
              TextButton(onPressed:()=>context.go('/ajustes'),child:const Text('Rancho y usuarios')),
            ]))),
          ] else ...[
            Text('Actualizado a las ${DateFormat('HH:mm').format(_loadedAt!)}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 640 ? 4 : 2;
              final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final item in [
                  ('Animales', Icons.pets_outlined, summary!.total),
                  ('Hembras', Icons.female, summary.females),
                  ('Machos', Icons.male, summary.males),
                  ('Con pesaje', Icons.monitor_weight_outlined, summary.weighed),
                ]) SizedBox(width: width, child: _SummaryCard(label: item.$1, icon: item.$2, value: item.$3)),
              ]);
            }),
            const SizedBox(height: 16),
            if (summary!.total == 0) const Text('No hay animales activos sincronizados en este rancho.'),
            FilledButton.icon(onPressed: () => context.go('/ganado'), icon: const Icon(Icons.pets_outlined), label: const Text('Consultar inventario')),
            const SizedBox(height: 24),
            Text('Actividad reciente', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (summary.activity.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Sin registros recientes de animales activos.')))
            else
              Card(child: Column(children: [
                for (final event in summary.activity)
                  ListTile(
                    leading: Icon(event.type == 'weight' ? Icons.monitor_weight_outlined : Icons.event_note_outlined, color: colors.primary),
                    title: Text(_eventLabel(event.type)),
                    subtitle: Text(event.animal),
                    trailing: Text(DateFormat('dd/MM/yy').format(event.date.toLocal())),
                  ),
              ])),
          ],
        ],
      ),
    ));
  }
}
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.icon, required this.value});
  final String label;
  final IconData icon;
  final int value;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 12),
      Text('$value', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(label),
    ])),
  );
}
