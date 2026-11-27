import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ganaderov/features/livestock/domain/animal_photos.dart';
import 'package:ganaderov/features/livestock/presentation/widgets/framed_photo.dart';
import 'package:ganaderov/features/livestock/presentation/widgets/photo_crop_editor.dart';

import 'photo_test_fixtures.dart';

void main() {
  Future<void> openEditor(
    WidgetTester tester, {
    PhotoCrop initial = const PhotoCrop(),
    Size size = const Size(430, 850),
    double textScale = 1,
    void Function(PhotoCrop?)? onResult,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = photoPng();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await showDialog<PhotoCrop>(
                    context: context,
                    builder: (_) =>
                        PhotoCropEditor(bytes: bytes, initial: initial),
                  );
                  onResult?.call(result);
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pump();
    await tester.runAsync(
      () => precacheImage(
        boundedPhoto(bytes, 1200),
        tester.element(find.byType(PhotoCropEditor)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PhotoCropEditor), findsOneWidget);
  }

  PhotoCrop preview(WidgetTester tester) =>
      tester.widget<FramedPhoto>(find.byType(FramedPhoto)).crop;

  testWidgets(
    'real two-pointer pinch zooms and changing to one finger does not jump',
    (tester) async {
      await openEditor(tester);
      expect(find.byType(Slider), findsNothing);
      final center = tester.getCenter(
        find.byKey(const ValueKey('photo-crop-viewport')),
      );
      final first = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(60, 0));
      await second.moveTo(center + const Offset(60, 0));
      await tester.pump();
      await first.moveTo(center - const Offset(80, 0));
      await second.moveTo(center + const Offset(80, 0));
      await tester.pump();
      final pinched = preview(tester);
      expect(pinched.zoom, greaterThan(1.4));
      expect(pinched.valid, isTrue);
      await second.up();
      await tester.pump();
      final lifted = preview(tester);
      expect(lifted.zoom, pinched.zoom);
      expect(lifted.x, pinched.x);
      expect(lifted.y, pinched.y);
      // The remaining pointer continues as a drag, without a synthetic zoom.
      await first.moveBy(const Offset(12, 0));
      await tester.pump();
      await first.moveBy(const Offset(18, 0));
      await tester.pump();
      expect(preview(tester).zoom, closeTo(pinched.zoom, 0.000001));
      expect(preview(tester).x, lessThan(pinched.x));
      await first.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accessible zoom buttons respect limits and reset restores centered original',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        PhotoCrop? saved;
        await openEditor(
          tester,
          initial: const PhotoCrop(x: 80, y: 20, zoom: 2),
          onResult: (crop) => saved = crop,
        );
        expect(find.byTooltip('Alejar fotografía'), findsOneWidget);
        expect(find.byTooltip('Acercar fotografía'), findsOneWidget);
        for (var index = 0; index < 7; index++) {
          await tester.tap(find.byTooltip('Acercar fotografía'));
          await tester.pump();
        }
        expect(preview(tester).zoom, 3);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Acercar fotografía',
                ),
              )
              .onPressed,
          isNull,
        );
        final area = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Área de encuadre de la fotografía',
          ),
        );
        expect(area.properties.customSemanticsActions, hasLength(4));
        area.properties.customSemanticsActions!.entries
            .singleWhere(
              (entry) => entry.key.label == 'Mover imagen a la izquierda',
            )
            .value();
        await tester.pump();
        expect(preview(tester).valid, isTrue);
        await tester.tap(find.text('Restablecer encuadre'));
        await tester.pump();
        expect(preview(tester).x, 50);
        expect(preview(tester).y, 50);
        expect(preview(tester).zoom, 1);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Alejar fotografía',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(saved, isNull);
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(saved!.changes('a'), const PhotoCrop().changes('a'));
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'small screen and enlarged text stay usable and close discards every gesture',
    (tester) async {
      var closed = false;
      PhotoCrop? saved;
      await openEditor(
        tester,
        size: const Size(320, 568),
        textScale: 1.4,
        initial: const PhotoCrop(zoom: 1.8),
        onResult: (crop) {
          closed = true;
          saved = crop;
        },
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('photo-crop-viewport')),
      );
      await tester.pumpAndSettle();
      final scroller = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      final scrollOffset = scroller.position.pixels;
      final initialY = preview(tester).y;
      final vertical = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('photo-crop-viewport'))),
      );
      for (var step = 0; step < 4; step++) {
        await vertical.moveBy(const Offset(0, -8));
        await tester.pump();
      }
      await vertical.up();
      await tester.pump();
      expect(preview(tester).y, greaterThan(initialY));
      expect(scroller.position.pixels, scrollOffset);
      await tester.drag(
        find.byKey(const ValueKey('photo-crop-viewport')),
        const Offset(-45, 20),
      );
      await tester.pump();
      expect(preview(tester).x, greaterThan(50));
      await tester.tap(find.byTooltip('Cerrar sin guardar'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(saved, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
