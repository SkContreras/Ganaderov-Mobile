import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ganaderov/features/auth/domain/auth_gateway.dart';
import 'package:ganaderov/features/livestock/domain/animal_photos.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';
import 'package:ganaderov/features/livestock/presentation/pages/livestock_page.dart';
import 'package:ganaderov/features/livestock/presentation/widgets/animal_gallery.dart';
import 'package:ganaderov/features/livestock/presentation/widgets/framed_photo.dart';
import 'package:ganaderov/features/livestock/presentation/widgets/photo_crop_editor.dart';

import 'photo_test_fixtures.dart';

class PhotoGalleryRepository
    implements
        InventoryRepository,
        AnimalPhotos,
        AnimalPhotoFraming,
        AnimalPhotoRemoval,
        OfflineAnimalPhotos {
  final original = photoSnapshot(offline: true);
  final operations = <Map<String, dynamic>>[];
  InventorySnapshot? savedSnapshot;
  int loads = 0;
  @override
  bool get supportsOfflinePhotoChanges => true;
  @override
  Future<InventorySnapshot> load() async {
    loads++;
    return refreshPhotoChanges(original);
  }

  @override
  Future<InventorySnapshot> refreshPhotoChanges(
    InventorySnapshot snapshot,
  ) async => projectPhotoChanges(original, operations);
  @override
  Future<Uint8List> readPhoto(
    InventorySnapshot snapshot,
    String animalId,
    AnimalPhoto photo,
  ) async => photoPng();
  @override
  Future<void> addPhoto(
    InventorySnapshot snapshot,
    String animalId,
    Uint8List bytes,
    String name,
  ) async => throw StateError('Online only');
  @override
  Future<void> savePhotoCrop(
    InventorySnapshot snapshot,
    String animalId,
    String photoId,
    PhotoCrop crop,
  ) async {
    savedSnapshot = snapshot;
    operations.add({
      'state': 'pending',
      'operation': {
        ...photoOperation(photoId: photoId),
        'changes': crop.changes(animalId),
      },
    });
  }

  @override
  Future<void> primaryPhoto(
    InventorySnapshot snapshot,
    String animalId,
    String photoId,
  ) async {
    operations.add({
      'state': 'pending',
      'operation': photoOperation(action: 'photo.primary', photoId: photoId),
    });
  }

  @override
  Future<void> removePhoto(
    InventorySnapshot snapshot,
    String animalId,
    String photoId,
  ) async {
    operations.add({
      'state': 'pending',
      'operation': photoOperation(action: 'photo.delete', photoId: photoId),
    });
  }
}

class PhotoAuth extends AuthGateway {
  @override
  bool get signedIn => true;
  @override
  bool get recovering => false;
  @override
  String? get email => 'test@example.com';
  @override
  String? get notice => null;
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<bool> register(String email, String password) async => false;
  @override
  Future<void> recover(String email) async {}
  @override
  Future<void> reset(String password) async {}
  @override
  Future<void> social(bool google) async {}
  @override
  Future<void> logout() async {}
}

void main() {
  Future<PhotoGalleryRepository> page(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = PhotoGalleryRepository();
    final auth = PhotoAuth(), ranchChanges = ChangeNotifier();
    addTearDown(auth.dispose);
    addTearDown(ranchChanges.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LivestockPage(
            repository: repository,
            auth: auth,
            ranchChanges: ranchChanges,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luna'));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openCrop(
    WidgetTester tester, {
    VoidCallback? beforeSelection,
  }) async {
    final heroSize = tester.getSize(
      find.byKey(const ValueKey('hero-$firstPhoto')),
    );
    await tester.tap(find.text('Editar encuadre'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('select-photo-$firstPhoto')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('select-photo-$secondPhoto')),
      findsOneWidget,
    );
    expect(find.text('Foto principal'), findsOneWidget);
    beforeSelection?.call();
    await tester.pump();
    await tester.tap(find.text('Original uno'));
    // The gallery intentionally remains busy while its crop dialog is open.
    await tester.pump();
    final editor = tester.widget<PhotoCropEditor>(find.byType(PhotoCropEditor));
    await tester.runAsync(
      () => precacheImage(
        boundedPhoto(editor.bytes, 1200),
        tester.element(find.byType(PhotoCropEditor)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    final frameSize = tester.getSize(
      find.byKey(const ValueKey('photo-crop-viewport')),
    );
    expect(frameSize.aspectRatio, closeTo(heroSize.aspectRatio, 0.000001));
  }

  for (final refreshDuringSelection in [false, true]) {
    testWidgets(
      'a gallery refresh keeps the original snapshot for the repository guard (during selection: $refreshDuringSelection)',
      (tester) async {
        tester.view.physicalSize = const Size(430, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = PhotoGalleryRepository();
        final opened = repository.original;
        final current = ValueNotifier(opened);
        addTearDown(current.dispose);
        final refreshed = photoSnapshot(offline: true);
        final photos =
            (refreshed.records.single['payload'] as Map)['photos'] as List;
        (photos.first as Map)['cropX'] = 90;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ValueListenableBuilder<InventorySnapshot>(
                  valueListenable: current,
                  builder: (context, snapshot, _) => AnimalGallery(
                    snapshot: snapshot,
                    animal: snapshot.animals.single,
                    repository: repository,
                    onChanged: () async {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openCrop(
          tester,
          beforeSelection: refreshDuringSelection
              ? () => current.value = refreshed
              : null,
        );
        await tester.tap(find.byTooltip('Acercar fotografía'));
        await tester.pump();
        if (!refreshDuringSelection) current.value = refreshed;
        await tester.pump();
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(repository.savedSnapshot, same(opened));
        expect(
          AnimalPhoto.fromSnapshot(repository.savedSnapshot!, 'a').first.crop.x,
          50,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'offline detail keeps gallery; gestures preview until explicit save and local callback avoids reload',
    (tester) async {
      final repository = await page(tester);
      expect(find.byType(AnimalGallery), findsOneWidget);
      expect(find.text('Editar encuadre'), findsOneWidget);
      expect(find.text('Cámara'), findsNothing);
      await openCrop(tester);
      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.byTooltip('Acercar fotografía'));
      await tester.pump();
      await tester.tap(find.byTooltip('Acercar fotografía'));
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('photo-crop-viewport')),
        const Offset(-40, 24),
      );
      await tester.pump();
      expect(repository.operations, isEmpty);
      final preview = tester
          .widget<FramedPhoto>(
            find.descendant(
              of: find.byType(PhotoCropEditor),
              matching: find.byType(FramedPhoto),
            ),
          )
          .crop;
      expect(preview.zoom, closeTo(1.4, 0.000001));
      expect(preview.x, greaterThan(50));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(repository.operations, hasLength(1));
      expect(repository.loads, 1);
      final gallery = tester.widget<AnimalGallery>(find.byType(AnimalGallery));
      expect(
        AnimalPhoto.fromSnapshot(gallery.snapshot, 'a').first.crop.x,
        preview.x,
      );
      expect(
        (repository.operations.single['operation'] as Map)['changes'],
        preview.changes('a'),
      );
      expect(find.byKey(const ValueKey('photo-sync-state')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Editar encuadre'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Quitar fotografía'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel does not enqueue; thumbnail and full original use bounded aspect-preserving decode',
    (tester) async {
      final repository = await page(tester);
      await openCrop(tester);
      await tester.tap(find.byTooltip('Acercar fotografía'));
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('photo-crop-viewport')),
        const Offset(30, -20),
      );
      await tester.pump();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repository.operations, isEmpty);
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images, isNotEmpty);
      for (final image in images) {
        final provider = image.image as ResizeImage;
        expect(provider.policy, ResizeImagePolicy.fit);
        expect(provider.width, lessThanOrEqualTo(1200));
        expect(provider.height, lessThanOrEqualTo(1200));
      }
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();
      final full = tester.widget<Image>(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(Image),
        ),
      );
      expect((full.image as ResizeImage).width, 2048);
      expect((full.image as ResizeImage).height, 2048);
      expect((full.image as ResizeImage).policy, ResizeImagePolicy.fit);
      expect(tester.takeException(), isNull);
    },
  );
}
