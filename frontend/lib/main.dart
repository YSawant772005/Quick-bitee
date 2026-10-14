import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config.dart';
import 'state/auth_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.bindPlatformOrigin();
  final container = ProviderContainer();
  container.read(apiClientProvider).onUnauthorized = () {
    container.read(authControllerProvider.notifier).handleUnauthorized();
  };
  runApp(UncontrolledProviderScope(container: container, child: const QuickBiteApp()));
}
