import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../../core/sync/conflict_review.dart';
import '../../../../core/sync/manual_resolution.dart';
import '../../../../core/sync/event_outbox.dart';
import '../../../livestock/domain/event_draft.dart';
import '../../../livestock/domain/local_changes.dart';

class SyncPanel extends StatefulWidget {
  const SyncPanel({super.key, required this.access});
  final OutboxAccess access;
  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  List<PendingEvent>? _items;
  List<Map<String, dynamic>> _operations = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool send = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _items = null;
    });
    try {
      if (send) await widget.access.syncEvents(manual: true);
      final items = await widget.access.pendingEvents();
      final access = widget.access;
      final ops = access is ConflictAccess
          ? await (access as ConflictAccess).reviewOperations()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _items = items;
          _operations = ops;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo consultar la cola.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspect(PendingEvent p) async {
    if (p.operation == null) return;
    final terminal = ['conflict', 'rejected'].contains(p.state);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(terminal ? 'Revisar conflicto' : 'Revisar operación'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                terminal ? conflictExplanation(p.error) : 'El resultado aún no está confirmado. Conserva el identificador original.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(p.operation),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _discard(PendingEvent p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          p.operation != null
              ? 'Archivar conflicto'
              : 'Descartar registro local',
        ),
        content: Text(
          p.operation != null
              ? 'Se ocultará de la cola activa, pero se conservará el cuerpo original en SQLite. No modifica Supabase ni resuelve el conflicto remoto.'
              : 'Esto elimina la operación pendiente. Si ya llegó al servidor, no elimina el historial remoto. Comprueba antes de volver a registrarla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    try {
      await widget.access.discardPending(p);
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo descartar. Espera a que termine el envío.',
        );
      }
    }
  }

  Future<void> _reviewUniversal(Map<String, dynamic> entry) async {
    final access = widget.access as ConflictAccess;
    try {
      final op = Map<String, dynamic>.from(entry['operation'] as Map);
      final current = await access.currentConflictEntity(entry);
      final fields = resolutionFields(op, current), selected = <String>{};
      if (!mounted) return;
      final result = await showDialog<List<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('Resolver ${op['action']}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Revisión ${current['revision']}. Marca los valores locales que deseas conservar.',
                  ),
                  for (final f in fields)
                    CheckboxListTile(
                      value: selected.contains(f['key']),
                      title: Text(f['key'].toString()),
                      subtitle: Text(
                        'Servidor: ${jsonEncode(f['remote'])}\nLocal: ${jsonEncode(f['local'])}',
                      ),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          selected.add(f['key'] as String);
                        } else {
                          selected.remove(f['key']);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, selected.toList()),
                child: const Text('Guardar resolución'),
              ),
            ],
          ),
        ),
      );
      if (result == null || !mounted) return;
      await access.resolveOperation(entry, current, result);
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _inspectUniversal(Map<String, dynamic> entry) async {
    final operation = entry['operation'] as Map;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Datos guardados'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(pendingLabel(entry['state'] as String)),
              if (entry['draft'] == true)
                const Text(
                  'Esta captura espera una operación anterior y todavía no se ha enviado.',
                ),
              if (entry['error'] != null) Text(entry['error'].toString()),
              const SizedBox(height: 12),
              SelectableText(
                const JsonEncoder.withIndent('  ')
                    .convert(operation['changes']),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _archiveUniversal(Map<String, dynamic> entry) async {
    if (entry['draft'] == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Archivar borrador dependiente'),
          content: const Text(
            'El borrador no se ha enviado. Se conservará para revisión y las capturas que dependan de él quedarán bloqueadas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archivar'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    try {
      await (widget.access as ConflictAccess).archiveOperation(
        entry,
        entry['state'] != 'archived',
      );
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sincronización',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Los registros pendientes se envían automáticamente mientras la app está abierta.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (_items != null) ...[
            Text('${_items!.length} registros pendientes'),
            for (final p in _items!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${eventTypes[p.draft.type] ?? p.draft.type} · ${p.draft.date}',
                ),
                subtitle: Text(
                  [
                    if (p.draft.weight != null) '${p.draft.weight} kg',
                    if (p.draft.product.isNotEmpty) p.draft.product,
                    'Animal: ${p.animalId}',
                    if (p.operation != null) 'RPC v1',
                    if (p.state == 'conflict') 'Conflicto',
                    if (p.state == 'rejected') 'Rechazado',
                    if (p.error.isNotEmpty) p.error,
                  ].join(' · '),
                ),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    if (p.operation != null)
                      IconButton(
                        tooltip: 'Revisar operación',
                        onPressed: _busy ? null : () => _inspect(p),
                        icon: const Icon(Icons.info_outline),
                      ),
                    if (p.operation == null ||
                        ['conflict', 'rejected'].contains(p.state))
                      IconButton(
                        tooltip: p.operation == null
                            ? 'Descartar pendiente'
                            : 'Archivar conflicto',
                        onPressed: _busy ? null : () => _discard(p),
                        icon: const Icon(Icons.archive_outlined),
                      ),
                  ],
                ),
              ),
          ],
          if (_operations.isNotEmpty) ...[
            const Divider(),
            const Text('Operaciones universales y archivadas'),
            for (final entry in _operations)
              ListTile(
                title: Text(
                  '${(entry['operation'] as Map)['action']} · ${entry['state'] == 'archived' ? 'Archivada' : pendingLabel(entry['state'] as String)}',
                ),
                subtitle: Text(
                  [
                    if (entry['draft'] == true)
                      'Borrador guardado; todavía no tiene cuerpo de envío',
                    if (entry['dependencies'] is List &&
                        (entry['dependencies'] as List).isNotEmpty)
                      'Depende de ${(entry['dependencies'] as List).length} capturas anteriores',
                    if (entry['error'] != null) entry['error'].toString(),
                    if (entry['receipt'] is Map &&
                        ['conflict', 'rejected'].contains(entry['state']))
                      conflictExplanation(
                        (entry['receipt'] as Map)['code']?.toString() ?? '',
                      ),
                    if (entry['resolvedBy'] != null) 'Se creó una resolución explícita; las dependencias anteriores requieren revisión',
                  ].join('\n'),
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Revisar datos guardados',
                      onPressed: _busy ? null : () => _inspectUniversal(entry),
                      icon: const Icon(Icons.info_outline),
                    ),
                    if (entry['resolvedBy'] == null &&
                        (entry['draft'] == true
                            ? ['waiting', 'blocked'].contains(entry['state'])
                            : [
                                'conflict',
                                'rejected',
                                'archived',
                              ].contains(entry['state'])))
                      IconButton(
                        tooltip: entry['state'] == 'archived'
                            ? 'Recuperar para revisión'
                            : 'Archivar',
                        onPressed: _busy
                            ? null
                            : () => _archiveUniversal(entry),
                        icon: const Icon(Icons.archive_outlined),
                      ),
                    if (entry['draft'] != true &&
                        entry['resolvedBy'] == null &&
                        ['conflict', 'rejected'].contains(entry['state']) &&
                        [
                          'animal.update',
                          'event.update',
                          'config.update',
                        ].contains((entry['operation'] as Map)['action']))
                      IconButton(
                        tooltip: 'Resolver conflicto',
                        onPressed: _busy ? null : () => _reviewUniversal(entry),
                        icon: const Icon(Icons.edit),
                      ),
                  ],
                ),
              ),
          ],
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _refresh(),
                child: const Text('Actualizar estado'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _refresh(send: true),
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar ahora'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
