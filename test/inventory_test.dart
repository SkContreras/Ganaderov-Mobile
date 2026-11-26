import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';

Map<String,dynamic> row(String id, String tag, String status, {bool deleted = false}) => {
  'animal_id': id, 'deleted_at': deleted ? '2026-01-01' : null,
  'payload': {'animal': {'id':id,'tag':tag,'name':'Rocío','status':status}, 'events': [
    {'animalId':id,'type':'weight','date':'2026-01-01','weight':200},
    {'animalId':id,'type':'weight','date':'2026-02-01','weight':'220.5'},
    {'animalId':'foreign','type':'weight','date':'2026-03-01','weight':900},
  ]},
};
void main() {
  test('archive, search, sort, and last weight match synced records', () {
    final animals = InventorySnapshot(status:'active', records:[
      row('a','10','Vendido'), row('b','2','Activo'), row('c','3','Activo',deleted:true), row('d','4','Cuarentena'),
    ],statusOptions:{'Cuarentena':false},statusLabels:{'Cuarentena':'Aislado'}).animals;
    expect(animals.map((a)=>a.id), ['b','d','a']);
    expect(animals.where((a)=>a.active).length,1);
    expect(animals.first.matches('rocio 2'),isTrue);
    expect(animals[1].statusLabel,'Aislado');
    expect(animals.first.latestWeight!.weight,220.5);
    expect(animals.first.events.length,2);
  });
}
