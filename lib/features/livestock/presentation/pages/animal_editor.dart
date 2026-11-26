import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import '../../domain/inventory.dart';
import '../../domain/animal_form_config.dart';

class AnimalEditor extends StatefulWidget {
  const AnimalEditor({super.key, required this.snapshot, required this.writer, this.animal});
  final InventorySnapshot snapshot;
  final AnimalWriter writer;
  final InventoryAnimal? animal;
  @override State<AnimalEditor> createState()=>_AnimalEditorState();
}
class _AnimalEditorState extends State<AnimalEditor> {
  final _key=GlobalKey<FormState>();
  final _controls=<String,TextEditingController>{};
  bool _busy=false;
  String? _error;
  late final AnimalFormConfig config=AnimalFormConfig(widget.snapshot.config);
  @override void initState(){
    super.initState();
    for(final f in animalFields){
      final v=widget.animal?.fields[f.id];
      _controls[f.id]=TextEditingController(text:f.kind=='age'&&v is Map ? (v['monthsAtRecord']??'').toString() : v?.toString()??(f.id=='status'?'Activo':''));
    }
  }
  @override void dispose(){for(final c in _controls.values){c.dispose();}super.dispose();}
  String value(String id)=>_controls[id]!.text.trim();
  Future<void> _save() async {
    if(_busy||!(_key.currentState?.validate()??false)) return;
    setState((){_busy=true;_error=null;});
    try{
      final changes=<String,dynamic>{};
      for(final f in animalFields.where((f)=>config.visible(f)&&config.applies(f,value('status'),value('originType')))){
        final v=value(f.id);
        if(f.kind=='age'){
          final old=widget.animal?.fields[f.id];
          if(v.isEmpty){changes[f.id]=null;}
          else if(old is Map && old['monthsAtRecord'].toString()==v){changes[f.id]=old;}
          else {changes[f.id]={'monthsAtRecord':int.parse(v),'recordedAt':DateFormat('yyyy-MM-dd').format(DateTime.now())};}
        }else if(f.kind=='boolean'){changes[f.id]=v.isEmpty?'':v=='true';}
        else{changes[f.id]=v;}
      }
      await widget.writer.saveAnimal(widget.snapshot,widget.animal?.id,changes);
      if(mounted) Navigator.of(context).pop(true);
    }on StateError catch(e){if(mounted)setState(()=>_error=e.message.toString());}
    catch(_){if(mounted)setState(()=>_error='No se confirmó el guardado. Actualiza el inventario antes de repetir la operación.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Widget _field(AnimalField f){
    final c=_controls[f.id]!;
    final required=config.requiredField(f)&&!(f.id=='estimatedAge'&&value('birthDate').isNotEmpty);
    final options=f.kind=='parent'?{for(final a in widget.snapshot.animals.where((a)=>a.id!=widget.animal?.id))a.id:a.title}:config.choices(f.id);
    final select=f.kind=='select'||f.kind=='boolean'||f.kind=='parent'||(f.kind=='list'&&options.isNotEmpty);
    final label='${config.label(f)}${required?' *':''}';
    String? validate(String? v){
      final s=(v??'').trim();
      if(required&&s.isEmpty)return 'Campo obligatorio';
      if(f.kind=='age'&&s.isNotEmpty&&(int.tryParse(s)==null||int.parse(s)<0))return 'Introduce meses enteros';
      if(f.kind=='date'&&s.isNotEmpty&&(DateTime.tryParse(s)==null||!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)))return 'Formato AAAA-MM-DD';
      return null;
    }
    if(select){
      final entries={'':'Sin seleccionar',...options};
      if(c.text.isNotEmpty&&!entries.containsKey(c.text))entries[c.text]='${c.text} (actual)';
      return DropdownButtonFormField<String>(key:ValueKey(f.id),initialValue:c.text, isExpanded:true,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),items:[for(final e in entries.entries)DropdownMenuItem(value:e.key,child:Text(e.value,overflow:TextOverflow.ellipsis))],onChanged:_busy?null:(v)=>setState(()=>c.text=v??''),validator:validate);
    }
    return TextFormField(controller:c,enabled:!_busy,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder(),hintText:f.kind=='date'?'AAAA-MM-DD':null),keyboardType:f.kind=='age'?TextInputType.number:TextInputType.text,onChanged:f.id=='birthDate'?(_)=>setState((){}):null,validator:validate);
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!_busy,child:Scaffold(
    appBar:AppBar(title:Text(widget.animal==null?'Registrar animal':'Editar animal'),automaticallyImplyLeading:!_busy),
    body:SafeArea(child:Form(key:_key,child:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Los campos con * son obligatorios.'),
      const SizedBox(height:16),
      for(final f in animalFields.where((f)=>config.visible(f)&&config.applies(f,value('status'),value('originType')))) Padding(padding:const EdgeInsets.only(bottom:14),child:_field(f)),
      if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      FilledButton(onPressed:_busy?null:_save,child:Text(_busy?'Guardando…':'Guardar animal')),
    ]))),
  ));
}
