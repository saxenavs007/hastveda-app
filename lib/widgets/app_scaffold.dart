import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import './app_navigation.dart';

class AppScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppScaffold({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      // Ensure content is not hidden behind system navigation
      body: SafeArea(
        bottom: false, // Bottom nav handles its own safe area
        child: navigationShell,
      ),
      bottomNavigationBar: AppNavigation(navigationShell: navigationShell),
    );
  }
}
