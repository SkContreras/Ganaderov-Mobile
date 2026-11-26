import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/analysis/domain/productive_analysis.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';
void main(){
  test('daily average and recent gain',(){
    final animal=InventoryAnimal(id:'a',fields:{},active:true,statusLabel:'Activo',events:[
      AnimalEvent(type:'weight',date:DateTime(2025,1,1),weight:100),
      AnimalEvent(type:'weight',date:DateTime(2025,2,1),weight:200),
      AnimalEvent(type:'weight',date:DateTime(2025,2,1),weight:220),
      AnimalEvent(type:'weight',date:DateTime(2025,2,11),weight:230),
    ]);
    final points=weightHistory(animal);
    expect(points[1].weight,210);
    expect(recentGrowth(points)!.gain,2);
    expect(recentGrowth(points)!.days,10);
  });
  test('sale net and target',(){
    const s=SaleScenario(weight:300,gain:1,days:30,price:50,futurePrice:50,dailyCost:20);
    expect(s.valid,isTrue);
    expect(s.net,900);
    expect(targetDays(300,1,350),50);
    expect(targetDays(300,0,350),isNull);
  });
}
