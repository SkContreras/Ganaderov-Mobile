import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../domain/event_draft.dart';
import '../../domain/inventory.dart';

class HistoricalEventEditor extends StatefulWidget {
  const HistoricalEventEditor({
    super.key,
    required this.snapshot,
    required this.animal,
    required this.event,
    required this.writer,
    this.remove = false,
  });
  final InventorySnapshot snapshot;
  final InventoryAnimal animal;
  final AnimalEvent event;
  final HistoricalEventWriter writer;
  final bool remove;
  @override
  State<HistoricalEventEditor> createState() => _HistoricalEventEditorState();
}

class _HistoricalEventEditorState extends State<HistoricalEventEditor> {
  final _form = GlobalKey<FormState>();
  final _operationId = const Uuid().v4();
  final _reason = TextEditingController();
  late final _date = TextEditingController(
    text:
        widget.event.raw['date']?.toString() ??
        (widget.event.date == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(widget.event.date!)),
  );
  late final _weight = TextEditingController(
    text: widget.event.weight?.toString() ?? '',
  );
  late final _product = TextEditingController(text: widget.event.product);
  late final _notes = TextEditingController(text: widget.event.notes);
  bool _busy = false, _uncertain = false;
  String? _error;
  @override
  void dispose() {
    for (final controller in [_date, _weight, _product, _notes, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.remove) {
        await widget.writer.deleteHistoricalEvent(
          widget.snapshot,
          widget.animal.id,
          widget.event,
          _reason.text.trim(),
          operationId: _operationId,
        );
      } else {
        final fields = <String, dynamic>{};
        if (_date.text.trim() != (widget.event.raw['date']?.toString() ?? '')) {
          fields['date'] = _date.text.trim();
        }
        if (_product.text.trim() != widget.event.product) {
          fields['product'] = _product.text.trim();
        }
        if (_notes.text.trim() != widget.event.notes) {
          fields['notes'] = _notes.text.trim();
        }
        if (widget.event.type == 'weight') {
          final weight = double.parse(_weight.text.trim().replaceAll(',', '.'));
          if (weight != widget.event.weight) fields['weight'] = weight;
        }
        if (fields.isEmpty) {
          throw StateError('Modifica al menos un dato del evento');
        }
        await widget.writer.updateHistoricalEvent(
          widget.snapshot,
          widget.animal.id,
          widget.event,
          fields,
          _reason.text.trim(),
          operationId: _operationId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error = 'No se confirmó el guardado local. Reintenta conservando los mismos datos.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _uncertain;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.remove ? 'Eliminar actividad' : 'Corregir actividad',
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.animal.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(widget.event.label),
                const SizedBox(height: 12),
                Text(
                  widget.remove
                      ? 'La solicitud quitará esta actividad del historial cuando el servidor la confirme. Se conservará el motivo en la auditoría.'
                      : 'El tipo de actividad y su autor original se conservan. La corrección requiere un motivo.',
                ),
                const Text(
                  'El cambio se guarda primero en el dispositivo y permanece pendiente hasta su confirmación.',
                ),
                if (!widget.remove) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _date,
                    enabled: !locked,
                    decoration: const InputDecoration(
                      labelText: 'Fecha (AAAA-MM-DD)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final date = DateTime.tryParse(value ?? '');
                      return date == null ||
                              !RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                  .hasMatch(value ?? '')
                          ? 'Introduce una fecha válida'
                          : null;
                    },
                  ),
                  if (widget.event.type == 'weight') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _weight,
                      enabled: !locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Peso (kg)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final n = double.tryParse(
                          (value ?? '').replaceAll(',', '.'),
                        );
                        return n == null || !n.isFinite || n < 0 || n > 100000
                            ? 'Introduce un peso válido'
                            : null;
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _product,
                    enabled: !locked,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Producto o tratamiento',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _notes,
                    enabled: !locked,
                    maxLines: 3,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        widget.event.type == 'note' &&
                            (value ?? '').trim().isEmpty
                        ? 'Escribe la observación'
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  enabled: !locked,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Motivo obligatorio',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Indica el motivo' : null,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(
                    _busy
                        ? 'Guardando…'
                        : _uncertain
                        ? 'Reintentar'
                        : widget.remove
                        ? 'Solicitar eliminación'
                        : 'Guardar corrección',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
