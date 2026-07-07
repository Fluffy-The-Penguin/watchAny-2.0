import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'state/player_state.dart' as ps;
import 'services/video_proxy_service.dart';
import 'screens/shell_layout.dart';
import 'screens/setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/brand_splash_screen.dart';

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
  VideoProxyService().start();
  
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
  bool _isLoading = true;

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
      // Dispose the media player BEFORE destroying the window to prevent
      // native mpv null-dereference crash (0x10 offset access after destroy).
      try {
        ps.PlayerState().stopPlayback();
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
      builder: (context, child) {
        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
              if (!_isDesktop) return KeyEventResult.ignored;
              windowManager.isFullScreen().then((isFS) {
                windowManager.setFullScreen(!isFS);
              });
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: child ?? const SizedBox(),
        );
      },
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: _isLoading
            ? BrandSplashScreen(
                key: const ValueKey('splash'),
                initFuture: _initFuture,
                onComplete: () {
                  setState(() => _isLoading = false);
                },
              )
            : (_showSetup || !AppSettings().setupCompleted)
                ? SetupScreen(
                    key: const ValueKey('setup'),
                    onSetupComplete: () {
                      setState(() => _showSetup = false);
                      // Re-sync TorrServer after setup
                      _handleNavigationModeChange();
                    },
                  )
                : ShellLayout(
                    key: const ValueKey('shell'),
                    navigationState: _navigationState,
                  ),
      ),
    );
  }
}
