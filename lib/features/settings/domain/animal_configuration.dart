import 'dart:convert';

import '../../livestock/domain/animal_form_config.dart';
import '../../livestock/domain/inventory.dart';

abstract interface class RanchConfigurationWriter {
  bool get supportsConfiguration;
  Future<void> saveConfiguration(
    InventorySnapshot snapshot,
    Map<String, dynamic> config, {
    String? operationId,
  });
}

const configurationModules = {
  'identification': 'Identificación básica',
  'dates': 'Fechas y procedencia',
  'location': 'Ubicación y estado',
  'tracking': 'Documentación y seguimiento',
};
const configurationLists = {
  'breed': 'Razas',
  'lot': 'Lotes',
  'paddock': 'Potreros',
  'pen': 'Corrales',
  'status': 'Estados',
};
const automaticConfigurationFields = [
  AnimalField(
    'internalId',
    'ID interno',
    'identification',
    kind: 'automatic',
    introduced: 4,
  ),
  AnimalField(
    'createdAt',
    'Fecha de creación',
    'tracking',
    kind: 'automatic',
    introduced: 4,
  ),
  AnimalField(
    'createdBy',
    'Usuario creador',
    'tracking',
    kind: 'automatic',
    introduced: 4,
  ),
  AnimalField(
    'updatedAt',
    'Última modificación',
    'tracking',
    kind: 'automatic',
    introduced: 4,
  ),
  AnimalField(
    'updatedBy',
    'Usuario que modificó',
    'tracking',
    kind: 'automatic',
    introduced: 4,
  ),
];
const configurationFields = [...animalFields, ...automaticConfigurationFields];
const defaultStatusLabels = {
  'Activo': 'Activo',
  'Vendido': 'Vendido',
  'Fallecido': 'Muerto',
  'Desaparecido': 'Extraviado',
  'Otro': 'Otro',
  'Baja': 'Baja (legado)',
  'Otros': 'Otro (legado)',
};

Map<String, dynamic> editableAnimalConfiguration(Map<String, dynamic> raw) {
  final copy = Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)) as Map),
      current = AnimalFormConfig(raw);
  final providedModules = copy['modules'] is Map
      ? copy['modules'] as Map
      : const {};
  final modules = {
    for (final id in configurationModules.keys)
      id:
          id == 'identification' ||
          (providedModules[id] is bool
              ? providedModules[id] as bool
              : current.version >= 4),
  };
  final providedFields = copy['fields'] is Map
      ? copy['fields'] as Map
      : const {};
  final fields = Map<String, dynamic>.from(providedFields);
  for (final field in configurationFields) {
    final prior = providedFields[field.id] is Map
        ? Map<String, dynamic>.from(providedFields[field.id] as Map)
        : <String, dynamic>{};
    final automatic = field.kind == 'automatic',
        locked = automatic || field.id == 'status';
    final enabled =
        locked ||
        (prior.isNotEmpty
            ? prior['enabled'] != false
            : field.introduced <= current.version);
    final required =
        !automatic &&
        (prior.isNotEmpty
            ? prior['required'] == true
            : ['tag', 'sex'].contains(field.id));
    final detail = prior['detailVisibility'];
    fields[field.id] = {
      ...prior,
      'enabled': enabled,
      'form': !automatic && enabled && (required || prior['form'] != false),
      'formLevel':
          prior['formLevel'] == 'basic' ||
              prior.isEmpty &&
                  ['tag', 'name', 'sex', 'breed'].contains(field.id)
          ? 'basic'
          : 'advanced',
      'detailVisibility': ['hidden', 'full', 'summary'].contains(detail)
          ? detail
          : prior['detail'] == false
          ? 'hidden'
          : ['tag', 'name', 'sex', 'breed', 'status'].contains(field.id)
          ? 'summary'
          : 'full',
      'table': !automatic && prior['table'] != false,
      'required': enabled && required,
      'label':
          prior['label'] is String &&
              (prior['label'] as String).trim().isNotEmpty
          ? prior['label']
          : field.label,
    };
  }
  final lists = copy['lists'] is Map
      ? Map<String, dynamic>.from(copy['lists'] as Map)
      : <String, dynamic>{};
  for (final id in configurationLists.keys) {
    lists.putIfAbsent(
      id,
      () => id == 'status'
          ? [
              for (final status in defaultStatusLabels.entries)
                {
                  'value': status.key,
                  'label': status.value,
                  'enabled': true,
                  'active': status.key == 'Activo',
                },
            ]
          : <Map<String, dynamic>>[],
    );
  }
  if ((lists['status'] as List).isEmpty) {
    lists['status'] = [
      for (final status in defaultStatusLabels.entries)
        {
          'value': status.key,
          'label': status.value,
          'enabled': true,
          'active': status.key == 'Activo',
        },
    ];
  }
  return {
    ...copy,
    'schemaVersion': 1,
    'configVersion': 4,
    'modules': modules,
    'fields': fields,
    'lists': lists,
    'layout': copy['layout'] is Map ? copy['layout'] : <String, dynamic>{},
  };
}

void validateAnimalConfiguration(
  Map<String, dynamic> config,
  InventorySnapshot snapshot,
) {
  if (config['schemaVersion'] != 1 ||
      config['configVersion'] != 4 ||
      config['modules'] is! Map ||
      config['fields'] is! Map ||
      config['lists'] is! Map ||
      config['layout'] is! Map) {
    throw StateError('Configuración inválida');
  }
  final modules = config['modules'] as Map,
      fields = config['fields'] as Map,
      lists = config['lists'] as Map;
  if (modules['identification'] != true ||
      configurationModules.keys.any((id) => modules[id] is! bool)) {
    throw StateError('La identificación básica debe permanecer activa');
  }
  for (final field in configurationFields) {
    final setting = fields[field.id];
    if (setting is! Map ||
        setting['label'] is! String ||
        (setting['label'] as String).trim().isEmpty ||
        (setting['label'] as String).length > 80 ||
        [
          'enabled',
          'form',
          'table',
          'required',
        ].any((key) => setting[key] is! bool) ||
        !['basic', 'advanced'].contains(setting['formLevel']) ||
        !['hidden', 'full', 'summary'].contains(setting['detailVisibility'])) {
      throw StateError('Configuración inválida para ${field.label}');
    }
    if ((field.kind == 'automatic' || field.id == 'status') &&
        setting['enabled'] != true) {
      throw StateError('${field.label} debe permanecer activo');
    }
    if (field.kind == 'automatic' &&
        (setting['form'] == true ||
            setting['required'] == true ||
            setting['table'] == true)) {
      throw StateError('Los campos automáticos no se capturan manualmente');
    }
    if (setting['required'] == true &&
        (setting['enabled'] != true || setting['form'] != true)) {
      throw StateError('Un campo obligatorio debe estar activo y visible');
    }
  }
  for (final id in configurationLists.keys) {
    final entries = lists[id];
    if (entries is! List) throw StateError('Lista inválida: $id');
    final seen = <String>{};
    for (final option in entries) {
      if (option is! Map ||
          option['value'] is! String ||
          option['label'] is! String ||
          (option['value'] as String).trim().isEmpty ||
          (option['label'] as String).trim().isEmpty ||
          (option['value'] as String).length > 80 ||
          (option['label'] as String).length > 80 ||
          !seen.add(option['value'] as String) ||
          option['enabled'] is! bool ||
          (id == 'status' && option['active'] is! bool)) {
        throw StateError(
          'Revisa los valores y etiquetas de ${configurationLists[id]}',
        );
      }
      if (id == 'status' &&
          defaultStatusLabels.containsKey(option['value']) &&
          option['active'] != (option['value'] == 'Activo')) {
        throw StateError(
          'No cambies la clasificación de los estados predeterminados',
        );
      }
    }
    final prior = snapshot.config['lists'] is Map
        ? (snapshot.config['lists'] as Map)[id]
        : null;
    final inUse = snapshot.animals
        .map((a) => a.value(id))
        .where((v) => v.isNotEmpty)
        .toSet();
    if (prior is List) {
      for (final old in prior.whereType<Map>()) {
        if (inUse.contains(old['value']) &&
            !entries.whereType<Map>().any(
              (e) => e['value'] == old['value'] && e['enabled'] == true,
            )) {
          throw StateError(
            'No se puede eliminar o desactivar una opción en uso',
          );
        }
      }
    }
    if (id == 'status' &&
        !entries.whereType<Map>().any(
          (e) => e['enabled'] == true && e['active'] == true,
        )) {
      throw StateError('Conserva al menos un estado activo para el inventario');
    }
  }
}
