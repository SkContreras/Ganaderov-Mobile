import 'package:material_ui/material_ui.dart';
import '../../../../core/sync/event_outbox.dart';
import '../../../livestock/domain/event_draft.dart';

class SyncPanel extends StatefulWidget{
  const SyncPanel({super.key,required this.access});
  final OutboxAccess access;
  @override State<SyncPanel> createState()=>_SyncPanelState();
}
class _SyncPanelState extends State<SyncPanel>{
  List<PendingEvent>? _items;
  bool _busy=false;
  String? _error;
  @override void initState(){super.initState();_refresh();}
  Future<void> _refresh({bool send=false})async{
    if(_busy)return;
    setState((){_busy=true;_error=null;_items=null;});
    try{
      if(send)await widget.access.syncEvents(manual:true);
      final items=await widget.access.pendingEvents();
      if(mounted)setState(()=>_items=items);
    }catch(_){if(mounted)setState(()=>_error='No se pudo consultar la cola.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text('Sincronización',style:Theme.of(context).textTheme.titleMedium),
    const Text('Los registros pendientes se envían automáticamente mientras la app está abierta.'),
    if(_busy)const LinearProgressIndicator(),
    if(_error!=null)Text(_error!),
    if(_items!=null)...[
      Text('${_items!.length} registros pendientes'),
      for(final p in _items!)ListTile(contentPadding:EdgeInsets.zero,title:Text('${eventTypes[p.draft.type]??p.draft.type} · ${p.draft.date}'),subtitle:Text([if(p.draft.weight!=null)'${p.draft.weight} kg',if(p.draft.product.isNotEmpty)p.draft.product,'Animal: ${p.animalId}',if(p.error.isNotEmpty)p.error].join(' · '))),
    ],
    Wrap(spacing:8,children:[TextButton(onPressed:_busy?null:()=>_refresh(),child:const Text('Actualizar estado')),FilledButton.icon(onPressed:_busy?null:()=>_refresh(send:true),icon:const Icon(Icons.sync),label:const Text('Sincronizar ahora'))]),
  ])));
}
