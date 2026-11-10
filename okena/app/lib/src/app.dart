import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_app/src/design_system/design_system.dart';

final class OkenaApp extends StatelessWidget {
  const OkenaApp({required this.router, super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tainá',
      debugShowCheckedModeBanner: false,
      theme: TainaTheme.data,
      routerConfig: router,
    );
  }
}
