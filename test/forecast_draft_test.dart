import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/analysis/domain/productive_analysis.dart';
void main(){
 test('forecast validates and encodes baseline inputs only',(){
  final d=ForecastDraft(baselineWeight:250,baselineDate:DateTime(2026,1,1),gain:.8,days:60);
  expect(d.valid,isTrue);expect(d.predicted,298);expect(d.changes('a')['predictedWeight'],isNull);
 });
 test('negative projected weight rejected',(){expect(ForecastDraft(baselineWeight:10,baselineDate:DateTime(2026,1,1),gain:-2,days:30).valid,isFalse);});
}
