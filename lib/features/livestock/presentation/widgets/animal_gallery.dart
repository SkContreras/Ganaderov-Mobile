import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/inventory.dart';
import '../../domain/animal_photos.dart';
import 'framed_photo.dart';
import 'photo_crop_editor.dart';

/// Opens the native Android share sheet with the original private photo.
Future<void> shareAnimalPhoto({
  required BuildContext context,
  required InventorySnapshot snapshot,
  required InventoryAnimal animal,
  required AnimalPhotos repository,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent() || snapshot.status != 'active') return;
  final photos = AnimalPhoto.fromSnapshot(snapshot, animal.id);
  final ordered = [
    ...photos.where((p) => p.primary),
    ...photos.where((p) => !p.primary),
  ];
  if (ordered.isEmpty) return;
  final photo = await showDialog<AnimalPhoto>(
    context: context,
    builder: (_) => _PhotoSelectionDialog(
      title: 'Compartir fotografía',
      subtitle: 'Elige el original de ${animal.title}. La imagen puede incluir metadatos de la cámara.',
      photos: ordered,
      snapshot: snapshot,
      animalId: animal.id,
      repository: repository,
    ),
  );
  if (photo == null || !context.mounted || !isCurrent()) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await repository.readPhoto(snapshot, animal.id, photo);
    if (!context.mounted || !isCurrent()) return;
    final mime = imageMime(bytes);
    if (mime == null || bytes.length > 10 * 1024 * 1024) {
      throw StateError('Formato de fotografía no compatible.');
    }
    await const MethodChannel('com.ganaderov.mobile/photo_share')
        .invokeMethod<void>('sharePhoto', {'bytes': bytes, 'mime': mime});
  } catch (_) {
    if (context.mounted && isCurrent()) {
      messenger.showSnackBar(SnackBar(content: Text(snapshot.offline
          ? 'No se pudo compartir. Comprueba que la foto esté guardada en el dispositivo.'
          : 'No se pudo compartir la fotografía. Inténtalo de nuevo.')));
    }
  }
}

class AnimalGallery extends StatefulWidget {
  const AnimalGallery({
    super.key,
    required this.snapshot,
    required this.animal,
    required this.repository,
    required this.onChanged,
  });
  final InventorySnapshot snapshot;
  final InventoryAnimal animal;
  final AnimalPhotos repository;
  final Future<void> Function() onChanged;
  @override
  State<AnimalGallery> createState() => _AnimalGalleryState();
}

class _AnimalGalleryState extends State<AnimalGallery> {
  bool _busy = false;
  String? _error;
  final _picker = ImagePicker();
  final _heroFrame = GlobalKey();
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo confirmar la operación. Actualiza la ficha antes de repetirla.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(ImageSource source) => _run(() async {
    final file = await _picker.pickImage(
      source: source,
      requestFullMetadata: false,
    );
    if (file == null || !mounted) return;
    if (await file.length() > 10 * 1024 * 1024) {
      throw StateError('La imagen supera 10 MB.');
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await widget.repository.addPhoto(
      widget.snapshot,
      widget.animal.id,
      bytes,
      file.name,
    );
    if (mounted) await widget.onChanged();
  });
  Future<void> _editCrop(
    AnimalPhoto photo, {
    required AnimalPhotos repository,
    required InventorySnapshot snapshot,
    required String animalId,
  }) async {
    if (repository is! AnimalPhotoFraming || _busy) return;
    await _run(() async {
      final bytes = await repository.readPhoto(snapshot, animalId, photo);
      if (!mounted ||
          widget.snapshot.userId != snapshot.userId ||
          widget.snapshot.ownerId != snapshot.ownerId ||
          widget.animal.id != animalId) {
        return;
      }
      final frame = _heroFrame.currentContext?.findRenderObject() as RenderBox?;
      final aspectRatio = frame != null && frame.hasSize && !frame.size.isEmpty
          ? frame.size.aspectRatio
          : 4 / 3;
      final crop = await showDialog<PhotoCrop>(
        context: context,
        builder: (_) => PhotoCropEditor(
          bytes: bytes,
          initial: photo.crop,
          aspectRatio: aspectRatio,
        ),
      );
      if (crop == null ||
          !mounted ||
          widget.snapshot.userId != snapshot.userId ||
          widget.snapshot.ownerId != snapshot.ownerId ||
          widget.animal.id != animalId) {
        return;
      }
      await (repository as AnimalPhotoFraming).savePhotoCrop(
        snapshot,
        animalId,
        photo.id,
        crop,
      );
      if (mounted) await widget.onChanged();
    });
  }

  Future<void> _remove(AnimalPhoto photo) async {
    final repository = widget.repository,
        snapshot = widget.snapshot,
        animalId = widget.animal.id;
    if (repository is! AnimalPhotoRemoval || _busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar fotografía'),
        content: const Text(
          'Se quitará de la galería sin borrar físicamente el archivo remoto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (!mounted ||
        yes != true ||
        widget.snapshot.userId != snapshot.userId ||
        widget.snapshot.ownerId != snapshot.ownerId ||
        widget.animal.id != animalId) {
      return;
    }
    await _run(() async {
      await (repository as AnimalPhotoRemoval).removePhoto(
        snapshot,
        animalId,
        photo.id,
      );
      if (mounted) await widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final photos = AnimalPhoto.fromSnapshot(widget.snapshot, widget.animal.id);
    final ordered = [
      ...photos.where((p) => p.primary),
      ...photos.where((p) => !p.primary),
    ];
    final offlineCapable =
        widget.repository is OfflineAnimalPhotos &&
        (widget.repository as OfflineAnimalPhotos).supportsOfflinePhotoChanges;
    final canChange =
        widget.snapshot.canManage ||
        (offlineCapable &&
            widget.snapshot.offline &&
            widget.snapshot.status == 'active' &&
            ['owner', 'admin'].contains(widget.snapshot.role));
    final syncState = widget.snapshot.photoSyncStates[widget.animal.id];
    final locked = _busy || syncState != null;
    final scope = widget.snapshot;
    final animalId = widget.animal.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Fotografías (${photos.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (widget.snapshot.offline)
          const Text(
            'Sin conexión · fotografías guardadas en este dispositivo.',
          ),
        if (syncState != null)
          Text(switch (syncState) {
            'pending' => 'Cambio guardado en el dispositivo, pendiente de sincronización. Espera a que se confirme antes de otro cambio en esta galería.',
            'confirmed' => 'Cambio confirmado. Actualiza el inventario para seguir editando.',
            _ => 'El cambio necesita revisión. Abre Sincronización en Ajustes antes de seguir editando.',
          }, key: const ValueKey('photo-sync-state')),
        if (ordered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.photo_outlined, size: 42),
                  Text('Sin fotografías'),
                ],
              ),
            ),
          ),
        if (ordered.isNotEmpty)
          SizedBox(
            key: _heroFrame,
            height: 190,
            child: _PrivatePhoto(
              key: ValueKey('hero-${ordered.first.id}'),
              snapshot: widget.snapshot,
              animalId: widget.animal.id,
              photo: ordered.first,
              repository: widget.repository,
              height: 190,
            ),
          ),
        if (ordered.isNotEmpty && scope.status == 'active')
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(() => shareAnimalPhoto(
              context: context,
              snapshot: scope,
              animal: widget.animal,
              repository: widget.repository,
              isCurrent: () => mounted &&
                  identical(widget.snapshot, scope) &&
                  widget.animal.id == animalId,
            )),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartir fotografía'),
          ),
        if (ordered.isNotEmpty) const SizedBox(height: 8),
        if (ordered.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ordered.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final photo = ordered[i];
                return SizedBox(
                  width: 100,
                  child: Column(
                    children: [
                      Expanded(
                        child: _PrivatePhoto(
                          key: ValueKey(photo.id),
                          snapshot: widget.snapshot,
                          animalId: widget.animal.id,
                          photo: photo,
                          repository: widget.repository,
                          height: 78,
                          thumbnail: true,
                        ),
                      ),
                      if (canChange)
                        IconButton(
                          tooltip: photo.primary
                              ? 'Foto principal'
                              : 'Elegir como principal',
                          onPressed: locked || photo.primary
                              ? null
                              : () => _run(() async {
                                  await widget.repository.primaryPhoto(
                                    widget.snapshot,
                                    widget.animal.id,
                                    photo.id,
                                  );
                                  if (mounted) await widget.onChanged();
                                }),
                          icon: Icon(
                            photo.primary ? Icons.star : Icons.star_border,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        if (canChange &&
            widget.repository is AnimalPhotoFraming &&
            ordered.isNotEmpty)
          TextButton.icon(
            onPressed: locked
                ? null
                : () async {
                    final snapshot = widget.snapshot,
                        animalId = widget.animal.id,
                        repository = widget.repository;
                    final photo = await showDialog<AnimalPhoto>(
                      context: context,
                      builder: (context) => _PhotoSelectionDialog(
                        title: 'Elegir fotografía',
                        subtitle: 'Selecciona la imagen que quieres encuadrar.',
                        photos: ordered,
                        snapshot: snapshot,
                        animalId: animalId,
                        repository: repository,
                      ),
                    );
                    if (mounted && photo != null) {
                      await _editCrop(
                        photo,
                        repository: repository,
                        snapshot: snapshot,
                        animalId: animalId,
                      );
                    }
                  },
            icon: const Icon(Icons.crop),
            label: const Text('Editar encuadre'),
          ),
        if (canChange &&
            widget.repository is AnimalPhotoRemoval &&
            ordered.isNotEmpty)
          TextButton(
            onPressed: locked
                ? null
                : () async {
                    final photo = await showDialog<AnimalPhoto>(
                      context: context,
                      builder: (context) => _PhotoSelectionDialog(
                        title: 'Quitar fotografía',
                        subtitle: 'Selecciona la imagen que quieres quitar de la galería.',
                        photos: ordered,
                        snapshot: widget.snapshot,
                        animalId: widget.animal.id,
                        repository: widget.repository,
                      ),
                    );
                    if (mounted && photo != null) await _remove(photo);
                  },
            child: const Text('Quitar fotografía'),
          ),
        if (widget.snapshot.canManage)
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Añadir fotografía',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Elige una imagen o toma una nueva · hasta 10 MB.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: locked
                          ? null
                          : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Cámara'),
                    ),
                    OutlinedButton.icon(
                      onPressed: locked
                          ? null
                          : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galería'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class _PrivatePhoto extends StatefulWidget {
  const _PrivatePhoto({
    super.key,
    required this.snapshot,
    required this.animalId,
    required this.photo,
    required this.repository,
    required this.height,
    this.thumbnail = false,
  });
  final InventorySnapshot snapshot;
  final String animalId;
  final AnimalPhoto photo;
  final AnimalPhotos repository;
  final double height;
  final bool thumbnail;
  @override
  State<_PrivatePhoto> createState() => _PrivatePhotoState();
}

class _PrivatePhotoState extends State<_PrivatePhoto> {
  late Future<Uint8List> _bytes;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _bytes = widget.repository.readPhoto(
      widget.snapshot,
      widget.animalId,
      widget.photo,
    );
  }

  @override
  void didUpdateWidget(covariant _PrivatePhoto old) {
    super.didUpdateWidget(old);
    if (old.snapshot.userId != widget.snapshot.userId ||
        old.snapshot.ownerId != widget.snapshot.ownerId ||
        old.animalId != widget.animalId ||
        old.photo.path != widget.photo.path ||
        old.snapshot.offline != widget.snapshot.offline ||
        old.snapshot.photoSyncStates[widget.animalId] !=
            widget.snapshot.photoSyncStates[widget.animalId]) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    width: double.infinity,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: IconButton(
                tooltip: 'Reintentar fotografía',
                onPressed: () => setState(_load),
                icon: const Icon(Icons.broken_image_outlined),
              ),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: InteractiveViewer(
                  child: Image(
                    image: boundedPhoto(s.data!, 2048),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            child: FramedPhoto(
              bytes: s.data!,
              crop: widget.photo.crop,
              cacheWidth: widget.thumbnail ? 320 : 1200,
            ),
          );
        },
      ),
    ),
  );
}

class _PhotoSelectionDialog extends StatelessWidget {
  const _PhotoSelectionDialog({
    required this.title,
    required this.subtitle,
    required this.photos,
    required this.snapshot,
    required this.animalId,
    required this.repository,
  });
  final String title, subtitle, animalId;
  final List<AnimalPhoto> photos;
  final InventorySnapshot snapshot;
  final AnimalPhotos repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: 'Cerrar selector',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(subtitle),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      key: ValueKey('select-photo-${photo.id}'),
                      minTileHeight: 84,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      leading: SizedBox(
                        width: 64,
                        height: 64,
                        child: IgnorePointer(
                          child: _PrivatePhoto(
                            snapshot: snapshot,
                            animalId: animalId,
                            photo: photo,
                            repository: repository,
                            height: 64,
                            thumbnail: true,
                          ),
                        ),
                      ),
                      title: Text(
                        photo.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        photo.primary
                            ? 'Foto principal'
                            : 'Fotografía adicional',
                        style: TextStyle(
                          color: photo.primary
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        photo.primary
                            ? Icons.star_rounded
                            : Icons.chevron_right,
                        color: photo.primary
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      onTap: () => Navigator.pop(context, photo),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
