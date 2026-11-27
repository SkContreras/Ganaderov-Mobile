import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/local_cipher.dart';
void main(){
 test('account keys are deterministic and separated',(){
  final root=LocalCipher(Uint8List(32));
  final sealed=root.forAccount('a').seal('pending','scope');
  expect(root.forAccount('a').open(sealed,'scope'),'pending');
  expect(()=>root.forAccount('b').open(sealed,'scope'),throwsA(anything));
 });
}
