import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class LocalCipher {
  LocalCipher(Uint8List key):_key=Uint8List.fromList(key){
    if(key.length!=32)throw ArgumentError('Invalid key length');
  }
  final Uint8List _key;
  static const prefix='gcm1:';
  static const accountPrefix='gcm2:';
  LocalCipher forAccount(String account){
    final mac=HMac(SHA256Digest(),64)..init(KeyParameter(_key));
    return LocalCipher(mac.process(Uint8List.fromList(utf8.encode('ganaderov/account/v2:$account'))));
  }
  static Uint8List randomBytes(int length){
    final random=Random.secure();
    return Uint8List.fromList(List.generate(length,(_)=>random.nextInt(256)));
  }
  String seal(String text,String scope){
    final nonce=randomBytes(12);
    final cipher=GCMBlockCipher(AESEngine())..init(true,AEADParameters(KeyParameter(_key),128,nonce,Uint8List.fromList(utf8.encode(scope))));
    return prefix+base64Encode([...nonce,...cipher.process(Uint8List.fromList(utf8.encode(text)))]);
  }
  String open(String text,String scope){
    if(!text.startsWith(prefix))throw const FormatException('Unencrypted record');
    final data=base64Decode(text.substring(prefix.length));
    if(data.length<28)throw const FormatException('Invalid encrypted record');
    final cipher=GCMBlockCipher(AESEngine())..init(false,AEADParameters(KeyParameter(_key),128,Uint8List.sublistView(data,0,12),Uint8List.fromList(utf8.encode(scope))));
    return utf8.decode(cipher.process(Uint8List.sublistView(data,12)));
  }
}
