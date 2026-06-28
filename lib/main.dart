import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'services/torrserver_manager.dart';
import 'services/extension_service.dart';
import 'services/download_service.dart';
import 'state/navigation_state.dart';
import 'state/app_settings.dart';
import 'state/library_state.dart';
import 'screens/shell_layout.dart';

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize MediaKit
  MediaKit.ensureInitialized();
  
  // Initialize Download Service
  await DownloadService().init();
  
  // Load persisted app settings (smooth scroll etc.)
  await AppSettings().init();
  
  // Initialize Library state
  await LibraryState().init();
  
  // Initialize ExtensionService early to load local extensions on startup
  ExtensionService().init();
  
  final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  if (isDesktop) {
    // Start TorrServer sidecar
    TorrServerManager.start();
    
    // Initialize the window manager
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(360, 500),
      center: true,
      backgroundColor: Colors.black,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  final NavigationState _navigationState = NavigationState();
  final bool _isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
    }
    _navigationState.addListener(_handleNavigationModeChange);
    // Sync the TorrServer state with the initial navigation mode
    _handleNavigationModeChange();
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _navigationState.removeListener(_handleNavigationModeChange);
    // Stop TorrServer when the app widget is disposed
    if (_isDesktop) {
      TorrServerManager.stop();
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_isDesktop) {
      try {
        await windowManager.hide();
      } catch (_) {}
      await TorrServerManager.stop();
      try {
        await windowManager.destroy();
      } catch (_) {}
    }
  }

  void _handleNavigationModeChange() {
    if (!_isDesktop) return;
    if (_navigationState.currentMode == AppMode.anime || _navigationState.currentMode == AppMode.movies) {
      TorrServerManager.start();
    } else {
      TorrServerManager.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'watchAny 2.0',
      scrollBehavior: MyCustomScrollBehavior(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white70,
          surface: Colors.black,
        ),
        useMaterial3: true,
      ),
      home: ShellLayout(navigationState: _navigationState),
    );
  }
}
