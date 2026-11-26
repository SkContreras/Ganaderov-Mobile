import 'inventory.dart';

const eventTypes = {
  'weight':'Pesaje','bath':'Baño','vaccine':'Vacunación','deworm':'Desparasitación',
  'injection':'Inyección','medication':'Medicamento','review':'Revisión veterinaria',
};
class EventDraft {
  const EventDraft({required this.id,required this.type,required this.date,this.weight,this.product='',this.notes='',this.capturedAt});
  final String id,type,date,product,notes;
  final double? weight;
  final DateTime? capturedAt;
  Map<String,dynamic> toJson()=>{'id':id,'type':type,'date':date,'weight':weight,'product':product,'notes':notes,'capturedAt':capturedAt?.toUtc().toIso8601String()};
  factory EventDraft.fromJson(Map<String,dynamic> j)=>EventDraft(id:j['id'] as String,type:j['type'] as String,date:j['date'] as String,weight:(j['weight'] as num?)?.toDouble(),product:j['product'] as String,notes:j['notes'] as String,capturedAt:DateTime.tryParse(j['capturedAt']?.toString()??''));
  void validate(){
    if(id.isEmpty||!eventTypes.containsKey(type))throw StateError('Tipo de registro inválido.');
    final parsed=DateTime.tryParse(date);
    if(parsed==null||!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)||parsed.toIso8601String().substring(0,10)!=date||parsed.isAfter(DateTime.now()))throw StateError('Fecha inválida.');
    if(type=='weight'&&(weight==null||!weight!.isFinite||weight!<0||weight!>100000))throw StateError('Introduce un peso válido.');
    if(product.length>120||notes.length>2000)throw StateError('Texto demasiado largo.');
  }
  Map<String,dynamic> toEvent(String animalId,Map<String,dynamic> actor,DateTime now){
    validate();
    final stamp=(capturedAt??now).toUtc().toIso8601String();
    return {'id':id,'animalId':animalId,'type':type,'date':date,'createdAt':stamp,'performedAt':stamp,'performedBy':actor,if(type=='weight')'weight':weight,if(product.trim().isNotEmpty)'label':product.trim(),if(notes.trim().isNotEmpty)'notes':notes.trim()};
  }
}
abstract interface class AnimalEventWriter {
  Future<void> addEvent(InventorySnapshot snapshot,String animalId,EventDraft draft);
}
