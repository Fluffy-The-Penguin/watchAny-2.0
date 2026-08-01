import 'dart:async';

/// Stub BackupService - background backup exports have been disabled to eliminate disk I/O lag.
class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  void backupAllDebounced() {
    // Disabled to prevent background disk I/O lag
  }

  Future<void> backupAll() async {
    // Disabled to prevent background disk I/O lag
  }

  Future<void> restoreAll() async {
    // Disabled
  }

  Future<void> restoreFromPath(String folderPath) async {
    // Disabled
  }
}
