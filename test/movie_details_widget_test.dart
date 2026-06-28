import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_any/screens/movies_details_page.dart';
import 'package:watch_any/services/stremio_addon_service.dart';
import 'package:watch_any/state/navigation_state.dart';

void main() {
  testWidgets('Test MovieDetailsPage loading meta', (WidgetTester tester) async {
    // Disable HTTP overrides to allow real network requests
    HttpOverrides.global = null;
    
    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});
    
    // Initialize service and install Porn Tube addon
    final service = StremioAddonService();
    await service.init();
    try {
      await service.installAddon('https://dirty-pink.ers.pw/manifest.json');
      print('Addon installed successfully');
    } catch (e) {
      print('Addon install failed: $e');
    }
    
    final navigationState = NavigationState();
    
    await tester.pumpWidget(
      MaterialApp(
        home: MovieDetailsPage(
          movieId: 'movie:porndb:11123151',
          navigationState: navigationState,
        ),
      ),
    );

    // Let async tasks run
    print('Pumped page. Waiting for metadata query...');
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    print('Test finished.');
  });
}
