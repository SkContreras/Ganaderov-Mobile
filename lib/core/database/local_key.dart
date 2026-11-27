import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'local_cipher.dart';

// Provision only in the foreground, before scheduling the background worker.
// Never silently replace a lost key after the database has been encrypted.
class LocalKey {
  static const _storage=FlutterSecureStorage();
  static const _name='ganaderov.local.aes.v1';
  static Future<LocalCipher?> read()async{
    final key=await _storage.read(key:_name);
    return key==null?null:LocalCipher(base64Decode(key));
  }
  static Future<LocalCipher> provision()async{
    final existing=await read();
    if(existing!=null)return existing;
    final key=LocalCipher.randomBytes(32);
    await _storage.write(key:_name,value:base64Encode(key));
    return LocalCipher(key);
  }
}
