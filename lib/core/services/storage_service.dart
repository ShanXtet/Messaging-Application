import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();
  
  // Auth keys
  static const String _authTokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _userNameKey = 'user_name';

  // Token management
  static Future<void> setAuthToken(String token) async {
    await _storage.write(key: _authTokenKey, value: token);
  }

  static Future<String?> getAuthToken() async {
    return await _storage.read(key: _authTokenKey);
  }

  static Future<void> clearAuthToken() async {
    await _storage.delete(key: _authTokenKey);
  }

  // User data management
  static Future<void> setUserData({
    required String userId,
    required String email,
    required String name,
  }) async {
    await Future.wait([
      _storage.write(key: _userIdKey, value: userId),
      _storage.write(key: _userEmailKey, value: email),
      _storage.write(key: _userNameKey, value: name),
    ]);
  }

  static Future<Map<String, String?>> getUserData() async {
    final userId = await _storage.read(key: _userIdKey);
    final email = await _storage.read(key: _userEmailKey);
    final name = await _storage.read(key: _userNameKey);
    
    return {
      'userId': userId,
      'email': email,
      'name': name,
    };
  }

  static Future<void> clearUserData() async {
    await Future.wait([
      _storage.delete(key: _userIdKey),
      _storage.delete(key: _userEmailKey),
      _storage.delete(key: _userNameKey),
    ]);
  }

  // Clear all data (logout)
  static Future<void> clearAll() async {
    await Future.wait([
      clearAuthToken(),
      clearUserData(),
    ]);
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }
}
