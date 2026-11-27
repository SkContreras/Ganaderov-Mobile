import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ganaderov/features/livestock/domain/event_draft.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';
import 'package:ganaderov/features/livestock/presentation/pages/historical_event_editor.dart';
import 'package:ganaderov/features/settings/domain/animal_configuration.dart';
import 'package:ganaderov/features/settings/presentation/pages/animal_configuration_page.dart';

import 'completion_test_fixtures.dart';

class _HistoryWriter implements HistoricalEventWriter {
  @override
  bool get supportsHistoricalEvents => true;
  Map<String, dynamic>? fields;
  String? reason, operation;
  @override
  Future<void> updateHistoricalEvent(
    InventorySnapshot snapshot,
    String animalId,
    AnimalEvent event,
    Map<String, dynamic> changes,
    String reason, {
    String? operationId,
  }) async {
    fields = changes;
    this.reason = reason;
    operation = operationId;
  }

  @override
  Future<void> deleteHistoricalEvent(
    InventorySnapshot snapshot,
    String animalId,
    AnimalEvent event,
    String reason, {
    String? operationId,
  }) async {
    fields = {};
    this.reason = reason;
    operation = operationId;
  }
}

class _ConfigurationWriter
    implements InventoryRepository, RanchConfigurationWriter {
  _ConfigurationWriter({this.role = 'owner'});
  final String role;
  Map<String, dynamic>? captured;
  @override
  bool get supportsConfiguration => true;
  @override
  Future<InventorySnapshot> load() async =>
      completionSnapshot(offline: true, role: role);
  @override
  Future<void> saveConfiguration(
    InventorySnapshot snapshot,
    Map<String, dynamic> config, {
    String? operationId,
  }) async {
    captured = config;
  }
}

void main() {
  testWidgets(
    'historical editor requires a reason and submits only changed fields without changing type',
    (tester) async {
      final snapshot = completionSnapshot(offline: true),
          writer = _HistoryWriter();
      await tester.pumpWidget(
        MaterialApp(
          home: HistoricalEventEditor(
            snapshot: snapshot,
            animal: snapshot.animals.single,
            event: snapshot.animals.single.events.single,
            writer: writer,
          ),
        ),
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      final weight = find.widgetWithText(TextFormField, 'Peso (kg)');
      await tester.enterText(weight, '125');
      await tester.scrollUntilVisible(
        find.text('Guardar corrección'),
        400,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Guardar corrección'));
      await tester.pumpAndSettle();
      expect(writer.fields, isNull);
      expect(find.text('Indica el motivo'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo obligatorio'),
        'Báscula corregida',
      );
      await tester.scrollUntilVisible(
        find.text('Guardar corrección'),
        400,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Guardar corrección'));
      await tester.pumpAndSettle();
      expect(writer.fields, {'weight': 125.0});
      expect(writer.reason, 'Báscula corregida');
      expect(writer.operation, isNotEmpty);
    },
  );

  testWidgets(
    'configuration editor preserves locked operational fields and saves shared labels',
    (tester) async {
      final writer = _ConfigurationWriter();
      await tester.pumpWidget(
        MaterialApp(
          home: AnimalConfigurationPage(inventory: writer, writer: writer),
        ),
      );
      await tester.pumpAndSettle();
      final identification = find.widgetWithText(
        SwitchListTile,
        'Identificación básica',
      );
      expect(tester.widget<SwitchListTile>(identification).onChanged, isNull);
      final tag = find.byKey(const ValueKey('config-field-tag'));
      await tester.scrollUntilVisible(
        tag,
        300,
        maxScrolls: 20,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(tag);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre visible'),
        'Arete de prueba',
      );
      await tester.scrollUntilVisible(
        find.text('Guardar configuración'),
        400,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Guardar configuración'));
      await tester.pumpAndSettle();
      expect(writer.captured, isNotNull);
      expect(
        (writer.captured!['fields'] as Map)['tag']['label'],
        'Arete de prueba',
      );
      expect(
        (writer.captured!['fields'] as Map)['internalId']['form'],
        isFalse,
      );
      expect(writer.captured!['schemaVersion'], 1);
      expect(writer.captured!['configVersion'], 4);
    },
  );

  testWidgets('worker can inspect configuration but cannot save it', (
    tester,
  ) async {
    final writer = _ConfigurationWriter(role: 'worker');
    await tester.pumpWidget(
      MaterialApp(
        home: AnimalConfigurationPage(inventory: writer, writer: writer),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Guardar configuración'), findsNothing);
    expect(
      find.text(
        'Sólo el propietario o administrador puede modificar esta configuración.',
      ),
      findsOneWidget,
    );
    expect(writer.captured, isNull);
  });

  test(
    'configuration rejects disabling an option used by a confirmed animal',
    () {
      final snapshot = completionSnapshot();
      final config = editableAnimalConfiguration(snapshot.config);
      final statuses = (config['lists'] as Map)['status'] as List;
      (statuses.first as Map)['enabled'] = false;
      expect(
        () => validateAnimalConfiguration(config, snapshot),
        throwsStateError,
      );
      final valid = editableAnimalConfiguration(snapshot.config);
      (valid['fields'] as Map)['tag']['required'] = true;
      (valid['fields'] as Map)['tag']['form'] = false;
      expect(
        () => validateAnimalConfiguration(valid, snapshot),
        throwsStateError,
      );
    },
  );
}
