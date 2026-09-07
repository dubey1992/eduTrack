import 'package:flutter/material.dart';

/// Shown once at startup while the auth session is being restored from
/// on-device storage.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
