import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'shared/theme.dart';

class QuickBiteApp extends ConsumerStatefulWidget {
  const QuickBiteApp({super.key});

  @override
  ConsumerState<QuickBiteApp> createState() => _QuickBiteAppState();
}

class _QuickBiteAppState extends ConsumerState<QuickBiteApp> {
  late final AuthRefresher _refresher;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _refresher = AuthRefresher(ref);
    _router = buildRouter(_refresher);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'QuickBite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
    );
  }
}
