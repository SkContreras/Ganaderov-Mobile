import 'inventory.dart';

const eventTypes = {
  'weight':'Pesaje','bath':'Baño','vaccine':'Vacunación','deworm':'Desparasitación',
  'injection':'Inyección','medication':'Medicamento','review':'Revisión veterinaria',
};
class EventDraft {
  const EventDraft({required this.id,required this.type,required this.date,this.weight,this.product='',this.notes=''});
  final String id,type,date,product,notes;
  final double? weight;
  void validate(){
    if(id.isEmpty||!eventTypes.containsKey(type))throw StateError('Tipo de registro inválido.');
    final parsed=DateTime.tryParse(date);
    if(parsed==null||!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)||parsed.toIso8601String().substring(0,10)!=date||parsed.isAfter(DateTime.now()))throw StateError('Fecha inválida.');
    if(type=='weight'&&(weight==null||!weight!.isFinite||weight!<0||weight!>100000))throw StateError('Introduce un peso válido.');
    if(product.length>120||notes.length>2000)throw StateError('Texto demasiado largo.');
  }
  Map<String,dynamic> toEvent(String animalId,Map<String,dynamic> actor,DateTime now){
    validate();
    final stamp=now.toUtc().toIso8601String();
    return {'id':id,'animalId':animalId,'type':type,'date':date,'createdAt':stamp,'performedAt':stamp,'performedBy':actor,if(type=='weight')'weight':weight,if(product.trim().isNotEmpty)'label':product.trim(),if(notes.trim().isNotEmpty)'notes':notes.trim()};
  }
}
abstract interface class AnimalEventWriter {
  Future<void> addEvent(InventorySnapshot snapshot,String animalId,EventDraft draft);
}
