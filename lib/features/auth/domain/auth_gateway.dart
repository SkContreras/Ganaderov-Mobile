import 'package:flutter/foundation.dart';
enum AuthMode { login, register, recovery, reset }
abstract class AuthGateway extends ChangeNotifier {
  bool get signedIn;
  bool get recovering;
  String? get email;
  String? get notice;
  Future<void> login(String email, String password);
  Future<bool> register(String email, String password);
  Future<void> recover(String email);
  Future<void> reset(String password);
  Future<void> social(bool google);
  Future<void> logout();
}
