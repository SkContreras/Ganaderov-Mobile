import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/analysis/domain/productive_analysis.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';
void main(){
  test('lot excludes archived and missing measurements',(){
    final animals=[
      InventoryAnimal(id:'a',fields:{'lot':'L'},active:true,statusLabel:'Activo',events:[AnimalEvent(type:'weight',date:DateTime(2025,1,1),weight:300)]),
      const InventoryAnimal(id:'b',fields:{'lot':'L'},active:true,statusLabel:'Activo',events:[]),
      const InventoryAnimal(id:'c',fields:{'lot':'L'},active:false,statusLabel:'Baja',events:[]),
    ];
    final s=summarizeLot(animals,'L');
    expect(s.count,2);expect(s.weighed,1);expect(s.meanWeight,300);expect(s.meanGain,isNull);
  });
  test('forecast zero prediction has no percentage',(){
    const s=InventorySnapshot(status:'active',records:[{'animal_id':'a','payload':{'forecasts':[{'id':'f','animalId':'a','targetDate':'2025-01-01','predictedWeight':0,'status':'evaluated','actualDate':'2025-01-02','actualWeight':10}]}}]);
    final f=savedForecasts(s,'a').single;
    expect(f.error,10);expect(f.absolutePercent,isNull);
  });
  test('comparison excludes impossible negative projection',(){
    const s=SaleScenario(weight:100,gain:-2,days:10,price:50,futurePrice:50,dailyCost:20);
    expect(compareSalePeriods(s,[30,60,30]).map((e)=>e.days),[30]);
  });
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
