import 'dart:async';


import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/ranch_illustration.dart';
import '../../../auth/domain/auth_gateway.dart';
import '../../domain/inventory.dart';
import '../../domain/animal_form_config.dart';
import 'animal_editor.dart';
import 'event_editor.dart';
import '../../domain/event_draft.dart';
import '../../../settings/domain/ranch.dart';
import '../../../settings/domain/animal_configuration.dart';
import '../../domain/animal_photos.dart';
import '../widgets/animal_gallery.dart';
import 'historical_event_editor.dart';
import '../../domain/local_changes.dart';

class LivestockPage extends StatefulWidget {
  const LivestockPage({
    super.key,
    required this.repository,
    required this.auth,
    required this.ranchChanges,
  });
  final InventoryRepository repository;
  final AuthGateway auth;
  final Listenable ranchChanges;
  @override
  State<LivestockPage> createState() => _LivestockPageState();
}

class _LivestockPageState extends State<LivestockPage> {
  final _search = TextEditingController();
  Timer? _searchTimer;
  String _query = '';
  void _scheduleSearch() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _query = _search.text);
    });
  }

  InventorySnapshot? _snapshot;
  List<InventoryAnimal> _animals = [];
  String? _selectedId;
  bool _archived = false, _loading = true, _failed = false;
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
      setState(() {
        _snapshot = null;
        _animals = [];
        _selectedId = null;
        _loading = false;
        _failed = false;
      });
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    widget.ranchChanges.removeListener(_authChanged);
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({String? keepSelected}) async {
    final request = ++_request;
    if (!widget.auth.signedIn || widget.auth.recovering) return;
    setState(() {
      _loading = true;
      _failed = false;
      _snapshot = null;
      _animals = [];
      _selectedId = null;
    });
    try {
      final snapshot = await widget.repository.load().timeout(
        const Duration(seconds: 45),
      );
      final animals = snapshot.animals;
      if (!mounted || request != _request || !widget.auth.signedIn) return;
      setState(() {
        _snapshot = snapshot;
        _animals = animals;
        _selectedId = keepSelected;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _edit([InventoryAnimal? animal]) async {
    final snapshot = _snapshot;
    final repository = widget.repository;
    if (snapshot == null ||
        !snapshot.canCaptureAnimals ||
        repository is! AnimalWriter) {
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AnimalEditor(
          snapshot: snapshot,
          writer: repository as AnimalWriter,
          animal: animal,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      await _localChanged(keepSelected: animal?.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ficha guardada; revisa su estado de sincronización.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _localChanged({String? keepSelected}) async {
    final repository = widget.repository,
        snapshot = _snapshot,
        request = _request;
    if (snapshot != null &&
        repository is OfflineInventory &&
        (repository as OfflineInventory).supportsOfflineInventory) {
      final next = await (repository as OfflineInventory).refreshLocalInventory(
        snapshot,
      );
      if (!mounted || request != _request || !widget.auth.signedIn) return;
      setState(() {
        _snapshot = next;
        _animals = next.animals;
        _selectedId = keepSelected;
      });
    } else {
      await _load(keepSelected: keepSelected);
    }
  }

  Future<void> _correctEvent(
    InventoryAnimal animal,
    AnimalEvent event, {
    bool remove = false,
  }) async {
    final snapshot = _snapshot, repository = widget.repository;
    if (snapshot == null ||
        !snapshot.canCaptureAnimals ||
        repository is! HistoricalEventWriter ||
        !(repository as HistoricalEventWriter).supportsHistoricalEvents) {
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => HistoricalEventEditor(
          snapshot: snapshot,
          animal: animal,
          event: event,
          writer: repository as HistoricalEventWriter,
          remove: remove,
        ),
      ),
    );
    if (mounted && saved == true) await _localChanged(keepSelected: animal.id);
  }

  bool _preparing = false;
  Future<void> _prepareOffline() async {
    final snapshot = _snapshot, repository = widget.repository;
    if (snapshot == null || repository is! OfflineInventory || _preparing) {
      return;
    }
    setState(() => _preparing = true);
    try {
      await (repository as OfflineInventory).prepareOfflineInventory(snapshot);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Revisiones descargadas para trabajar sin conexión durante 24 horas.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se completó la descarga. Actualiza el inventario y vuelve a intentarlo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _photoChanged(String animalId) async {
    final repository = widget.repository,
        snapshot = _snapshot,
        request = _request;
    if (snapshot == null) return;
    if (repository is OfflineAnimalPhotos &&
        (repository as OfflineAnimalPhotos).supportsOfflinePhotoChanges) {
      final next = await (repository as OfflineAnimalPhotos)
          .refreshPhotoChanges(snapshot);
      if (!mounted || request != _request || !widget.auth.signedIn) return;
      setState(() {
        _snapshot = next;
        _animals = next.animals;
        _selectedId = animalId;
      });
    } else {
      await _load(keepSelected: animalId);
    }
  }

  bool _statusBusy = false;
  Future<void> _changeStatus(InventoryAnimal animal) async {
    final snapshot = _snapshot, repository = widget.repository;
    if (_statusBusy ||
        snapshot == null ||
        !snapshot.canCaptureAnimals ||
        repository is! AnimalLifecycleWriter) {
      return;
    }
    final config = AnimalFormConfig(snapshot.config);
    final choices = config
        .choices('status')
        .entries
        .where((e) => config.active(e.key) != animal.active)
        .toList();
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay estados configurados para esta transición.'),
        ),
      );
      return;
    }
    final status = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(animal.active ? 'Archivar animal' : 'Restaurar animal'),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Se conservarán la ficha, fotografías y actividades. Selecciona el nuevo estado.',
            ),
          ),
          for (final e in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e.key),
              child: Text(e.value),
            ),
        ],
      ),
    );
    if (!mounted || status == null || _statusBusy) return;
    setState(() => _statusBusy = true);
    try {
      await (repository as AnimalLifecycleWriter).setAnimalStatus(
        snapshot,
        animal.id,
        status,
      );
      if (mounted) {
        _archived = !config.active(status);
        await _localChanged(keepSelected: animal.id);
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${e.message}. Si falta un motivo, usa Editar ficha y estado.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        await _load(keepSelected: animal.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se confirmó el cambio. Revisa el estado antes de repetir.',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  Future<void> _registerEvent(InventoryAnimal animal, String type) async {
    final snapshot = _snapshot;
    final repository = widget.repository;
    if (snapshot == null ||
        snapshot.status != 'active' ||
        !animal.active ||
        repository is! AnimalEventWriter) {
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventEditor(
          snapshot: snapshot,
          animal: animal,
          writer: repository as AnimalEventWriter,
          initialType: type,
        ),
      ),
    );
    if (!mounted || saved != true) return;
    if (snapshot.offlineWritesEnabled) {
      await _localChanged(keepSelected: animal.id);
    } else {
      if (widget.ranchChanges is RanchRepository) {
        (widget.ranchChanges as RanchRepository).invalidate();
      }
      await _load(keepSelected: animal.id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registro guardado en el dispositivo. Consulta Sincronización en Ajustes.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = _animals.where((a) => a.active).length;
    final filtered = _animals
        .where(
          (animal) =>
              animal.active != _archived &&
              (_query.trim().isEmpty || animal.matches(_query)),
        )
        .toList();
    final selected = _animals.where((a) => a.id == _selectedId).firstOrNull;
    if (selected != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) setState(() => _selectedId = null);
        },
        child: _AnimalDetail(
          animal: selected,
          config: AnimalFormConfig(_snapshot!.config),
          animals: _animals,
          onRegister:
              selected.active &&
                  widget.repository is AnimalEventWriter &&
                  ['owner', 'admin', 'worker'].contains(_snapshot?.role)
              ? (type) => _registerEvent(selected, type)
              : null,
          gallery: widget.repository is AnimalPhotos && _snapshot != null
              ? AnimalGallery(
                  snapshot: _snapshot!,
                  animal: selected,
                  repository: widget.repository as AnimalPhotos,
                  onChanged: () => _photoChanged(selected.id),
                )
              : null,
          onEdit:
              _snapshot?.canCaptureAnimals == true &&
                  widget.repository is AnimalWriter
              ? () => _edit(selected)
              : null,
          onChangeStatus:
              !_statusBusy &&
                  _snapshot?.canCaptureAnimals == true &&
                  widget.repository is AnimalLifecycleWriter
              ? () => _changeStatus(selected)
              : null,
          onCorrect:
              _snapshot?.canCaptureAnimals == true &&
                  selected.active &&
                  widget.repository is HistoricalEventWriter &&
                  (widget.repository as HistoricalEventWriter)
                      .supportsHistoricalEvents
              ? (event) => _correctEvent(selected, event)
              : null,
          onDelete:
              _snapshot?.canCaptureAnimals == true &&
                  selected.active &&
                  widget.repository is HistoricalEventWriter &&
                  (widget.repository as HistoricalEventWriter)
                      .supportsHistoricalEvents
              ? (event) => _correctEvent(selected, event, remove: true)
              : null,
          onBack: () => setState(() => _selectedId = null),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Inventario de ganado',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Actualizar inventario',
                          onPressed: _loading ? null : _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (_snapshot?.status == 'active')
                      Text(_snapshot!.ranchName),
                    if (_snapshot?.offline == true)
                      Text(
                        'Sin conexión · actividades pendientes de sincronización · ${DateFormat('dd/MM HH:mm').format(_snapshot!.cachedAt!)}',
                      ),
                    if (_snapshot?.canCaptureAnimals == true &&
                        widget.repository is AnimalWriter)
                      FilledButton.icon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('Registrar animal'),
                      ),
                    if (_snapshot?.offline == false &&
                        widget.repository is OfflineInventory &&
                        (widget.repository as OfflineInventory)
                            .supportsOfflineInventory)
                      TextButton.icon(
                        onPressed: _preparing ? null : _prepareOffline,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: Text(
                          _preparing
                              ? 'Preparando…'
                              : 'Preparar trabajo sin conexión',
                        ),
                      ),
                    if (_loading) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const Text('Consultando inventario…'),
                    ],
                    if (_failed) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'No se pudo consultar el inventario. Revisa tu conexión.',
                      ),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Reintentar'),
                      ),
                    ],
                    if (!_loading && !_failed && _snapshot?.status != 'active')
                      Text(
                        _snapshot?.status == 'pending'
                            ? 'Solicitud de acceso pendiente.'
                            : 'No perteneces a un rancho activo.',
                      ),
                    if (_snapshot?.status == 'active') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _search,
                        onChanged: (_) {
                          setState(() {});
                          _scheduleSearch();
                        },
                        decoration: InputDecoration(
                          hintText: 'Buscar por arete, nombre o raza',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpiar búsqueda',
                                  onPressed: () {
                                    _searchTimer?.cancel();
                                    _search.clear();
                                    setState(() {
                                      _query = '';
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('Activos ($activeCount)'),
                            selected: !_archived,
                            onSelected: (_) =>
                                setState(() => _archived = false),
                          ),
                          ChoiceChip(
                            label: Text(
                              'Archivo (${_animals.length - activeCount})',
                            ),
                            selected: _archived,
                            onSelected: (_) => setState(() => _archived = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${filtered.length} animales',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_animals.isEmpty && !_archived && _query.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Center(
                            child: SizedBox(
                              width: 180,
                              child: RanchIllustration(
                                'ranch-inventory-empty',
                                aspectRatio: 190 / 84,
                              ),
                            ),
                          ),
                        ),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text('No hay animales que coincidan.'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (_snapshot?.status == 'active')
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final animal = filtered[index];
                    return _AnimalCard(
                      key: ValueKey(animal.id),
                      animal: animal,
                      config: AnimalFormConfig(_snapshot!.config),
                      onTap: () => setState(() => _selectedId = animal.id),
                    );
                  }, childCount: filtered.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime? date) =>
    date == null ? 'Sin fecha' : DateFormat('dd/MM/yyyy').format(date);
String _kg(double? weight) =>
    weight == null ? 'Sin pesaje' : '${NumberFormat('0.##').format(weight)} kg';

class _AnimalCard extends StatelessWidget {
  const _AnimalCard({
    super.key,
    required this.animal,
    required this.onTap,
    required this.config,
  });
  final InventoryAnimal animal;
  final VoidCallback onTap;
  final AnimalFormConfig config;
  static const _summaryFieldIds = {'tag', 'sex', 'color'};

  @override
  Widget build(BuildContext context) {
    final weight = animal.latestWeight;
    final colors = Theme.of(context).colorScheme;
    final summaryFields = <Widget>[];
    for (final field in configurationFields) {
      if (!_summaryFieldIds.contains(field.id) ||
          !config.detailVisible(field, summary: true)) {
        continue;
      }
      final value = animal.value(field.id);
      if (value.isEmpty) continue;
      summaryFields.add(
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${config.label(field)}: ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: value),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                child: Icon(
                  animal.value('sex') == 'Hembra'
                      ? Icons.female
                      : animal.value('sex') == 'Macho'
                      ? Icons.male
                      : Icons.pets_outlined,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animal.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (summaryFields.isNotEmpty)
                      Wrap(spacing: 12, runSpacing: 4, children: summaryFields),
                    Text(
                      animal.statusLabel,
                      style: TextStyle(
                        color: animal.active
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    if (animal.syncState != null)
                      Text(pendingLabel(animal.syncState)),
                    Wrap(
                      spacing: 8,
                      children: [
                        Text(_kg(weight?.weight)),
                        if (weight != null) Text(_date(weight.date)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimalDetail extends StatelessWidget {
  const _AnimalDetail({
    required this.animal,
    required this.onBack,
    required this.config,
    required this.animals,
    this.onEdit,
    this.gallery,
    this.onRegister,
    this.onChangeStatus,
    this.onCorrect,
    this.onDelete,
  });
  final InventoryAnimal animal;
  final VoidCallback onBack;
  final AnimalFormConfig config;
  final List<InventoryAnimal> animals;
  final VoidCallback? onEdit, onChangeStatus;
  final Widget? gallery;
  final ValueChanged<String>? onRegister;
  final ValueChanged<AnimalEvent>? onCorrect, onDelete;
  String fieldValue(AnimalField field) {
    final value = animal.fields[field.id];
    if (value == null) return '';
    if (field.kind == 'boolean') return value == true ? 'Sí' : 'No';
    if (field.kind == 'age' && value is Map) {
      return '${value['monthsAtRecord'] ?? ''} meses al ${value['recordedAt'] ?? ''}';
    }
    if (field.kind == 'parent') {
      return animals.where((a) => a.id == value).firstOrNull?.title ??
          value.toString();
    }
    return config.choices(field.id)[value.toString()] ?? value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weights = animal.events
        .where((event) => event.type == 'weight')
        .toList();
    final latest = animal.latestWeight;
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver al inventario'),
            ),
          ),
          Text(
            animal.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(animal.statusLabel),
          if (animal.syncState != null) Text(pendingLabel(animal.syncState)),
          if (onRegister != null)
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => onRegister!('weight'),
                  icon: const Icon(Icons.monitor_weight_outlined),
                  label: const Text('Registrar pesaje'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onRegister!('vaccine'),
                  icon: const Icon(Icons.medical_services_outlined),
                  label: const Text('Registrar tratamiento'),
                ),
              ],
            ),
          if (gallery != null) ...[const SizedBox(height: 12), gallery!],
          if (onEdit != null)
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit),
              label: const Text('Editar ficha y estado'),
            ),
          if (onChangeStatus != null)
            OutlinedButton(
              onPressed: onChangeStatus,
              child: Text(
                animal.active ? 'Archivar animal' : 'Restaurar animal',
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Último peso registrado'),
                  Text(
                    _kg(latest?.weight),
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (latest != null) Text(_date(latest.date)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Identificación y datos generales',
            style: theme.textTheme.titleLarge,
          ),
          Card(
            child: Column(
              children: [
                for (final field in configurationFields)
                  if (config.detailVisible(field) &&
                      fieldValue(field).isNotEmpty)
                    ListTile(
                      title: Text(config.label(field)),
                      subtitle: Text(fieldValue(field)),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Historial de pesajes (${weights.length})',
            style: theme.textTheme.titleLarge,
          ),
          if (weights.isEmpty) const Text('No hay pesajes registrados.'),
          for (final event in weights)
            ListTile(
              leading: const Icon(Icons.monitor_weight_outlined),
              title: Text(_kg(event.weight)),
              subtitle: Text(_date(event.date)),
            ),
          const SizedBox(height: 20),
          Text('Historial de actividades', style: theme.textTheme.titleLarge),
          if (animal.historyState != null)
            Text(pendingLabel(animal.historyState)),
          if (animal.events.isEmpty)
            const Text('No hay actividades registradas.'),
          for (final event in animal.events)
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: Text(event.label),
              subtitle: Text(
                [
                  _date(event.date),
                  event.product,
                  event.notes,
                  event.actor,
                  if (event.syncState != null) pendingLabel(event.syncState),
                  if (event.fromJourney) 'Se corrige desde su jornada',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              trailing:
                  !event.fromJourney &&
                      event.id.isNotEmpty &&
                      (onCorrect != null || onDelete != null)
                  ? PopupMenuButton<String>(
                      tooltip: 'Acciones del historial',
                      onSelected: (action) {
                        if (action == 'edit') {
                          onCorrect?.call(event);
                        } else {
                          onDelete?.call(event);
                        }
                      },
                      itemBuilder: (_) => [
                        if (onCorrect != null)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Corregir con motivo'),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar con motivo'),
                          ),
                      ],
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
