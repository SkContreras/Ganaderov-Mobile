import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/animal_photos.dart';
import '../../domain/photo_crop_geometry.dart';
import 'framed_photo.dart';

class PhotoCropEditor extends StatefulWidget {
  const PhotoCropEditor({
    super.key,
    required this.bytes,
    required this.initial,
    this.aspectRatio = 4 / 3,
  }) : assert(aspectRatio > 0 && aspectRatio < double.infinity);
  final Uint8List bytes;
  final PhotoCrop initial;

  /// Matches the gallery hero measured when the editor opens.
  final double aspectRatio;

  @override
  State<PhotoCropEditor> createState() => _PhotoCropEditorState();
}

class _PhotoCropEditorState extends State<PhotoCropEditor> {
  late PhotoCrop _crop = widget.initial;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    _loaded,
    onError: _failed,
  );
  Size? _imageSize, _viewportSize;
  Offset? _lastFocalPoint;
  double _lastScale = 1;
  int _pointerCount = 0;
  bool _gesturing = false, _imageError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant PhotoCropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _crop = widget.initial;
      _lastFocalPoint = null;
      _gesturing = false;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final stream = boundedPhoto(
      widget.bytes,
      1200,
    ).resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stream?.removeListener(_listener);
    _imageSize = null;
    _imageError = false;
    _stream = stream;
    stream.addListener(_listener);
  }

  void _loaded(ImageInfo info, bool synchronousCall) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    info.dispose();
    if (mounted && _imageSize != size) {
      setState(() {
        _imageSize = size;
        _imageError = false;
      });
    }
  }

  void _failed(Object error, StackTrace? stack) {
    if (mounted) {
      setState(() {
        _imageSize = null;
        _imageError = true;
      });
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  PhotoCropGeometry? get _geometry {
    final image = _imageSize, viewport = _viewportSize;
    if (image == null || viewport == null || viewport.isEmpty) return null;
    return PhotoCropGeometry(
      width: viewport.width,
      height: viewport.height,
      imageWidth: image.width,
      imageHeight: image.height,
    );
  }

  void _scaleStart(ScaleStartDetails details) {
    if (_geometry == null) return;
    _lastFocalPoint = details.localFocalPoint;
    _lastScale = 1;
    _pointerCount = details.pointerCount;
    setState(() => _gesturing = true);
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    final geometry = _geometry, previous = _lastFocalPoint;
    if (geometry == null || previous == null) return;
    // Adding or lifting a finger moves the centroid without moving the image.
    // Re-anchor that transition so a one-finger drag can become a pinch safely.
    if (details.pointerCount != _pointerCount) {
      _pointerCount = details.pointerCount;
      _lastFocalPoint = details.localFocalPoint;
      _lastScale = details.scale;
      return;
    }
    if (!details.scale.isFinite || details.scale <= 0 || _lastScale <= 0) {
      return;
    }
    final focal = details.localFocalPoint;
    final next = geometry.transform(
      _crop,
      fromX: previous.dx,
      fromY: previous.dy,
      toX: focal.dx,
      toY: focal.dy,
      zoom: _crop.zoom * details.scale / _lastScale,
    );
    _lastFocalPoint = focal;
    _lastScale = details.scale;
    setState(() => _crop = next);
  }

  void _scaleEnd(ScaleEndDetails details) {
    _lastFocalPoint = null;
    if (_gesturing) setState(() => _gesturing = false);
  }

  void _zoom(double delta) {
    final geometry = _geometry;
    if (geometry == null) return;
    setState(
      () => _crop = geometry.transform(
        _crop,
        fromX: geometry.width / 2,
        fromY: geometry.height / 2,
        toX: geometry.width / 2,
        toY: geometry.height / 2,
        zoom: _crop.zoom + delta,
      ),
    );
  }

  void _move(Offset delta) {
    final geometry = _geometry;
    if (geometry == null) return;
    setState(
      () => _crop = geometry.transform(
        _crop,
        fromX: 0,
        fromY: 0,
        toX: delta.dx,
        toY: delta.dy,
        zoom: _crop.zoom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final ready = _imageSize != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  if (MediaQuery.sizeOf(context).width >= 400) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.crop, color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      'Ajustar encuadre',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar sin guardar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Arrastra la imagen para acomodarla. Usa dos dedos para acercar o alejar.',
                    ),
                    const SizedBox(height: 16),
                    AspectRatio(
                      aspectRatio: widget.aspectRatio,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _viewportSize = constraints.biggest;
                          return Semantics(
                            label: 'Área de encuadre de la fotografía',
                            value:
                                'Acercamiento ${(_crop.zoom * 100).round()} por ciento',
                            hint: 'Arrastra o usa las acciones para mover la imagen.',
                            customSemanticsActions: ready
                                ? {
                                    const CustomSemanticsAction(
                                      label: 'Mover imagen a la izquierda',
                                    ): () =>
                                        _move(const Offset(-24, 0)),
                                    const CustomSemanticsAction(
                                      label: 'Mover imagen a la derecha',
                                    ): () =>
                                        _move(const Offset(24, 0)),
                                    const CustomSemanticsAction(
                                      label: 'Mover imagen arriba',
                                    ): () =>
                                        _move(const Offset(0, -24)),
                                    const CustomSemanticsAction(
                                      label: 'Mover imagen abajo',
                                    ): () =>
                                        _move(const Offset(0, 24)),
                                  }
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: RawGestureDetector(
                                key: const ValueKey('photo-crop-viewport'),
                                behavior: HitTestBehavior.opaque,
                                gestures: {
                                  if (ready)
                                    _FrameScaleGestureRecognizer:
                                        GestureRecognizerFactoryWithHandlers<
                                          _FrameScaleGestureRecognizer
                                        >(
                                          _FrameScaleGestureRecognizer.new,
                                          (recognizer) => recognizer
                                            ..onStart = _scaleStart
                                            ..onUpdate = _scaleUpdate
                                            ..onEnd = _scaleEnd,
                                        ),
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(
                                      color: colors.surfaceContainerHighest,
                                    ),
                                    FramedPhoto(
                                      bytes: widget.bytes,
                                      crop: _crop,
                                    ),
                                    if (!ready && !_imageError)
                                      const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    IgnorePointer(
                                      child: CustomPaint(
                                        painter: _FrameGuide(
                                          visible: _gesturing,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Alejar fotografía',
                          onPressed: ready && _crop.zoom > 1
                              ? () => _zoom(-0.2)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 84,
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              '${(_crop.zoom * 100).round()}%',
                              key: const ValueKey('photo-crop-zoom'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Acercar fotografía',
                          onPressed: ready && _crop.zoom < 3
                              ? () => _zoom(0.2)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: ready
                          ? () => setState(() => _crop = const PhotoCrop())
                          : null,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Restablecer encuadre'),
                    ),
                    if (_imageError)
                      Text(
                        'No se pudo mostrar la fotografía. Cierra el editor y vuelve a abrirla.',
                        style: TextStyle(color: colors.error),
                      )
                    else
                      Text(
                        'El archivo original se conserva.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cancel = TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  );
                  final save = FilledButton.icon(
                    onPressed: ready
                        ? () => Navigator.pop(context, _crop)
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Guardar'),
                  );
                  if (constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [save, const SizedBox(height: 4), cancel],
                    );
                  }
                  return Row(
                    children: [
                      cancel,
                      const SizedBox(width: 12),
                      Expanded(child: save),
                    ],
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

/// A touch inside the frame belongs to the image. Otherwise the dialog's
/// vertical scroll can win the gesture arena before a one-finger pan starts.
/// Keep Flutter's pointer/scale lifecycle, accepting only after it has recorded
/// the initial focal point so changing the pointer count remains well-defined.
class _FrameScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent || event is PointerPanZoomStartEvent) {
      resolve(GestureDisposition.accepted);
    }
  }
}

class _FrameGuide extends CustomPainter {
  const _FrameGuide({required this.visible});
  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final paint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1;
    for (final fraction in [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(size.width * fraction, 0),
        Offset(size.width * fraction, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FrameGuide oldDelegate) => visible != oldDelegate.visible;
}
