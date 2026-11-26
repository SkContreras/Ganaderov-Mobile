import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import '../../../auth/domain/auth_gateway.dart';
import '../../domain/inventory.dart';
import 'animal_editor.dart';
import '../../domain/animal_photos.dart';
import '../widgets/animal_gallery.dart';

class LivestockPage extends StatefulWidget {
  const LivestockPage({super.key, required this.repository, required this.auth, required this.ranchChanges});
  final InventoryRepository repository;
  final AuthGateway auth;
  final Listenable ranchChanges;
  @override
  State<LivestockPage> createState() => _LivestockPageState();
}

class _LivestockPageState extends State<LivestockPage> {
  final _search = TextEditingController();
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
      setState(() { _snapshot = null; _animals = []; _selectedId = null; _loading = false; _failed = false; });
    } else {
      _load();
    }
  }
  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    widget.ranchChanges.removeListener(_authChanged);
    _search.dispose();
    super.dispose();
  }
  Future<void> _load({String? keepSelected}) async {
    final request = ++_request;
    if (!widget.auth.signedIn || widget.auth.recovering) return;
    setState(() { _loading = true; _failed = false; _snapshot = null; _animals = []; _selectedId = null; });
    try {
      final snapshot = await widget.repository.load().timeout(const Duration(seconds: 45));
      final animals = snapshot.animals;
      if (!mounted || request != _request || !widget.auth.signedIn) return;
      setState(() { _snapshot = snapshot; _animals = animals; _selectedId = keepSelected; _loading = false; });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() { _loading = false; _failed = true; });
    }
  }

  Future<void> _edit([InventoryAnimal? animal]) async {
    final snapshot=_snapshot;
    final repository=widget.repository;
    if(snapshot==null||!snapshot.canManage||repository is! AnimalWriter)return;
    final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>AnimalEditor(snapshot:snapshot,writer:repository as AnimalWriter,animal:animal)));
    if(!mounted)return;
    if(saved==true){
      await _load();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Animal guardado.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _animals.where((animal) => animal.active != _archived && animal.matches(_search.text)).toList();
    final selected = _animals.where((a) => a.id == _selectedId).firstOrNull;
    if (selected != null) {
      return PopScope(canPop: false, onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _selectedId = null);
      }, child: _AnimalDetail(animal: selected, gallery: widget.repository is AnimalPhotos && _snapshot != null ? AnimalGallery(snapshot: _snapshot!, animal: selected, repository: widget.repository as AnimalPhotos, onChanged: () => _load(keepSelected: selected.id)) : null, onEdit: _snapshot?.canManage == true && widget.repository is AnimalWriter ? () => _edit(selected) : null, onBack: () => setState(() => _selectedId = null)));
    }
    return SafeArea(top: false, child: RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), sliver: SliverToBoxAdapter(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('Inventario de ganado', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                IconButton(tooltip: 'Actualizar inventario', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
              ]),
              if (_snapshot?.status == 'active') Text(_snapshot!.ranchName),
              if (_snapshot?.canManage == true && widget.repository is AnimalWriter) FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Registrar animal')),
              if (_loading) ...[const SizedBox(height: 16), const LinearProgressIndicator(), const Text('Consultando inventario…')],
              if (_failed) ...[const SizedBox(height: 16), const Text('No se pudo consultar el inventario. Revisa tu conexión.'), TextButton(onPressed: _load, child: const Text('Reintentar'))],
              if (!_loading && !_failed && _snapshot?.status != 'active')
                Text(_snapshot?.status == 'pending' ? 'Solicitud de acceso pendiente.' : 'No perteneces a un rancho activo.'),
              if (_snapshot?.status == 'active') ...[
                const SizedBox(height: 16),
                TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: InputDecoration(
                  hintText: 'Buscar por arete, nombre o raza',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Limpiar búsqueda', onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.close)),
                )),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: Text('Activos (${_animals.where((a) => a.active).length})'), selected: !_archived, onSelected: (_) => setState(() => _archived = false)),
                  ChoiceChip(label: Text('Archivo (${_animals.where((a) => !a.active).length})'), selected: _archived, onSelected: (_) => setState(() => _archived = true)),
                ]),
                const SizedBox(height: 12),
                Text('${filtered.length} animales', style: theme.textTheme.bodySmall),
                if (filtered.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No hay animales que coincidan.'))),
              ],
            ],
          ))),
          if (_snapshot?.status == 'active') SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) {
              final animal = filtered[index];
              return _AnimalCard(animal: animal, onTap: () => setState(() => _selectedId = animal.id));
            }, childCount: filtered.length)),
          ),
        ],
      ),
    ));
  }
}

String _date(DateTime? date) => date == null ? 'Sin fecha' : DateFormat('dd/MM/yyyy').format(date);
String _kg(double? weight) => weight == null ? 'Sin pesaje' : '${NumberFormat('0.##').format(weight)} kg';

class _AnimalCard extends StatelessWidget {
  const _AnimalCard({required this.animal, required this.onTap});
  final InventoryAnimal animal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final weight = animal.latestWeight;
    final colors = Theme.of(context).colorScheme;
    return Card(child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        CircleAvatar(backgroundColor: colors.primaryContainer, child: Icon(animal.value('sex') == 'Hembra' ? Icons.female : animal.value('sex') == 'Macho' ? Icons.male : Icons.pets_outlined, color: colors.onPrimaryContainer)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(animal.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text([animal.value('tag'), animal.value('breed'), animal.value('sex')].where((s) => s.isNotEmpty).join(' · ')),
          Text(animal.statusLabel, style: TextStyle(color: animal.active ? colors.primary : colors.onSurfaceVariant)),
          Text(weight == null ? 'Sin pesaje' : '${_kg(weight.weight)} · ${_date(weight.date)}'),
        ])),
        const Icon(Icons.chevron_right),
      ])),
    ));
  }
}

class _AnimalDetail extends StatelessWidget {
  const _AnimalDetail({required this.animal, required this.onBack, this.onEdit, this.gallery});
  final InventoryAnimal animal;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  final Widget? gallery;
  static const fields = {
    'tag':'Número de arete','name':'Nombre','sex':'Sexo','breed':'Raza','color':'Color','cross':'Cruza','markings':'Señas particulares',
    'officialId':'Identificador oficial','birthDate':'Fecha de nacimiento','entryDate':'Fecha de ingreso','originType':'Procedencia',
    'originName':'Rancho o vendedor de origen','weaningDate':'Fecha de destete','lot':'Lote','paddock':'Potrero','pen':'Corral',
    'locationSince':'Fecha de entrada a la ubicación','responsible':'Responsable','exitReason':'Motivo de baja','exitNotes':'Observaciones de baja','generalNotes':'Observaciones generales',
  };
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weights = animal.events.where((event) => event.type == 'weight').toList();
    final latest = animal.latestWeight;
    return SafeArea(top: false, child: ListView(padding: const EdgeInsets.all(20), children: [
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: onBack, icon: const Icon(Icons.arrow_back), label: const Text('Volver al inventario'))),
      Text(animal.title, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      Text(animal.statusLabel),
      if(gallery!=null) ...[const SizedBox(height:12),gallery!],
      if(onEdit!=null) OutlinedButton.icon(onPressed:onEdit,icon:const Icon(Icons.edit),label:const Text('Editar ficha y estado')),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Último peso registrado'),
        Text(_kg(latest?.weight), style: theme.textTheme.headlineSmall),
        if (latest != null) Text(_date(latest.date)),
      ]))),
      const SizedBox(height: 20),
      Text('Identificación y datos generales', style: theme.textTheme.titleLarge),
      Card(child: Column(children: [
        for (final field in fields.entries)
          if (animal.value(field.key).isNotEmpty) ListTile(title: Text(field.value), subtitle: Text(animal.value(field.key))),
      ])),
      const SizedBox(height: 20),
      Text('Historial de pesajes (${weights.length})', style: theme.textTheme.titleLarge),
      if (weights.isEmpty) const Text('No hay pesajes registrados.'),
      for (final event in weights) ListTile(leading: const Icon(Icons.monitor_weight_outlined), title: Text(_kg(event.weight)), subtitle: Text(_date(event.date))),
      const SizedBox(height: 20),
      Text('Historial de actividades', style: theme.textTheme.titleLarge),
      if (animal.events.isEmpty) const Text('No hay actividades registradas.'),
      for (final event in animal.events) ListTile(leading: const Icon(Icons.event_note_outlined), title: Text(event.label), subtitle: Text(event.notes.isEmpty ? _date(event.date) : '${_date(event.date)} · ${event.notes}')),
    ]));
  }
}
