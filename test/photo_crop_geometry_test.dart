import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/livestock/domain/animal_photos.dart';
import 'package:ganaderov/features/livestock/domain/photo_crop_geometry.dart';

void main() {
  test(
    'drag moves rendered pixels with the finger in the existing cover geometry',
    () {
      final frame = PhotoCropGeometry(
        width: 300,
        height: 200,
        imageWidth: 900,
        imageHeight: 400,
      );
      const before = PhotoCrop(zoom: 2);
      final after = frame.transform(
        before,
        fromX: 100,
        fromY: 80,
        toX: 145,
        toY: 50,
        zoom: 2,
      );
      expect(frame.renderedWidth(2), 900);
      expect(frame.renderedHeight(2), 400);
      expect(frame.left(after) - frame.left(before), closeTo(45, 0.000001));
      expect(frame.top(after) - frame.top(before), closeTo(-30, 0.000001));
      expect(after.x, closeTo(42.5, 0.000001));
      expect(after.y, closeTo(65, 0.000001));
    },
  );

  test(
    'off-center pinch preserves the image point beneath the moving focal point',
    () {
      final frame = PhotoCropGeometry(
        width: 320,
        height: 240,
        imageWidth: 800,
        imageHeight: 600,
      );
      const before = PhotoCrop(zoom: 1.5);
      final u = (120 - frame.left(before)) / frame.renderedWidth(before.zoom);
      final v = (90 - frame.top(before)) / frame.renderedHeight(before.zoom);
      final after = frame.transform(
        before,
        fromX: 120,
        fromY: 90,
        toX: 134,
        toY: 102,
        zoom: 2.4,
      );
      expect(
        frame.left(after) + u * frame.renderedWidth(after.zoom),
        closeTo(134, 0.000001),
      );
      expect(
        frame.top(after) + v * frame.renderedHeight(after.zoom),
        closeTo(102, 0.000001),
      );
    },
  );

  test('a fitting axis stays covered and preserves its legacy coordinate', () {
    final frame = PhotoCropGeometry(
      width: 320,
      height: 240,
      imageWidth: 100,
      imageHeight: 400,
    );
    const before = PhotoCrop(x: 17, y: 50);
    final after = frame.transform(
      before,
      fromX: 0,
      fromY: 0,
      toX: 200,
      toY: 52,
      zoom: 1,
    );
    expect(after.x, 17);
    expect(frame.left(after), 0);
    expect(frame.top(after) - frame.top(before), closeTo(52, 0.000001));
    final zoomed = frame.transform(
      after,
      fromX: 160,
      fromY: 120,
      toX: 160,
      toY: 120,
      zoom: 2,
    );
    expect(zoomed.x, closeTo(50, 0.000001));
  });

  test('portrait, landscape and square frames clamp gestures and zoom without blank edges', () {
    for (final image in [(100.0, 900.0), (900.0, 100.0), (400.0, 400.0)]) {
      final frame = PhotoCropGeometry(
        width: 320,
        height: 240,
        imageWidth: image.$1,
        imageHeight: image.$2,
      );
      for (final delta in [-100000.0, 100000.0]) {
        for (final zoom in [-5.0, 1.0, 2.0, 30.0]) {
          final crop = frame.transform(
            const PhotoCrop(x: 93, y: 12, zoom: 1.7),
            fromX: 40,
            fromY: 120,
            toX: delta,
            toY: -delta,
            zoom: zoom,
          );
          expect(crop.valid, isTrue);
          expect(frame.left(crop), lessThanOrEqualTo(0.000001));
          expect(frame.top(crop), lessThanOrEqualTo(0.000001));
          expect(
            frame.left(crop) + frame.renderedWidth(crop.zoom),
            greaterThanOrEqualTo(frame.width - 0.000001),
          );
          expect(
            frame.top(crop) + frame.renderedHeight(crop.zoom),
            greaterThanOrEqualTo(frame.height - 0.000001),
          );
        }
      }
    }
  });

  test('stored percentages remain independent of display size and idle gestures are lossless', () {
    final small = PhotoCropGeometry(
      width: 300,
      height: 200,
      imageWidth: 900,
      imageHeight: 1200,
    );
    final large = PhotoCropGeometry(
      width: 600,
      height: 400,
      imageWidth: 900,
      imageHeight: 1200,
    );
    const crop = PhotoCrop(x: 82, y: 24, zoom: 2.4);
    expect(large.left(crop), closeTo(small.left(crop) * 2, 0.000001));
    expect(large.top(crop), closeTo(small.top(crop) * 2, 0.000001));
    final idle = small.transform(
      crop,
      fromX: 43,
      fromY: 71,
      toX: 43,
      toY: 71,
      zoom: crop.zoom,
    );
    expect(idle.x, closeTo(crop.x, 0.000001));
    expect(idle.y, closeTo(crop.y, 0.000001));
    expect(idle.zoom, crop.zoom);
    expect(idle.changes('a').keys, ['animalId', 'cropX', 'cropY', 'cropZoom']);
  });

  test('invalid dimensions and nonfinite gesture coordinates are rejected', () {
    expect(
      () => PhotoCropGeometry(
        width: 0,
        height: 200,
        imageWidth: 10,
        imageHeight: 10,
      ),
      throwsArgumentError,
    );
    final frame = PhotoCropGeometry(
      width: 300,
      height: 200,
      imageWidth: 100,
      imageHeight: 100,
    );
    expect(
      () => frame.transform(
        const PhotoCrop(),
        fromX: double.nan,
        fromY: 0,
        toX: 0,
        toY: 0,
        zoom: 1,
      ),
      throwsArgumentError,
    );
  });

  test('matching the measured hero ratio preserves every visible source edge in the editor', () {
    for (final heroWidth in [288.0, 398.0, 968.0]) {
      for (final image in [(900.0, 600.0), (400.0, 1200.0)]) {
        final hero = PhotoCropGeometry(
          width: heroWidth,
          height: 190,
          imageWidth: image.$1,
          imageHeight: image.$2,
        );
        final editor = PhotoCropGeometry(
          width: 248,
          height: 248 / (heroWidth / 190),
          imageWidth: image.$1,
          imageHeight: image.$2,
        );
        for (final crop in [
          const PhotoCrop(),
          const PhotoCrop(x: 82, y: 24, zoom: 2.4),
        ]) {
          List<double> sourceEdges(PhotoCropGeometry frame) => [
            -frame.left(crop) / frame.renderedWidth(crop.zoom),
            -frame.top(crop) / frame.renderedHeight(crop.zoom),
            (frame.width - frame.left(crop)) / frame.renderedWidth(crop.zoom),
            (frame.height - frame.top(crop)) / frame.renderedHeight(crop.zoom),
          ];
          final expected = sourceEdges(hero), actual = sourceEdges(editor);
          for (var edge = 0; edge < 4; edge++) {
            expect(actual[edge], closeTo(expected[edge], 0.000001));
          }
        }
      }
    }
  });
}
