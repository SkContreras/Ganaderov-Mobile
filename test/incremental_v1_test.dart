import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/sync/incremental_v1.dart';
void main(){
  final snapshot=<String,dynamic>{'ownerId':'r','epoch':null,'cursor':0,'records':[]};
  final change=<String,dynamic>{'revision':1,'kind':'animal','entity_id':'a','deleted':false,'record':{'owner_id':'r','animal_id':'a'}};
  final page=<String,dynamic>{'protocolVersion':1,'status':'ok','epoch':'e','head':1,'nextCursor':1,'hasMore':false,'changes':[change]};
  test('apply without mutating prior snapshot',(){
    final next=applyChangePage(snapshot,page,'r');
    expect(next['cursor'],1);
    expect(next['records'],hasLength(1));
    expect(snapshot['records'],isEmpty);
  });
  test('reject gaps, other ranch and invalid epoch',(){
    expect(()=>applyChangePage(snapshot,{...page,'changes':[{...change,'revision':2}]},'r'),throwsFormatException);
    expect(()=>applyChangePage(snapshot,{...page,'changes':[{...change,'record':{'owner_id':'other','animal_id':'a'}}]},'r'),throwsFormatException);
    final next=applyChangePage(snapshot,page,'r');
    expect(()=>applyChangePage(next,{...page,'epoch':'other'},'r'),throwsFormatException);
  });
  test('physical deletion removes confirmed record',(){
    final next=applyChangePage(snapshot,page,'r');
    final result=applyChangePage(next,{...page,'head':2,'nextCursor':2,'changes':[{...change,'revision':2,'deleted':true,'record':null}]},'r');
    expect(result['records'],isEmpty);
  });
}
