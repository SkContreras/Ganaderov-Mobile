import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../../auth/domain/auth_gateway.dart';
import '../../domain/ranch.dart';

class RanchPanel extends StatefulWidget {
  const RanchPanel({super.key,required this.repository,required this.auth});
  final RanchRepository repository;
  final AuthGateway auth;
  @override State<RanchPanel> createState()=>_RanchPanelState();
}
class _RanchPanelState extends State<RanchPanel>{
  RanchContext? _ranch;
  bool _loading=true,_busy=false,_failed=false;
  int _request=0;
  String? _message;
  @override void initState(){super.initState();widget.auth.addListener(_authChanged);_load();}
  @override void dispose(){widget.auth.removeListener(_authChanged);super.dispose();}
  void _authChanged(){
    if(!mounted)return;
    if(!widget.auth.signedIn||widget.auth.recovering){
      _request++;
      setState((){_ranch=null;_loading=false;_failed=false;_message=null;});
    }else{_load();}
  }
  Future<void> _load() async{
    if(!widget.auth.signedIn||widget.auth.recovering)return;
    final request=++_request;
    setState((){_loading=true;_failed=false;_ranch=null;});
    try{
      final ranch=await widget.repository.load().timeout(const Duration(seconds:30));
      if(!mounted||request!=_request||!widget.auth.signedIn)return;
      setState(()=>_ranch=ranch);
    }catch(_){if(mounted&&request==_request)setState(()=>_failed=true);}
    finally{if(mounted&&request==_request)setState(()=>_loading=false);}
  }
  Future<void> _run(Future<void> Function() action)async{
    if(_busy||!widget.auth.signedIn)return;
    setState((){_busy=true;_message=null;});
    try{await action();if(mounted){await _load();if(mounted)setState(()=>_message='Operación completada.');}}
    on StateError catch(e){if(mounted)setState(()=>_message=e.message.toString());}
    catch(_){if(mounted){await _load();if(mounted)setState(()=>_message='No se pudo confirmar la operación. Revisa el estado antes de repetirla.');}}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _form(bool create)async{
    final result=await showDialog<(String,String)>(context:context,builder:(_)=>_RanchForm(create:create));
    if(result==null||!mounted)return;
    await _run(()=>create?widget.repository.create(result.$1,result.$2):widget.repository.requestAccess(result.$1,result.$2));
  }
  Future<void> _confirm(String title,String message,Future<void> Function() action)async{
    final accepted=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:Text(title),content:Text(message),actions:[
      TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),
      FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Confirmar')),
    ]));
    if(mounted&&accepted==true)await _run(action);
  }
  @override Widget build(BuildContext context){
    final ranch=_ranch;
    final disabled=_loading||_busy;
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        const Icon(Icons.agriculture),
        const SizedBox(width:10),
        Expanded(child:Text('Rancho y usuarios',style:Theme.of(context).textTheme.titleMedium)),
        IconButton(tooltip:'Actualizar rancho',onPressed:disabled?null:()async{await _load();if(mounted)widget.repository.invalidate();},icon:const Icon(Icons.refresh)),
      ]),
      if(_loading||_busy)const LinearProgressIndicator(),
      if(_failed)const Text('No se pudo comprobar la membresía. Actualiza para reintentar.'),
      if(ranch?.status=='unassigned')...[
        const Text('Crea tu propio rancho o solicita acceso con el código de otro.'),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:disabled?null:()=>_form(true),icon:const Icon(Icons.add),label:const Text('Crear rancho')),
        OutlinedButton.icon(onPressed:disabled?null:()=>_form(false),icon:const Icon(Icons.group_add_outlined),label:const Text('Unirme a un rancho')),
      ],
      if(ranch?.status=='pending')const ListTile(leading:Icon(Icons.hourglass_top),title:Text('Solicitud pendiente'),subtitle:Text('Un administrador debe aprobar tu acceso. Actualiza esta pantalla para comprobarlo.')),
      if(ranch!=null&&ranch.status=='active')...[
        Text(ranch.name,style:Theme.of(context).textTheme.titleLarge),
        Text('${ranch.displayName} · ${ranchRoleLabel(ranch.role)}'),
        if(ranch.canManage)...[
          const SizedBox(height:12),
          if(ranch.joinCode.isNotEmpty)ListTile(contentPadding:EdgeInsets.zero,title:const Text('Código de acceso'),subtitle:SelectableText(ranch.joinCode),trailing:IconButton(tooltip:'Copiar código',onPressed:disabled?null:()async{await Clipboard.setData(ClipboardData(text:ranch.joinCode));if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Código copiado.')));},icon:const Icon(Icons.copy))),
          const Divider(),
          Text('Miembros (${ranch.members.length})',style:Theme.of(context).textTheme.titleMedium),
          for(final member in ranch.members)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.person_outline),title:Text(member.name),subtitle:Text(ranchRoleLabel(member.role)),trailing:member.role=='worker'?IconButton(tooltip:'Retirar acceso',onPressed:disabled?null:()=>_confirm('Retirar acceso','¿Retirar el acceso de ${member.name} al rancho? Su cuenta no será eliminada.',()=>widget.repository.revoke(ranch,member.id)),icon:const Icon(Icons.person_remove_outlined)):null),
          const Divider(),
          Text('Solicitudes pendientes (${ranch.requests.length})',style:Theme.of(context).textTheme.titleMedium),
          if(ranch.requests.isEmpty)const Text('No hay solicitudes pendientes.'),
          for(final request in ranch.requests)Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            ListTile(contentPadding:EdgeInsets.zero,title:Text(request.name),subtitle:Text(request.requestedAt.length>=10?request.requestedAt.substring(0,10):request.requestedAt)),
            Wrap(spacing:8,children:[
              FilledButton(onPressed:disabled?null:()=>_confirm('Aprobar solicitud','${request.name} tendrá acceso como trabajador.',()=>widget.repository.review(ranch,request.id,true)),child:const Text('Aprobar')),
              OutlinedButton(onPressed:disabled?null:()=>_confirm('Rechazar solicitud','¿Rechazar la solicitud de ${request.name}?',()=>widget.repository.review(ranch,request.id,false)),child:const Text('Rechazar')),
            ]),
          ]),
        ]else const Text('Tu acceso está limitado a las funciones autorizadas para trabajadores.'),
      ],
      if(_message!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_message!)),
    ])));
  }
}
class _RanchForm extends StatefulWidget{
  const _RanchForm({required this.create});
  final bool create;
  @override State<_RanchForm> createState()=>_RanchFormState();
}
class _RanchFormState extends State<_RanchForm>{
  final _key=GlobalKey<FormState>();
  final _first=TextEditingController(),_name=TextEditingController();
  @override void dispose(){_first.dispose();_name.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text(widget.create?'Crear rancho':'Unirme a un rancho'),
    content:SingleChildScrollView(child:Form(key:_key,child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextFormField(controller:_first,maxLength:widget.create?120:40,textCapitalization:widget.create?TextCapitalization.words:TextCapitalization.characters,decoration:InputDecoration(labelText:widget.create?'Nombre del rancho':'Código de acceso'),validator:(v)=>(v??'').trim().length<(widget.create?1:6)?'Completa este campo':null),
      TextFormField(controller:_name,maxLength:120,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Tu nombre'),validator:(v)=>(v??'').trim().isEmpty?'Introduce tu nombre':null),
    ]))),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:(){if(_key.currentState!.validate())Navigator.pop(context,(_first.text,_name.text));},child:Text(widget.create?'Crear':'Solicitar acceso'))],
  );
}
