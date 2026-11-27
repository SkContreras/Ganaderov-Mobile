import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';
import 'package:ganaderov/features/livestock/presentation/pages/livestock_page.dart';
import 'package:material_ui/material_ui.dart';

import 'widget_test.dart' show FakeAuth;

const _notes =
    'No está herniado, nomás es el nombre. Esta observación continúa con '
    'más texto para comprobar que el resumen de la tarjeta no crezca sin '
    'límite y que la ficha conserve la nota completa.';
const _fieldLabels = {
  'birthDate': 'Fecha de nacimiento',
  'birthEstimated': 'Nacimiento estimado',
  'entryDate': 'Fecha de ingreso al rancho',
  'originType': 'Procedencia',
  'generalNotes': 'Observaciones generales',
};

class _InventoryWithExtraFields implements InventoryRepository {
  @override
  Future<InventorySnapshot> load() async => InventorySnapshot(
    status: 'active',
    config: {
      'fields': {
        for (final entry in _fieldLabels.entries)
          entry.key: {'label': entry.value, 'detailVisibility': 'summary'},
        'lot': {'detailVisibility': 'hidden'},
      },
    },
    records: [
      for (final (id, name, status, estimated) in [
        ('1', 'Herniado', 'Activo', true),
        ('2', 'Lucero', 'Vendido', false),
      ])
        {
          'animal_id': id,
          'payload': {
            'animal': {
              'id': id,
              'tag': '657$id',
              'name': name,
              'sex': 'Macho',
              'status': status,
              'birthDate': '2023-03-01',
              'birthEstimated': estimated,
              'entryDate': '2026-11-27',
              'originType': 'Nacimiento propio',
              'generalNotes': _notes,
              'lot': 'No se muestra',
            },
            'events': [
              {
                'animalId': id,
                'type': 'weight',
                'weight': 210,
                'date': '2026-11-27',
              },
            ],
          },
        },
    ],
  );
}

void main() {
  for (final (width, textScale) in [(390.0, 1.0), (320.0, 1.4)]) {
    testWidgets('inventory keeps summary fields readable at ${width}px', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final auth = FakeAuth()..active = true;
      final ranchChanges = ValueNotifier(0);
      addTearDown(auth.dispose);
      addTearDown(ranchChanges.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LivestockPage(
              repository: _InventoryWithExtraFields(),
              auth: auth,
              ranchChanges: ranchChanges,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.widgetWithText(Card, 'Herniado');
      for (final text in [
        'Fecha de nacimiento: 2023-03-01',
        'Nacimiento estimado: Sí',
        'Fecha de ingreso al rancho: 2026-11-27',
        'Procedencia: Nacimiento propio',
        'Observaciones generales: $_notes',
        '210 kg',
        '27/11/2026',
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(find.textContaining(' · '), findsNothing);
      expect(find.textContaining('No se muestra'), findsNothing);
      final preview = find.text('Observaciones generales: $_notes');
      expect(tester.widget<Text>(preview).maxLines, 2);
      expect(
        tester.getRect(card).contains(tester.getRect(preview).center),
        isTrue,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Herniado'));
      await tester.pumpAndSettle();
      final note = find.text(_notes);
      await tester.scrollUntilVisible(note, 180);
      expect(tester.widget<Text>(note).maxLines, isNull);
      expect(tester.takeException(), isNull);

      final back = find.text('Volver al inventario');
      await tester.scrollUntilVisible(back, -180);
      await tester.tap(back);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archivo (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Lucero'), findsOneWidget);
      expect(find.text('Nacimiento estimado: No'), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
