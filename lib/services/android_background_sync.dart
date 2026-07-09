import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../state/library_state.dart';
import '../state/app_settings.dart';

const String syncTaskName = "com.watchany.background_sync";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("WorkManager background sync task started: $task");
    try {
      // 1. Initialize configurations and SQLite databases
      await AppSettings().init();
      await LibraryState().init();
      
      // 2. Perform synchronization
      await LibraryState().updateNotificationCount(force: true);
      debugPrint("WorkManager background sync completed successfully.");
      return true;
    } catch (e) {
      debugPrint("WorkManager background sync task failed: $e");
      return false;
    }
  });
}

class AndroidBackgroundSync {
  static final AndroidBackgroundSync _instance = AndroidBackgroundSync._internal();
  factory AndroidBackgroundSync() => _instance;
  AndroidBackgroundSync._internal();

  Future<void> init() async {
    // Only register WorkManager on Android!
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      // Register a periodic background task firing every 6 hours.
      // Constraints: requires unmetered Wi-Fi and device to be charging.
      await Workmanager().registerPeriodicTask(
        "watchany-periodic-sync",
        syncTaskName,
        frequency: const Duration(hours: 6),
        constraints: Constraints(
          networkType: NetworkType.unmetered,
          requiresCharging: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
      debugPrint("WorkManager periodic sync registered.");
    }
  }
}
