import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../domain/event_draft.dart';
import '../../domain/inventory.dart';

class EventEditor extends StatefulWidget {
  const EventEditor({super.key,required this.snapshot,required this.animal,required this.writer,required this.initialType});
  final InventorySnapshot snapshot;
  final InventoryAnimal animal;
  final AnimalEventWriter writer;
  final String initialType;
  @override State<EventEditor> createState()=>_EventEditorState();
}
class _EventEditorState extends State<EventEditor>{
  final _form=GlobalKey<FormState>();
  final _weight=TextEditingController(),_product=TextEditingController(),_notes=TextEditingController();
  final _id=const Uuid().v4();
  final _capturedAt=DateTime.now().toUtc();
  late String _type=widget.initialType;
  DateTime _date=DateTime.now();
  bool _busy=false,_uncertain=false;
  String? _error;
  @override void dispose(){_weight.dispose();_product.dispose();_notes.dispose();super.dispose();}
  Future<void> _save()async{
    if(_busy||!(_form.currentState?.validate()??false))return;
    final draft=EventDraft(id:_id,capturedAt:_capturedAt,type:_type,date:DateFormat('yyyy-MM-dd').format(_date),weight:_type=='weight'?double.tryParse(_weight.text.trim().replaceAll(',','.')):null,product:_type=='weight'?'':_product.text.trim(),notes:_notes.text.trim());
    setState((){_busy=true;_error=null;});
    try{
      await widget.writer.addEvent(widget.snapshot,widget.animal.id,draft);
      if(mounted)Navigator.of(context).pop(true);
    }on StateError catch(e){if(mounted)setState(()=>_error=e.message.toString());}
    catch(_){if(mounted)setState((){_uncertain=true;_error='No se confirmó el guardado. Reintenta con los mismos datos para evitar duplicados.';});}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context){
    final locked=_busy||_uncertain;
    return PopScope(canPop:!_busy,child:Scaffold(
      appBar:AppBar(title:const Text('Registrar actividad'),automaticallyImplyLeading:!_busy),
      body:SafeArea(child:Form(key:_form,child:ListView(padding:const EdgeInsets.all(20),children:[
        Text(widget.animal.title,style:Theme.of(context).textTheme.headlineSmall),
        Text('Arete: ${widget.animal.value('tag')}'),
        const SizedBox(height:20),
        const Text('Se guardará primero en el dispositivo y se enviará cuando haya conexión.'),
        DropdownButtonFormField<String>(initialValue:_type,decoration:const InputDecoration(labelText:'Tipo de registro',border:OutlineInputBorder()),items:[for(final e in eventTypes.entries)if(!['note','other'].contains(e.key)||['owner','admin'].contains(widget.snapshot.role))DropdownMenuItem(value:e.key,child:Text(e.value))],onChanged:locked?null:(v)=>setState(()=>_type=v!)),
        const SizedBox(height:16),
        OutlinedButton.icon(onPressed:locked?null:()async{
          final value=await showDatePicker(context:context,initialDate:_date,firstDate:DateTime(1900),lastDate:DateTime.now());
          if(mounted&&value!=null)setState(()=>_date=value);
        },icon:const Icon(Icons.calendar_today),label:Text(DateFormat('dd/MM/yyyy').format(_date))),
        const SizedBox(height:16),
        if(_type=='weight')TextFormField(controller:_weight,enabled:!locked,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Peso (kg)',border:OutlineInputBorder()),validator:(v){final n=double.tryParse((v??'').trim().replaceAll(',','.'));return n==null||!n.isFinite||n<0||n>100000?'Introduce un peso válido':null;})
        else TextFormField(controller:_product,enabled:!locked,maxLength:120,decoration:const InputDecoration(labelText:'Producto o tratamiento (opcional)',border:OutlineInputBorder())),
        const SizedBox(height:16),
        TextFormField(controller:_notes,enabled:!locked,maxLines:3,maxLength:2000,decoration:const InputDecoration(labelText:'Observaciones',border:OutlineInputBorder()),validator:(value)=>_type=='note'&&(value??'').trim().isEmpty?'Escribe la observación':null),
        if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        const SizedBox(height:12),
        FilledButton(onPressed:_busy?null:_save,child:Text(_busy?'Guardando…':_uncertain?'Reintentar guardado':'Guardar registro')),
      ]))),
    ));
  }
}
