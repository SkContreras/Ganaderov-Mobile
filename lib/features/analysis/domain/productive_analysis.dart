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
