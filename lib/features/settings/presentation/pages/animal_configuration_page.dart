import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../livestock/domain/inventory.dart';
import '../../../livestock/domain/animal_form_config.dart';
import '../../../livestock/domain/local_changes.dart';
import '../../domain/animal_configuration.dart';

class AnimalConfigurationPage extends StatefulWidget {
  const AnimalConfigurationPage({
    super.key,
    required this.inventory,
    required this.writer,
  });
  final InventoryRepository inventory;
  final RanchConfigurationWriter writer;
  @override
  State<AnimalConfigurationPage> createState() =>
      _AnimalConfigurationPageState();
}

class _AnimalConfigurationPageState extends State<AnimalConfigurationPage> {
  final _form = GlobalKey<FormState>();
  InventorySnapshot? _snapshot;
  Map<String, dynamic>? _config;
  String _operationId = const Uuid().v4();
  String? _error;
  bool _busy = true, _uncertain = false;
  bool get _editable =>
      !_busy &&
      !_uncertain &&
      widget.writer.supportsConfiguration &&
      _snapshot?.canCaptureAnimals == true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await widget.inventory.load();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _config = editableAnimalConfiguration(snapshot.config);
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo consultar la configuración del rancho';
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy ||
        _snapshot == null ||
        _config == null ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fields = _config!['fields'] as Map;
      for (final field in fields.values.whereType<Map>()) {
        field['detail'] = field['detailVisibility'] != 'hidden';
      }
      validateAnimalConfiguration(_config!, _snapshot!);
      await widget.writer.saveConfiguration(
        _snapshot!,
        _config!,
        operationId: _operationId,
      );
      final inventory = widget.inventory;
      if (inventory is OfflineInventory) {
        final updated = await (inventory as OfflineInventory)
            .refreshLocalInventory(_snapshot!);
        if (mounted) setState(() => _snapshot = updated);
      }
      if (mounted) {
        _operationId = const Uuid().v4();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Configuración guardada en el dispositivo; pendiente de confirmación.',
            ),
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error = 'No se confirmó el guardado local. Reintenta con los mismos datos.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleField(Map setting, String key, bool value) {
    setState(() {
      setting[key] = value;
      if (key == 'required' && value) {
        setting['enabled'] = true;
        setting['form'] = true;
      }
      if ((key == 'enabled' || key == 'form') && !value) {
        setting['required'] = false;
      }
    });
  }

  Widget _fieldSettings(AnimalField field) {
    final setting = (_config!['fields'] as Map)[field.id] as Map;
    final automatic = field.kind == 'automatic',
        locked = automatic || field.id == 'status';
    Widget toggle(String key, String label, {bool disabled = false}) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: setting[key] == true,
          onChanged: _editable && !disabled
              ? (value) => _toggleField(setting, key, value)
              : null,
        );
    return ExpansionTile(
      key: ValueKey('config-field-${field.id}'),
      title: Text(setting['label'] as String),
      subtitle: Text(
        '${configurationModules[field.module]}${locked ? ' · Campo operativo' : ''}',
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        TextFormField(
          initialValue: setting['label'] as String,
          enabled: _editable,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Nombre visible'),
          onChanged: (value) => setting['label'] = value.trim(),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Escribe una etiqueta' : null,
        ),
        toggle('enabled', 'Campo activo', disabled: locked),
        if (!automatic) ...[
          toggle(
            'form',
            'Mostrar en formulario',
            disabled: field.id == 'status',
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('${field.id}:${setting['formLevel']}'),
            initialValue: setting['formLevel'] as String,
            decoration: const InputDecoration(
              labelText: 'Nivel del formulario',
            ),
            items: const [
              DropdownMenuItem(value: 'basic', child: Text('Básico')),
              DropdownMenuItem(
                value: 'advanced',
                child: Text('Datos adicionales'),
              ),
            ],
            onChanged: _editable
                ? (value) => setState(() => setting['formLevel'] = value)
                : null,
          ),
          toggle('required', 'Obligatorio'),
          toggle('table', 'Mostrar en tabla'),
        ],
        DropdownButtonFormField<String>(
          key: ValueKey('${field.id}:${setting['detailVisibility']}'),
          initialValue: setting['detailVisibility'] as String,
          decoration: const InputDecoration(labelText: 'Visibilidad en ficha'),
          items: const [
            DropdownMenuItem(value: 'hidden', child: Text('Oculto')),
            DropdownMenuItem(value: 'full', child: Text('Sólo ficha completa')),
            DropdownMenuItem(
              value: 'summary',
              child: Text('Resumida y completa'),
            ),
          ],
          onChanged: _editable
              ? (value) => setState(() => setting['detailVisibility'] = value)
              : null,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _addOption(String id) async {
    final option = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ListOptionDialog(status: id == 'status'),
    );
    if (!mounted || option == null) return;
    final entries = (_config!['lists'] as Map)[id] as List;
    if (entries.whereType<Map>().any(
      (entry) => entry['value'] == option['value'],
    )) {
      setState(() => _error = 'Ya existe ese valor en la lista');
      return;
    }
    setState(() => entries.add(option));
  }

  Widget _listSettings(String id, String title) {
    final entries = (_config!['lists'] as Map)[id] as List;
    return ExpansionTile(
      key: ValueKey('config-list-$id'),
      title: Text(title),
      subtitle: Text('${entries.length} opciones'),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final option in entries.whereType<Map>())
          Builder(
            builder: (context) {
              final used = _snapshot!.animals.any(
                (animal) => animal.value(id) == option['value'],
              );
              final fixedStatus =
                  id == 'status' &&
                  defaultStatusLabels.containsKey(option['value']);
              return Card(
                key: ValueKey('$id:${option['value']}'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor: ${option['value']}'),
                      TextFormField(
                        initialValue: option['label'] as String,
                        enabled: _editable,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Etiqueta visible',
                        ),
                        onChanged: (value) => option['label'] = value.trim(),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Escribe una etiqueta'
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          used ? 'Habilitada · en uso' : 'Habilitada',
                        ),
                        value: option['enabled'] == true,
                        onChanged: _editable && !used
                            ? (value) =>
                                  setState(() => option['enabled'] = value)
                            : null,
                      ),
                      if (id == 'status')
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Cuenta en inventario activo'),
                          value: option['active'] != false,
                          onChanged: _editable && !fixedStatus
                              ? (value) =>
                                    setState(() => option['active'] = value)
                              : null,
                        ),
                      if (!used && !fixedStatus)
                        TextButton.icon(
                          onPressed: _editable
                              ? () => setState(() => entries.remove(option))
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('Quitar opción'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        TextButton.icon(
          onPressed: _editable ? () => _addOption(id) : null,
          icon: const Icon(Icons.add),
          label: const Text('Añadir opción'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot, config = _config;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Campos y listas del rancho')),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (snapshot != null && config != null) ...[
                  Text(
                    snapshot.ranchName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (snapshot.operationStates['config:${snapshot.ownerId}'] !=
                      null)
                    Text(
                      pendingLabel(
                        snapshot.operationStates['config:${snapshot.ownerId}'],
                      ),
                    ),
                  if (!snapshot.canCaptureAnimals)
                    const Text(
                      'Sólo el propietario o administrador puede modificar esta configuración.',
                    ),
                  const Text(
                    'Los cambios se comparten con el rancho al confirmarse. Las opciones en uso conservan su valor y no se pueden desactivar.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Módulos',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final module in configurationModules.entries)
                    SwitchListTile(
                      title: Text(module.value),
                      value: (config['modules'] as Map)[module.key] == true,
                      onChanged: _editable && module.key != 'identification'
                          ? (value) => setState(
                              () => (config['modules'] as Map)[module.key] =
                                  value,
                            )
                          : null,
                    ),
                  const Divider(),
                  Text('Campos', style: Theme.of(context).textTheme.titleLarge),
                  for (final field in configurationFields)
                    _fieldSettings(field),
                  const Divider(),
                  Text('Listas', style: Theme.of(context).textTheme.titleLarge),
                  for (final list in configurationLists.entries)
                    _listSettings(list.key, list.value),
                  const SizedBox(height: 20),
                  if (snapshot.canCaptureAnimals &&
                      widget.writer.supportsConfiguration)
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(
                        _busy
                            ? 'Guardando…'
                            : _uncertain
                            ? 'Reintentar guardado'
                            : 'Guardar configuración',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListOptionDialog extends StatefulWidget {
  const _ListOptionDialog({required this.status});
  final bool status;
  @override
  State<_ListOptionDialog> createState() => _ListOptionDialogState();
}

class _ListOptionDialogState extends State<_ListOptionDialog> {
  final _form = GlobalKey<FormState>();
  final _value = TextEditingController(), _label = TextEditingController();
  bool _active = true;
  @override
  void dispose() {
    _value.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nueva opción'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'El valor queda fijo para mantener las referencias de los animales.',
            ),
            TextFormField(
              controller: _value,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Valor único'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Escribe un valor' : null,
            ),
            TextFormField(
              controller: _label,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Etiqueta visible'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Escribe una etiqueta' : null,
            ),
            if (widget.status)
              SwitchListTile(
                title: const Text('Cuenta en inventario activo'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, {
              'value': _value.text.trim(),
              'label': _label.text.trim(),
              'enabled': true,
              if (widget.status) 'active': _active,
            });
          }
        },
        child: const Text('Añadir'),
      ),
    ],
  );
}
