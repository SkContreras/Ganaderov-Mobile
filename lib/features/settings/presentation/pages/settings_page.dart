import 'package:material_ui/material_ui.dart';

import '../../../../core/widgets/ranch_illustration.dart';
import '../../../../core/sync/event_outbox.dart';
import '../widgets/sync_panel.dart';
import '../../../auth/domain/auth_gateway.dart';
import '../../domain/ranch.dart';
import '../widgets/ranch_panel.dart';
import '../../domain/animal_configuration.dart';
import '../../../livestock/domain/inventory.dart';
import 'animal_configuration_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.auth, required this.ranchRepository,this.outbox});
  final AuthGateway auth;
  final RanchRepository ranchRepository;
  final OutboxAccess? outbox;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta? Los registros pendientes permanecen guardados para esta cuenta y se enviarán al volver a iniciar sesión.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.auth.logout();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo cerrar sesión. Inténtalo de nuevo.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Configuración', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const RanchIllustration('ranch-settings'),
      const SizedBox(height: 20),
      ListenableBuilder(listenable: widget.auth, builder: (context, _) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: const Text('Mi cuenta'),
        subtitle: Text(widget.auth.email ?? 'Sesión activa'),
      ))),
      const SizedBox(height: 12),
      RanchPanel(repository: widget.ranchRepository, auth: widget.auth),
      if(widget.outbox is RanchConfigurationWriter&&widget.outbox is InventoryRepository&&(widget.outbox as RanchConfigurationWriter).supportsConfiguration)Card(child:ListTile(leading:const Icon(Icons.tune),title:const Text('Campos y listas del rancho'),subtitle:const Text('Módulos, campos, etiquetas y opciones compartidas'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>AnimalConfigurationPage(inventory:widget.outbox as InventoryRepository,writer:widget.outbox as RanchConfigurationWriter))))),
      const SizedBox(height: 12),
      const Card(child: Column(children: [
        ListTile(leading: Icon(Icons.tune), title: Text('Preferencias productivas'), subtitle: Text('Próximamente')),

      ])),
      if(widget.outbox!=null)SyncPanel(access:widget.outbox!),
      const SizedBox(height: 24),
      OutlinedButton.icon(onPressed: _busy ? null : _logout, icon: const Icon(Icons.logout), label: const Text('Cerrar sesión')),
    ],
  ));
}
