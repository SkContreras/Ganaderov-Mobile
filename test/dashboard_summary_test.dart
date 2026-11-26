import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/dashboard/domain/dashboard_summary.dart';

Map<String, dynamic> row(String id, String sex, String status, {bool deleted = false, List<Map<String, dynamic>> events = const []}) => {
  'animal_id': id,
  'deleted_at': deleted ? '2026-01-01' : null,
  'payload': {'animal': {'id': id, 'sex': sex, 'status': status, 'tag': id}, 'events': events},
};
Map<String, dynamic> weight(String id, String animal) => {'id': id, 'animalId': animal, 'type': 'weight', 'date': '2026-01-01'};

void main() {
  test('matches web active status and distinct weighed animals', () {
    final data = DashboardSummary.fromRecords(ranchName: 'Rancho', role: 'worker', records: [
      row('a', 'Hembra', 'Activo', events: [weight('1', 'a'), weight('2', 'a')]),
      row('b', 'Macho', 'Activo'),
      row('c', 'Hembra', 'Vendido', events: [weight('3', 'c')]),
      row('d', 'Macho', 'Activo', deleted: true),
      row('e', 'Hembra', 'Cuarentena'),
      row('f', 'Macho', 'Otro'),
    ], statusOptions: {'Cuarentena': false, 'Otro': true});
    expect(data.total, 3);
    expect(data.females, 1);
    expect(data.males, 2);
    expect(data.weighed, 1);
    expect(data.activity.length, 2);
  });
  test('empty inventory is a verified zero', () {
    final data = DashboardSummary.fromRecords(ranchName: 'Rancho', role: 'owner', records: []);
    expect(data.total, 0);
    expect(data.activity, isEmpty);
  });
}
