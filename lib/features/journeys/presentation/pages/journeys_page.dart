import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../auth/domain/auth_gateway.dart';
import '../../../livestock/domain/inventory.dart';
import '../../../livestock/domain/event_draft.dart';
import '../../domain/journey.dart';

class JourneysPage extends StatefulWidget {
  const JourneysPage({super.key,required this.inventory,required this.auth,required this.changes});
  final InventoryRepository inventory;
  final AuthGateway auth;
  final Listenable changes;
  @override State<JourneysPage> createState()=>_JourneysPageState();
}
class _JourneysPageState extends State<JourneysPage>{
  InventorySnapshot? _snapshot;
  List<Journey> _items=[];
  String? _selected;
  String _query='',_filter='all';
  bool _loading=false,_busy=false;
  String? _error;
  int _request=0;
  JourneyRepository? get repository=>widget.inventory is JourneyRepository?widget.inventory as JourneyRepository:null;
  @override void initState(){super.initState();widget.auth.addListener(_changed);widget.changes.addListener(_changed);_load();}
  @override void dispose(){widget.auth.removeListener(_changed);widget.changes.removeListener(_changed);super.dispose();}
  void _changed(){
    if(!mounted)return;
    if(!widget.auth.signedIn||widget.auth.recovering){_request++;setState((){_snapshot=null;_items=[];_selected=null;_loading=false;});}
    else{_load();}
  }
  Future<void> _load()async{
    final repo=repository;
    if(repo==null||!widget.auth.signedIn||widget.auth.recovering)return;
    final request=++_request;
    setState((){_loading=true;_error=null;_snapshot=null;_items=[];});
    try{
      final snapshot=await widget.inventory.load();
      final items=snapshot.status=='active'&&!snapshot.offline?await repo.journeys(snapshot):<Journey>[];
      if(!mounted||request!=_request||!widget.auth.signedIn)return;
      setState((){_snapshot=snapshot;_items=items;});
    }catch(_){if(mounted&&request==_request)setState(()=>_error='No se pudieron consultar las jornadas.');}
    finally{if(mounted&&request==_request)setState(()=>_loading=false);}
  }
  Future<void> _run(Future<void> Function() action)async{
    if(_busy)return;
    setState((){_busy=true;_error=null;});
    try{await action();if(mounted)await _load();}
    on StateError catch(e){if(mounted)setState(()=>_error=e.message.toString());}
    catch(_){if(mounted){await _load();if(mounted)setState(()=>_error='No se confirmó el cambio. Actualiza antes de repetir.');}}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _create()async{
    final snapshot=_snapshot,repo=repository;
    if(snapshot==null||repo==null)return;
    final result=await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>_CreateJourney(snapshot:snapshot,repository:repo)));
    if(mounted&&result!=null){_selected=result;await _load();}
  }
  Future<void> _attend(Journey j,Map<String,dynamic> animal)async{
    final snapshot=_snapshot,repo=repository;
    if(snapshot==null||repo==null)return;
    double? weight;
    if(j.type=='weight'){
      weight=await showDialog<double>(context:context,builder:(_)=>_WeightDialog(initial:(animal['weight'] as num?)?.toDouble()));
      if(weight==null||!mounted)return;
    }
    await _run(()=>repo.attendJourney(snapshot,j,animal['id'] as String,weight));
  }
  @override Widget build(BuildContext context){
    final selected=_items.where((j)=>j.id==_selected).firstOrNull;
    return SafeArea(top:false,child:RefreshIndicator(onRefresh:_load,child:ListView(
      physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(20),children:[
      Row(children:[Expanded(child:Text('Jornadas de campo',style:Theme.of(context).textTheme.headlineSmall)),IconButton(tooltip:'Actualizar jornadas',onPressed:_busy||_loading?null:_load,icon:const Icon(Icons.refresh))]),
      if(_loading||_busy)const LinearProgressIndicator(),
      if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(!_loading&&_snapshot!=null&&_snapshot!.status!='active')const Text('Necesitas pertenecer a un rancho activo.'),
      if(_snapshot?.offline==true)const Text('Las jornadas requieren conexión a internet.'),
      if(selected==null&&_snapshot?.status=='active'&&_snapshot?.offline==false)...[
        FilledButton.icon(onPressed:_busy?null:_create,icon:const Icon(Icons.add),label:const Text('Nueva jornada')),
        if(_items.isEmpty)const Text('No hay jornadas registradas.'),
        for(final j in _items)Card(child:ListTile(title:Text(j.title),subtitle:Text('${j.date} · ${j.attended}/${j.roster.length} atendidos · ${j.open?'En curso':j.status=='completed'?'Completada':'Incompleta'}'),trailing:const Icon(Icons.chevron_right),onTap:(){setState((){_selected=j.id;_query='';_filter='all';});})),
      ],
      if(selected!=null)...[
        TextButton.icon(onPressed:()=>setState(()=>_selected=null),icon:const Icon(Icons.arrow_back),label:const Text('Volver a jornadas')),
        Text(selected.title,style:Theme.of(context).textTheme.headlineMedium),
        Text(selected.date),
        for(final k in ['product','dose','notes'])if((selected.payload[k]?.toString()??'').isNotEmpty)Text(selected.payload[k].toString()),
        const SizedBox(height:12),
        LinearProgressIndicator(value:selected.roster.isEmpty?0:selected.attended/selected.roster.length),
        Text('${selected.attended} de ${selected.roster.length} atendidos · ${selected.pending} pendientes'),
        const SizedBox(height:12),
        TextField(onChanged:(v)=>setState(()=>_query=v.toLowerCase().trim()),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar arete o nombre')),
        Wrap(spacing:8,children:[for(final f in const [('all','Todos'),('attended','Atendidos'),('pending','Pendientes')])ChoiceChip(label:Text(f.$2),selected:_filter==f.$1,onSelected:(_)=>setState(()=>_filter=f.$1))]),
        for(final a in selected.roster)
          if((_filter=='all'||(_filter=='attended')==(a['attended']==true))&&'${a['tag']} ${a['name']}'.toLowerCase().contains(_query))
            Card(child:ListTile(
              leading:Icon(a['attended']==true?Icons.check_circle:Icons.radio_button_unchecked),
              title:Text('${a['tag']??''} · ${a['name']??''}'),
              subtitle:Text(a['attended']==true?(selected.type=='weight'?'${a['weight']} kg':'Atendido'):'Pendiente'),
              trailing:selected.open&&eventTypes.containsKey(selected.type)&&(_snapshot?.animals.any((x)=>x.id==a['id']&&x.active)??false)&&(a['attended']!=true||selected.type=='weight')?TextButton(onPressed:_busy?null:()=>_attend(selected,a),child:Text(selected.type=='weight'?'Pesar':'Atender')):null,
            )),
        if(selected.open)const Padding(padding:EdgeInsets.only(top:16),child:Text('Para finalizar y generar los historiales colectivos, abre esta jornada en Ganaderov Web.')),
      ],
    ])));
  }
}
class _WeightDialog extends StatefulWidget{
  const _WeightDialog({this.initial});
  final double? initial;
  @override State<_WeightDialog> createState()=>_WeightDialogState();
}
class _WeightDialogState extends State<_WeightDialog>{
  late final _controller=TextEditingController(text:widget.initial?.toString()??'');
  final _key=GlobalKey<FormState>();
  @override void dispose(){_controller.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Registrar peso'),content:Form(key:_key,child:TextFormField(controller:_controller,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Peso (kg)'),validator:(v){final n=double.tryParse((v??'').replaceAll(',','.'));return n==null||!n.isFinite||n<0||n>100000?'Peso inválido':null;})),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:(){if(_key.currentState!.validate())Navigator.pop(context,double.parse(_controller.text.replaceAll(',','.')));},child:const Text('Guardar'))]);
}
class _CreateJourney extends StatefulWidget{
  const _CreateJourney({required this.snapshot,required this.repository});
  final InventorySnapshot snapshot;
  final JourneyRepository repository;
  @override State<_CreateJourney> createState()=>_CreateJourneyState();
}
class _CreateJourneyState extends State<_CreateJourney>{
  final _id=const Uuid().v4();
  final _product=TextEditingController(),_dose=TextEditingController(),_notes=TextEditingController();
  late final Set<String> _ids=widget.snapshot.animals.where((a)=>a.active).map((a)=>a.id).toSet();
  String _type='weight';
  DateTime _date=DateTime.now();
  bool _busy=false,_uncertain=false;
  String? _error;
  @override void dispose(){_product.dispose();_dose.dispose();_notes.dispose();super.dispose();}
  Future<void> _save()async{
    if(_busy||_ids.isEmpty)return;
    setState((){_busy=true;_error=null;});
    try{await widget.repository.createJourney(widget.snapshot,_id,_type,DateFormat('yyyy-MM-dd').format(_date),_product.text.trim(),_dose.text.trim(),_notes.text.trim(),_ids);if(mounted)Navigator.pop(context,_id);}
    catch(_){if(mounted)setState((){_uncertain=true;_error='No se confirmó la creación. Reintenta con los mismos datos o consulta las jornadas.';});}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context){
    final locked=_busy||_uncertain;
    return PopScope(canPop:!_busy,child:Scaffold(appBar:AppBar(title:const Text('Nueva jornada')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      DropdownButtonFormField<String>(initialValue:_type,items:[for(final e in eventTypes.entries)DropdownMenuItem(value:e.key,child:Text(e.value))],onChanged:locked?null:(v)=>setState(()=>_type=v!),decoration:const InputDecoration(labelText:'Tipo')),
      OutlinedButton(onPressed:locked?null:()async{final d=await showDatePicker(context:context,initialDate:_date,firstDate:DateTime(1900),lastDate:DateTime.now());if(mounted&&d!=null)setState(()=>_date=d);},child:Text(DateFormat('dd/MM/yyyy').format(_date))),
      TextField(controller:_product,enabled:!locked,maxLength:120,decoration:const InputDecoration(labelText:'Producto')),
      TextField(controller:_dose,enabled:!locked,maxLength:120,decoration:const InputDecoration(labelText:'Dosis registrada')),
      TextField(controller:_notes,enabled:!locked,maxLength:2000,decoration:const InputDecoration(labelText:'Observaciones')),
      Text('Animales seleccionados: ${_ids.length}'),
      Wrap(spacing:8,children:[TextButton(onPressed:locked?null:()=>setState(()=>_ids.addAll(widget.snapshot.animals.where((a)=>a.active).map((a)=>a.id))),child:const Text('Todos')),TextButton(onPressed:locked?null:()=>setState(_ids.clear),child:const Text('Ninguno'))]),
      for(final a in widget.snapshot.animals.where((a)=>a.active))CheckboxListTile(value:_ids.contains(a.id),onChanged:locked?null:(v)=>setState((){if(v==true){_ids.add(a.id);}else{_ids.remove(a.id);}}),title:Text(a.title),subtitle:Text(a.value('tag'))),
      if(_error!=null)Text(_error!),
      FilledButton(onPressed:_busy||_ids.isEmpty?null:_save,child:Text(_busy?'Guardando…':'Iniciar jornada')),
    ]))));
  }
}
