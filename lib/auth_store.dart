import 'package:flutter_secure_storage/flutter_secure_storage.dart'; //ပေးပို့လိုသော data များအား encrypt ပြုလုပ်ရန်

class AuthStore {
  static const _key = 'auth_token';
  static const _storage = FlutterSecureStorage(); //instantiate FlutterSecureStorage

  static Future<void> setToken(String token) =>
      _storage.write(key: _key, value: token);

  static Future<String?> getToken() => _storage.read(key: _key);

  static Future<void> clear() => _storage.delete(key: _key);
}
