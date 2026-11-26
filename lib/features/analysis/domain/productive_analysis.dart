import '../../livestock/domain/inventory.dart';

class WeightPoint {
  const WeightPoint(this.date,this.weight,this.count);
  final DateTime date;
  final double weight;
  final int count;
}
List<WeightPoint> weightHistory(InventoryAnimal animal) {
  final grouped=<DateTime,List<double>>{};
  for(final e in animal.events){
    final d=e.date,w=e.weight;
    if(e.type!='weight'||d==null||w==null||!w.isFinite||w<0)continue;
    final day=DateTime.utc(d.year,d.month,d.day);
    (grouped[day]??=[]).add(w);
  }
  return grouped.entries.map((e)=>WeightPoint(e.key,e.value.reduce((a,b)=>a+b)/e.value.length,e.value.length)).toList()..sort((a,b)=>a.date.compareTo(b.date));
}
class GrowthBasis {
  const GrowthBasis(this.points,this.gain,this.days,this.variable);
  final List<WeightPoint> points;
  final double gain;
  final int days;
  final bool variable;
}
GrowthBasis? recentGrowth(List<WeightPoint> points){
  if(points.length<2)return null;
  final last=points.last;
  final recent=points.where((p)=>!p.date.isBefore(last.date.subtract(const Duration(days:30)))).toList();
  if(recent.length<2)return null;
  final days=last.date.difference(recent.first.date).inDays;
  if(days<=0)return null;
  bool up=false,down=false;
  for(var i=1;i<recent.length;i++){
    up=up||recent[i].weight>recent[i-1].weight;
    down=down||recent[i].weight<recent[i-1].weight;
  }
  return GrowthBasis(recent,(last.weight-recent.first.weight)/days,days,up&&down);
}
class SaleScenario {
  const SaleScenario({required this.weight,required this.gain,required this.days,required this.price,required this.futurePrice,required this.dailyCost});
  final double weight,gain,price,futurePrice,dailyCost;
  final int days;
  double get projected=>weight+gain*days;
  double get current=>weight*price;
  double get gross=>projected*futurePrice;
  double get cost=>days*dailyCost;
  double get net=>gross-cost-current;
  double? get breakPrice=>projected>0?(current+cost)/projected:null;
  double? get breakCost=>days>0?(gross-current)/days:null;
  bool get valid=>days>=0&&days<=3650&&[weight,gain,price,futurePrice,dailyCost,projected,current,gross,cost,net].every((v)=>v.isFinite)&&[weight,price,futurePrice,dailyCost,projected].every((v)=>v>=0);
}
int? targetDays(double weight,double gain,double target){
  if(![weight,gain,target].every((v)=>v.isFinite)||weight<0||target<0)return null;
  if(weight>=target)return 0;
  if(gain<=0)return null;
  final days=(target-weight)/gain;
  return days.isFinite&&days<100000000?days.ceil():null;
}


// Read-only view of forecasts recorded by Web. Never rewrite their audit data.
class ForecastView {
  const ForecastView({required this.id,required this.targetDate,required this.predicted,required this.status,this.actual,this.actualDate});
  final String id,targetDate,status;
  final double predicted;
  final double? actual;
  final String? actualDate;
  double? get error=>actual==null?null:actual!-predicted;
  double? get absolutePercent=>error==null||predicted==0?null:error!.abs()/predicted*100;
}
List<ForecastView> savedForecasts(InventorySnapshot snapshot,String animalId){
  final row=snapshot.records.where((r)=>r['animal_id']==animalId&&r['deleted_at']==null).firstOrNull;
  final payload=row?['payload'];
  final raw=payload is Map?payload['forecasts']:null;
  if(raw is! List)return [];
  final result=<ForecastView>[];
  bool validWeight(Object? v)=>v is num&&v.isFinite&&v>=0;
  bool validDate(Object? v)=>v is String&&RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)&&DateTime.tryParse(v)?.toIso8601String().substring(0,10)==v;
  for(final f in raw.whereType<Map>()){
    if(f['animalId']!=animalId||f['id'] is! String||!validDate(f['targetDate'])||!validWeight(f['predictedWeight']))continue;
    final status=f['status'];
    if(status!='pending'&&status!='evaluated')continue;
    if(status=='evaluated'&&(!validWeight(f['actualWeight'])||!validDate(f['actualDate'])||(f['actualDate'] as String).compareTo(f['targetDate'] as String)<0))continue;
    result.add(ForecastView(id:f['id'] as String,targetDate:f['targetDate'] as String,predicted:(f['predictedWeight'] as num).toDouble(),status:status as String,actual:status=='evaluated'?(f['actualWeight'] as num).toDouble():null,actualDate:status=='evaluated'?f['actualDate'] as String:null));
  }
  return result..sort((a,b)=>b.targetDate.compareTo(a.targetDate));
}
class LotSummary {
  const LotSummary(this.count,this.weighed,this.withGrowth,this.meanWeight,this.meanGain);
  final int count,weighed,withGrowth;
  final double? meanWeight,meanGain;
}
LotSummary summarizeLot(Iterable<InventoryAnimal> animals,String lot){
  final selected=animals.where((a)=>a.active&&a.value('lot')==lot).toList();
  final weights=<double>[],gains=<double>[];
  for(final a in selected){
    final points=weightHistory(a);
    if(points.isNotEmpty)weights.add(points.last.weight);
    final basis=recentGrowth(points);
    if(basis!=null)gains.add(basis.gain);
  }
  double? mean(List<double> v)=>v.isEmpty?null:v.reduce((a,b)=>a+b)/v.length;
  return LotSummary(selected.length,weights.length,gains.length,mean(weights),mean(gains));
}
List<SaleScenario> compareSalePeriods(SaleScenario base,Iterable<int> periods){
  return (periods.toSet().toList()..sort()).map((d)=>SaleScenario(weight:base.weight,gain:base.gain,days:d,price:base.price,futurePrice:base.futurePrice,dailyCost:base.dailyCost)).where((s)=>s.valid).toList();
}
