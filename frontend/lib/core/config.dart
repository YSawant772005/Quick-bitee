import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_origin_stub.dart' if (dart.library.html) 'web_origin_web.dart';

/// Build-time configuration via --dart-define=API_BASE_URL=...
/// Web deployments may use a same-origin relative path ("/api/v1"); mobile
/// builds must pass an absolute reachable address.
class AppConfig {
  static const String rawApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  static String? _webOrigin;

  static String resolveApiBaseUrl() {
    var base = rawApiBaseUrl;
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.startsWith('/')) {
      assert(kIsWeb, 'Relative API_BASE_URL is only valid on Flutter Web');
      base = '$_webOrigin$base';
    }
    return base;
  }

  /// Called once at startup so relative API paths resolve same-origin on Web.
  static void bindPlatformOrigin() {
    if (kIsWeb) _webOrigin = currentOrigin();
  }

  static String resolveAssetUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/')) {
      if (kIsWeb && _webOrigin != null) return '$_webOrigin$path';
      final base = resolveApiBaseUrl();
      final origin = base.substring(0, base.indexOf('/api/'));
      return '$origin$path';
    }
    return path;
  }
}
