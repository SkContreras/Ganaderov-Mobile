import '../../livestock/domain/inventory.dart';
import '../../livestock/domain/event_draft.dart';

class Journey {
  const Journey(this.id,this.version,this.payload);
  final String id,version;
  final Map<String,dynamic> payload;
  String get type=>payload['type']?.toString()??'';
  String get title=>type=='other'?(payload['name']?.toString()??'Actividad personalizada'):eventTypes[type]??type;
  String get status=>payload['status']?.toString()??'';
  String get date=>payload['date']?.toString()??'';
  bool get open=>status=='in_progress';
  List<Map<String,dynamic>> get roster=>(payload['roster'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  int get attended=>roster.where((a)=>a['attended']==true).length;
  int get pending=>roster.length-attended;
  static Map<String,dynamic> rosterEntry(InventoryAnimal a)=>{'id':a.id,for(final k in ['tag','name','sex','color','status']) k:a.value(k),'attended':false};
}
abstract interface class JourneyRepository {
  Future<List<Journey>> journeys(InventorySnapshot snapshot);
  Future<void> createJourney(InventorySnapshot snapshot,String id,String type,String date,String product,String dose,String notes,Set<String> animalIds);
  Future<void> attendJourney(InventorySnapshot snapshot,Journey journey,String animalId,double? weight);
}
