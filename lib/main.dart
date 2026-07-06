import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'services/torrserver_manager.dart';
import 'services/extension_service.dart';
import 'services/download_service.dart';
import 'services/backup_service.dart';
import 'state/navigation_state.dart';
import 'state/app_settings.dart';
import 'state/library_state.dart';
import 'state/anilist_auth_state.dart';
import 'screens/shell_layout.dart';
import 'screens/setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  if (isDesktop) {
    // Initialize the window manager immediately so the native window shows up instantly
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
  late Future<void> _initFuture;
  bool _showSetup = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeApp();
    if (_isDesktop) {
      windowManager.addListener(this);
    }
    _navigationState.addListener(_handleNavigationModeChange);
    // Sync the TorrServer state with the initial navigation mode
    _handleNavigationModeChange();
  }

  Future<void> _initializeApp() async {
    // 1. Initial SharedPreferences load
    final prefs = await SharedPreferences.getInstance();
    final bool hasLocalLibrary = prefs.getString('library_items') != null;
    
    // Restore backups ONLY if there is no local database (saves massive redundant I/O on normal boots)
    if (!hasLocalLibrary) {
      await BackupService().restoreAll();
    }

    // 2. Load configurations and parse databases concurrently
    await Future.wait([
      AppSettings().init(),
      AnilistAuthState().init(),
      LibraryState().init(),
      DownloadService().init(),
    ]);

    // 3. Register change listeners for debounced background exports
    AppSettings().addListener(() {
      BackupService().backupAllDebounced();
    });
    LibraryState().addListener(() {
      BackupService().backupAllDebounced();
    });

    // 4. Initialize ExtensionService early to load local extensions in the background
    ExtensionService().init();
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _navigationState.removeListener(_handleNavigationModeChange);
    // Stop TorrServer when the app widget is disposed
    TorrServerManager.stop();
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
    if (!_isDesktop && !Platform.isAndroid) return;
    final settings = AppSettings();
    final mode = _navigationState.currentMode;
    // Only start TorrServer if anime or movies section is enabled and currently active
    final needsTorr = (mode == AppMode.anime && settings.isModeEnabled(AppMode.anime)) ||
                      (mode == AppMode.movies && settings.isModeEnabled(AppMode.movies));
    if (needsTorr) {
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
      home: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (_showSetup || !AppSettings().setupCompleted) {
              return SetupScreen(
                onSetupComplete: () {
                  setState(() => _showSetup = false);
                  // Re-sync TorrServer after setup
                  _handleNavigationModeChange();
                },
              );
            }
            return ShellLayout(navigationState: _navigationState);
          }
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'watchAny',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  SizedBox(height: 24.0),
                  SizedBox(
                    width: 32.0,
                    height: 32.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
