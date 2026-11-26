class DashboardActivity {
  const DashboardActivity({required this.animal, required this.type, required this.date});
  final String animal, type;
  final DateTime date;
}

class DashboardSummary {
  const DashboardSummary({
    required this.status,
    this.ranchName = '',
    this.role = '',
    this.total = 0,
    this.females = 0,
    this.males = 0,
    this.weighed = 0,
    this.activity = const [],
    this.offline = false,
    this.cachedAt,
  });
  final String status, ranchName, role;
  final bool offline;
  final DateTime? cachedAt;
  final int total, females, males, weighed;
  final List<DashboardActivity> activity;

  factory DashboardSummary.fromRecords({
    required String ranchName,
    required String role,
    required Iterable<Map<String, dynamic>> records,
    Map<String, bool> statusOptions = const {},
    bool offline = false, DateTime? cachedAt,
  }) {
    const inactive = {'Vendido', 'Fallecido', 'Baja', 'Otro', 'Otros', 'Desaparecido'};
    final animals = <String, Map<String, dynamic>>{};
    final events = <Map<String, dynamic>>[];
    for (final row in records) {
      if (row['deleted_at'] != null) continue;
      final payload = row['payload'];
      if (payload is! Map || payload['animal'] is! Map) {
        throw const FormatException('Registro de animal inválido');
      }
      final animal = Map<String, dynamic>.from(payload['animal'] as Map);
      final id = row['animal_id'];
      if (id is! String || id.isEmpty || animal['id'] != id) {
        throw const FormatException('Identificador de animal inválido');
      }
      animals[id] = animal;
      final history = payload['events'];
      if (history is List) {
        events.addAll(history.whereType<Map>().map((event) => Map<String, dynamic>.from(event)));
      }
    }
    final active = animals.entries.where((entry) {
      final status = entry.value['status'];
      return statusOptions[status] ?? !inactive.contains(status);
    }).toList();
    final activeIds = active.map((entry) => entry.key).toSet();
    final weighedIds = <String>{};
    final recent = <DashboardActivity>[];
    final seen = <String>{};
    for (final event in events) {
      final animalId = event['animalId'];
      if (animalId is! String || !activeIds.contains(animalId)) continue;
      final type = event['type'];
      if (type is! String) continue;
      if (type == 'weight') weighedIds.add(animalId);
      final eventId = event['id'];
      if (eventId is String && !seen.add(eventId)) continue;
      final date = DateTime.tryParse(event['performedAt']?.toString() ?? '') ??
          DateTime.tryParse(event['date']?.toString() ?? '');
      if (date == null) continue;
      final animal = animals[animalId]!;
      final name = animal['name']?.toString().trim() ?? '';
      final tag = animal['tag']?.toString().trim() ?? '';
      recent.add(DashboardActivity(animal: name.isNotEmpty ? name : tag.isNotEmpty ? tag : 'Animal', type: type, date: date));
    }
    recent.sort((a, b) => b.date.compareTo(a.date));
    return DashboardSummary(
      status: 'active', ranchName: ranchName, role: role, offline: offline, cachedAt: cachedAt,
      total: active.length,
      females: active.where((a) => a.value['sex'] == 'Hembra').length,
      males: active.where((a) => a.value['sex'] == 'Macho').length,
      weighed: weighedIds.length,
      activity: List.unmodifiable(recent.take(5)),
    );
  }
}

abstract interface class DashboardRepository {
  Future<DashboardSummary> load();
}
