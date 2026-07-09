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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/library_providers.dart';
import 'services/android_background_sync.dart';

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize MediaKit
  MediaKit.ensureInitialized();
  VideoProxyService().start();
  
  final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  if (isDesktop) {
    // Initialize the window manager immediately so the native window shows up instantly
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 400),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
      await windowManager.setResizable(false);
    });
  }

  // Pre-warm SharedPreferences so all subsequent getInstance() calls are instant
  await SharedPreferences.getInstance();

  // Configure image cache boundaries
  final imageCache = PaintingBinding.instance.imageCache;
  if (isDesktop) {
    imageCache.maximumSize = 150;
    imageCache.maximumSizeBytes = 80 * 1024 * 1024; // 80 MB
  } else {
    imageCache.maximumSize = 80;
    imageCache.maximumSizeBytes = 40 * 1024 * 1024; // 40 MB
  }

  final container = ProviderContainer();
  RiverpodContainerHolder.container = container;

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener, WidgetsBindingObserver {
  final NavigationState _navigationState = NavigationState();
  final bool _isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  late Future<void> _initFuture;
  bool _showSetup = false;
  bool _isLoading = true;
  double _savedWidth = 1280.0;
  double _savedHeight = 720.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _savedWidth = prefs.getDouble('window_width') ?? 1280.0;
    _savedHeight = prefs.getDouble('window_height') ?? 720.0;
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

    // 5. Register WorkManager background synchronization for Android devices
    AndroidBackgroundSync().init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _navigationState.removeListener(_handleNavigationModeChange);
    // Stop TorrServer when the app widget is disposed
    TorrServerManager.stop();
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    PaintingBinding.instance.imageCache.clear();
    debugPrint("OS memory pressure signal received. Cleared ImageCache.");
  }

  @override
  void onWindowClose() async {
    if (_isDesktop) {
      try {
        final size = await windowManager.getSize();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('window_width', size.width);
        await prefs.setDouble('window_height', size.height);
      } catch (_) {}

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

  AppMode? _lastTorrMode;

  void _handleNavigationModeChange() {
    if (!_isDesktop && !Platform.isAndroid) return;
    final settings = AppSettings();
    final mode = _navigationState.currentMode;
    if (mode == _lastTorrMode) return;
    _lastTorrMode = mode;

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
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (Widget child, Animation<double> animation) {
          final scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: scaleAnimation,
              child: child,
            ),
          );
        },
        child: _isLoading
            ? BrandSplashScreen(
                key: const ValueKey('splash'),
                initFuture: _initFuture,
                onComplete: () {
                  if (_isDesktop) {
                    // Fire and forget size changes asynchronously so we NEVER block the loading state transition
                    windowManager.setSize(Size(_savedWidth, _savedHeight), animate: true);
                    windowManager.center();
                    
                    // Schedule borders and app reveal after 450ms, guaranteed to run
                    Future.delayed(const Duration(milliseconds: 450), () async {
                      await windowManager.setResizable(true);
                      await windowManager.setHasShadow(true);
                      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
                      await windowManager.setMinimumSize(const Size(360, 500));
                      if (mounted) {
                        setState(() => _isLoading = false);
                      }
                    });
                  } else {
                    setState(() => _isLoading = false);
                  }
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
