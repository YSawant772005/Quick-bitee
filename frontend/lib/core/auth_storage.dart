import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token storage: secure storage on mobile, in-memory only on Web (a page
/// reload therefore requires signing in again, per assignment).
class AuthStorage {
  AuthStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'quickbite_access_token';
  String? _memoryToken;
  bool _isWeb = false;

  void markWeb() => _isWeb = true;

  Future<void> saveToken(String token) async {
    _memoryToken = token;
    if (!_isWeb) {
      await _storage.write(key: _key, value: token);
    }
  }

  Future<String?> readToken() async {
    if (_isWeb) return _memoryToken;
    return _memoryToken ??= await _storage.read(key: _key);
  }

  Future<void> clear() async {
    _memoryToken = null;
    if (!_isWeb) {
      await _storage.delete(key: _key);
    }
  }
}
