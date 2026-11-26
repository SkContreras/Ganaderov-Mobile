import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import '../../../auth/domain/auth_gateway.dart';
import '../../../livestock/domain/inventory.dart';
import '../../domain/productive_analysis.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key,required this.repository,required this.auth,required this.changes});
  final InventoryRepository repository;
  final AuthGateway auth;
  final Listenable changes;
  @override State<AnalysisPage> createState()=>_AnalysisPageState();
}
class _AnalysisPageState extends State<AnalysisPage>{
  InventorySnapshot? _snapshot;
  List<InventoryAnimal> _animals=[];
  String? _id;
  bool _loading=true,_failed=false;
  int _request=0;
  @override void initState(){super.initState();widget.auth.addListener(_changed);widget.changes.addListener(_changed);_load();}
  @override void dispose(){widget.auth.removeListener(_changed);widget.changes.removeListener(_changed);super.dispose();}
  void _changed(){
    if(!mounted)return;
    if(!widget.auth.signedIn||widget.auth.recovering){_request++;setState((){_snapshot=null;_animals=[];_id=null;_loading=false;_failed=false;});}
    else{_load();}
  }
  Future<void> _load()async{
    if(!widget.auth.signedIn||widget.auth.recovering)return;
    final request=++_request;
    setState((){_loading=true;_failed=false;_snapshot=null;_animals=[];});
    try{
      final s=await widget.repository.load().timeout(const Duration(seconds:45));
      final animals=s.animals.where((a)=>a.active).toList();
      if(!mounted||request!=_request||!widget.auth.signedIn)return;
      setState((){_snapshot=s;_animals=animals;if(!animals.any((a)=>a.id==_id))_id=null;});
    }catch(_){if(mounted&&request==_request)setState(()=>_failed=true);}
    finally{if(mounted&&request==_request)setState(()=>_loading=false);}
  }
  @override Widget build(BuildContext context){
    final animal=_animals.where((a)=>a.id==_id).firstOrNull;
    final points=animal==null?<WeightPoint>[]:weightHistory(animal);
    final basis=recentGrowth(points);
    return SafeArea(top:false,child:RefreshIndicator(onRefresh:_load,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(20),children:[
      Row(children:[Expanded(child:Text('Análisis ganadero',style:Theme.of(context).textTheme.headlineSmall)),IconButton(tooltip:'Actualizar análisis',onPressed:_loading?null:_load,icon:const Icon(Icons.refresh))]),
      if(_loading)const LinearProgressIndicator(),
      if(_failed)const Text('No se pudieron consultar los datos. Actualiza para reintentar.'),
      if(_snapshot!=null&&_snapshot!.status!='active')const Text('Necesitas pertenecer a un rancho activo.'),
      if(_snapshot?.status=='active')...[
        Text(_snapshot!.ranchName),
        if(_snapshot!.offline)Text('Sin conexión · datos del ${DateFormat('dd/MM HH:mm').format(_snapshot!.cachedAt!)}'),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(key:ValueKey(_id),initialValue:_id??'',isExpanded:true,decoration:const InputDecoration(labelText:'Animal',border:OutlineInputBorder()),items:[const DropdownMenuItem(value:'',child:Text('Captura manual')),for(final a in _animals)DropdownMenuItem(value:a.id,child:Text('${a.value('tag')} · ${a.title}',overflow:TextOverflow.ellipsis))],onChanged:(v)=>setState(()=>_id=v==''?null:v)),
        const SizedBox(height:16),
        if(animal!=null)...[
          Text('Evolución del peso',style:Theme.of(context).textTheme.titleLarge),
          if(points.isEmpty)const Text('Sin pesajes válidos.'),
          if(points.isNotEmpty)...[
            Text('Último peso promedio: ${points.last.weight.toStringAsFixed(1)} kg · ${DateFormat('dd/MM/yyyy').format(points.last.date)}'),
            if(DateTime.now().toUtc().difference(points.last.date).inDays>=30)const Text('Aviso: el último pesaje tiene al menos 30 días.'),
            SizedBox(height:200,child:CustomPaint(painter:_WeightChart(points,Theme.of(context).colorScheme.primary),child:const SizedBox.expand())),
            for(final p in points.reversed.take(8))ListTile(dense:true,title:Text(DateFormat('dd/MM/yyyy').format(p.date)),trailing:Text('${p.weight.toStringAsFixed(1)} kg (${p.count})')),
          ],
          if(basis==null)const Text('No hay dos fechas distintas dentro de los últimos 30 días de pesajes para calcular GMD.')
          else Text('GMD medida: ${basis.gain.toStringAsFixed(3)} kg/día · ${basis.days} días · ${basis.points.length} fechas'),
          if(basis?.variable==true)const Text('Aviso: hubo ganancias y pérdidas entre pesajes.'),
        ],
        _ScenarioTools(key:ValueKey('$_id-${points.isEmpty?'':points.last.weight}-${basis?.gain}'),initialWeight:points.isEmpty?null:points.last.weight,initialGain:basis?.gain,baseDate:points.isEmpty?null:points.last.date),
      ],
    ])));
  }
}
class _ScenarioTools extends StatefulWidget{
  const _ScenarioTools({super.key,this.initialWeight,this.initialGain,this.baseDate});
  final double? initialWeight,initialGain;
  final DateTime? baseDate;
  @override State<_ScenarioTools> createState()=>_ScenarioToolsState();
}
class _ScenarioToolsState extends State<_ScenarioTools>{
  late final _weight=TextEditingController(text:widget.initialWeight?.toStringAsFixed(1)??'');
  late final _gain=TextEditingController(text:widget.initialGain?.toStringAsFixed(3)??'');
  final _days=TextEditingController(text:'30'),_price=TextEditingController(),_future=TextEditingController(),_cost=TextEditingController(),_target=TextEditingController(),_count=TextEditingController(text:'1'),_ration=TextEditingController(),_feedPrice=TextEditingController();
  @override void dispose(){for(final c in [_weight,_gain,_days,_price,_future,_cost,_target,_count,_ration,_feedPrice]){c.dispose();}super.dispose();}
  double? _n(TextEditingController c){final v=double.tryParse(c.text.trim().replaceAll(',','.'));return v!=null&&v.isFinite?v:null;}
  Widget _field(String label,TextEditingController c)=>Padding(padding:const EdgeInsets.only(top:10),child:TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true,signed:true),onChanged:(_)=>setState((){}),decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
  String money(double v)=>NumberFormat.currency(locale:'es_MX',symbol:r'$').format(v);
  @override Widget build(BuildContext context){
    final w=_n(_weight),g=_n(_gain),d=int.tryParse(_days.text),p=_n(_price),f=_n(_future)??(_future.text.trim().isEmpty?p:null),c=_n(_cost),t=_n(_target),n=int.tryParse(_count.text),ration=_n(_ration),fp=_n(_feedPrice);
    final valid=w!=null&&g!=null&&d!=null&&d>=0&&d<=3650&&w>=0&&(w+g*d).isFinite&&w+g*d>=0;
    final sale=valid&&p!=null&&f!=null&&c!=null?SaleScenario(weight:w,gain:g,days:d,price:p,futurePrice:f,dailyCost:c):null;
    final result=sale?.valid==true?sale:null;
    final target=w!=null&&g!=null&&t!=null?targetDays(w,g,t):null;
    final feed=n!=null&&n>0&&ration!=null&&ration>=0&&fp!=null&&fp>=0&&d!=null&&d>=0&&d<=3650&&(n*ration*fp*d).isFinite;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const SizedBox(height:24),
      Text('Proyección de crecimiento',style:Theme.of(context).textTheme.titleLarge),
      Text(widget.baseDate==null?'Escenario manual: los valores no son mediciones.':'Fecha base: ${DateFormat('dd/MM/yyyy').format(widget.baseDate!)}. Si editas la GMD, será un supuesto.'),
      _field('Peso base (kg)',_weight),_field('GMD (kg/día)',_gain),_field('Plazo (días)',_days),
      if(valid)Card(child:Padding(padding:const EdgeInsets.all(16),child:Text('Peso proyectado: ${(w+g*d).toStringAsFixed(1)} kg\nFecha objetivo: ${DateFormat('dd/MM/yyyy').format((widget.baseDate??DateTime.now()).add(Duration(days:d)))}'))),
      const SizedBox(height:20),
      Text('Peso objetivo',style:Theme.of(context).textTheme.titleLarge),
      _field('Peso objetivo (kg)',_target),
      Text(target==null?'Completa los datos. Una GMD no positiva no alcanza un objetivo superior.':'$target días estimados desde la fecha base.'),
      const SizedBox(height:20),
      Text('Rentabilidad de venta (MXN)',style:Theme.of(context).textTheme.titleLarge),
      _field('Precio actual por kg',_price),_field('Precio futuro por kg (opcional)',_future),_field('Costo diario por animal',_cost),
      if(result!=null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Venta base: ${money(result.current)}'),
        Text('Venta futura bruta: ${money(result.gross)}'),
        Text('Costos: ${money(result.cost)}'),
        Text('Venta futura neta: ${money(result.gross-result.cost)}'),
        Text('Diferencia: ${money(result.net)}',style:Theme.of(context).textTheme.titleMedium),
        if(result.breakPrice!=null)Text('Precio de equilibrio: ${money(result.breakPrice!)}/kg'),
        if(result.breakCost!=null)Text('Costo diario de equilibrio: ${money(result.breakCost!)}/día'),
      ]))),
      const SizedBox(height:20),
      Text('Alimentación y lote',style:Theme.of(context).textTheme.titleLarge),
      _field('Número de animales',_count),_field('Ración kg/animal/día',_ration),_field('Precio del alimento por kg',_feedPrice),
      if(feed)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Alimento total: ${(n*ration*d).toStringAsFixed(1)} kg'),
        Text('Costo por animal/día: ${money(ration*fp)}'),
        Text('Costo total: ${money(n*ration*fp*d)}'),
        TextButton(onPressed:()=>setState(()=>_cost.text=(ration*fp).toStringAsFixed(2)),child:const Text('Usar como costo diario')),
      ]))),
      if(result!=null&&n!=null&&n>0&&(result.net*n).isFinite)Text('Diferencia estimada para $n animales iguales: ${money(result.net*n)}'),
      const SizedBox(height:16),
      const Text('Simulaciones lineales bajo los supuestos capturados. No garantizan crecimiento, precios ni ganancias. No sustituyen un presupuesto completo.'),
    ]);
  }
}
class _WeightChart extends CustomPainter{
  const _WeightChart(this.points,this.color);
  final List<WeightPoint> points;
  final Color color;
  @override void paint(Canvas canvas,Size size){
    if(points.isEmpty||size.width<40||size.height<40)return;
    final lo=points.map((p)=>p.weight).reduce(math.min);
    final hi=points.map((p)=>p.weight).reduce(math.max);
    final span=math.max(1.0,hi-lo);
    final days=math.max(1,points.last.date.difference(points.first.date).inDays);
    final line=Paint()..color=color..strokeWidth=2..style=PaintingStyle.stroke;
    final dot=Paint()..color=color;
    final path=Path();
    for(var i=0;i<points.length;i++){
      final p=points[i];
      final x=12+(size.width-24)*p.date.difference(points.first.date).inDays/days;
      final y=size.height-20-(size.height-40)*(p.weight-lo)/span;
      if(i==0){path.moveTo(x,y);}else{path.lineTo(x,y);}
      canvas.drawCircle(Offset(x,y),3,dot);
    }
    canvas.drawPath(path,line);
  }
  @override bool shouldRepaint(covariant _WeightChart old)=>old.points!=points||old.color!=color;
}
