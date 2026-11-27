import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/local_cipher.dart';
void main(){
  test('authenticated encryption binds ciphertext to scope',(){
    final cipher=LocalCipher(Uint8List(32));
    final a=cipher.seal('secret','user-a');
    expect(cipher.open(a,'user-a'),'secret');
    expect(cipher.seal('secret','user-a'),isNot(a));
    expect(()=>cipher.open(a,'user-b'),throwsA(anything));
    expect(()=>LocalCipher(Uint8List.fromList(List.filled(32,1))).open(a,'user-a'),throwsA(anything));
  });
}
