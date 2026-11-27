import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../domain/animal_photos.dart';

// Bound both axes without changing the original bytes or their aspect ratio.
ImageProvider boundedPhoto(Uint8List bytes, int size) => ResizeImage(
  MemoryImage(bytes),
  width: size,
  height: size,
  policy: ResizeImagePolicy.fit,
);

class FramedPhoto extends StatelessWidget {
  const FramedPhoto({
    super.key,
    required this.bytes,
    required this.crop,
    this.cacheWidth = 1200,
  });
  final Uint8List bytes;
  final PhotoCrop crop;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final alignment = Alignment(crop.x / 50 - 1, crop.y / 50 - 1);
    return ClipRect(
      child: Transform.scale(
        scale: crop.zoom,
        alignment: alignment,
        child: SizedBox.expand(
          child: Image(
            image: boundedPhoto(bytes, cacheWidth),
            fit: BoxFit.cover,
            alignment: alignment,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }
}
