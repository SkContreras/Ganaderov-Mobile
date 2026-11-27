import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/sync/manual_resolution.dart';
void main(){
 test('new UUID and selected fields only',(){
  final op=<String,dynamic>{'action':'animal.update','operationId':'old','changes':{'fields':{'name':'Luna','color':'Negro'}}};
  final remote=<String,dynamic>{'revision':2,'data':{'name':'Sol','color':'Blanco'}};
  final next=replacementOperation(op,remote,remote,['name'],'new','stamp');
  expect(next['changes'],{'fields':{'name':'Luna'}});expect(next['baseRevision'],2);expect(next['operationId'],'new');
  expect(()=>replacementOperation(op,remote,{...remote,'revision':3},['name'],'new','stamp'),throwsStateError);
 });
}
