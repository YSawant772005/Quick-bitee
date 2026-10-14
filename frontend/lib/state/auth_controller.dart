import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/auth_storage.dart';
import '../core/config.dart';
import '../models/models.dart';

final authStorageProvider = Provider<AuthStorage>((ref) {
  final storage = AuthStorage();
  if (kIsWeb) storage.markWeb();
  return storage;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: AppConfig.resolveApiBaseUrl());
});

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class SignedOut extends AuthState {
  const SignedOut();
}

class SignedIn extends AuthState {
  const SignedIn(this.user);
  final User user;
}

class AuthController extends Notifier<AuthState> {
  AuthStorage get _storage => ref.read(authStorageProvider);
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  AuthState build() {
    _restore();
    return const AuthUnknown();
  }

  Future<void> _restore() async {
    final token = await _storage.readToken();
    if (token == null) {
      state = const SignedOut();
      return;
    }
    _api.token = token;
    try {
      state = SignedIn(await _api.me());
    } on ApiException catch (e) {
      if (e.isExpiredToken) {
        await logout();
      } else {
        state = const SignedOut();
      }
    }
  }

  Future<void> login({required String email, required String password}) async {
    final session = await _api.login(email: email, password: password);
    await _storage.saveToken(session.accessToken);
    _api.token = session.accessToken;
    state = SignedIn(session.user);
  }

  Future<void> logout() async {
    await _storage.clear();
    _api.token = null;
    state = const SignedOut();
  }

  void handleUnauthorized() {
    if (state is! SignedOut) {
      _storage.clear();
      _api.token = null;
      state = const SignedOut();
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
