import 'dart:math' as math;

import 'animal_photos.dart';

/// The existing cover + alignment + transform-origin presentation, in pixels.
/// The stored coordinates remain percentages, independent of viewport size.
class PhotoCropGeometry {
  PhotoCropGeometry({
    required this.width,
    required this.height,
    required this.imageWidth,
    required this.imageHeight,
  }) {
    if ([
      width,
      height,
      imageWidth,
      imageHeight,
    ].any((value) => !value.isFinite || value <= 0)) {
      throw ArgumentError(
        'El área y la imagen deben tener dimensiones válidas',
      );
    }
  }

  final double width, height, imageWidth, imageHeight;

  double get coverScale => math.max(width / imageWidth, height / imageHeight);
  double renderedWidth(double zoom) => imageWidth * coverScale * zoom;
  double renderedHeight(double zoom) => imageHeight * coverScale * zoom;
  double left(PhotoCrop crop) =>
      (width - renderedWidth(crop.zoom)) * crop.x / 100;
  double top(PhotoCrop crop) =>
      (height - renderedHeight(crop.zoom)) * crop.y / 100;

  /// Move the image point under the previous focal point to the new focal point.
  /// Clamp the resulting image bounds so the frame never exposes empty space.
  PhotoCrop transform(
    PhotoCrop crop, {
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    required double zoom,
  }) {
    if (!crop.valid ||
        [fromX, fromY, toX, toY, zoom].any((value) => !value.isFinite)) {
      throw ArgumentError('El gesto de encuadre no es válido');
    }
    final nextZoom = zoom.clamp(1.0, 3.0).toDouble();
    final ratio = nextZoom / crop.zoom;
    final nextLeft = toX - (fromX - left(crop)) * ratio;
    final nextTop = toY - (fromY - top(crop)) * ratio;
    double position(
      double offset,
      double extent,
      double viewport,
      double fallback,
    ) {
      final overflow = extent - viewport;
      // A fitting axis cannot move. Keep its existing stored position; its
      // visual offset is zero and a future zoom computes the new focal anchor.
      return overflow <= 0.000001
          ? fallback
          : (-offset / overflow * 100).clamp(0.0, 100.0).toDouble();
    }

    return PhotoCrop(
      x: position(nextLeft, renderedWidth(nextZoom), width, crop.x),
      y: position(nextTop, renderedHeight(nextZoom), height, crop.y),
      zoom: nextZoom,
    );
  }
}
