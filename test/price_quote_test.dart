import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/analysis/domain/productive_analysis.dart';
void main(){
 test('quote checks range and category threshold',(){
  const q=PriceQuote(id:'a',category:'Becerro',date:'2026-01-01',minimum:50,average:60,maximum:70,nextThreshold:300,nextAverage:55);
  expect(q.valid,isTrue);expect(q.priceAt(299),60);expect(q.priceAt(300),55);expect(PriceQuote.fromJson(q.toJson()).valid,isTrue);
 });
 test('empty lot has no invented income',(){
  const q=PriceQuote(id:'a',category:'Becerro',date:'2026-01-01',minimum:50,average:60,maximum:70);
  final r=evaluateLot([],'A',30,q,10);expect(r.included,0);expect(r.net,0);
 });
}
