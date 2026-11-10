import 'package:flutter/material.dart';

final class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tainá'),
              SizedBox(height: 16),
              Text('Preparando o app.'),
            ],
          ),
        ),
      ),
    );
  }
}
