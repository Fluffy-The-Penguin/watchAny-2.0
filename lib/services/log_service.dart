import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  File? _logFile;
  final List<String> _inMemoryLogs = [];
  static const int _maxInMemoryLogs = 1000;
  static const int _maxLogFileSize = 5 * 1024 * 1024; // 5 MB

  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _logFile = File('${dir.path}/watch_any.log');
      
      // Rotate log file if it exceeds the limit
      if (await _logFile!.exists() && await _logFile!.length() > _maxLogFileSize) {
        final backupFile = File('${dir.path}/watch_any_old.log');
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        await _logFile!.rename(backupFile.path);
        _logFile = File('${dir.path}/watch_any.log');
      }

      // Log startup
      info('--- APP STARTED ---');
    } catch (e, stackTrace) {
      debugPrint('Error initializing LogService: $e\n$stackTrace');
    }
  }

  void log(String message, {String level = 'INFO', dynamic error, StackTrace? stackTrace}) {
    final timestamp = DateTime.now().toIso8601String();
    var logLine = '[$timestamp] [$level] $message';
    if (error != null) {
      logLine += '\nError: $error';
    }
    if (stackTrace != null) {
      logLine += '\nStackTrace:\n$stackTrace';
    }

    // Print to console in debug mode
    if (kDebugMode) {
      debugPrint(logLine);
    }

    // Add to in-memory buffer
    _inMemoryLogs.add(logLine);
    if (_inMemoryLogs.length > _maxInMemoryLogs) {
      _inMemoryLogs.removeAt(0);
    }

    final file = _logFile;
    if (file != null) {
      () async {
        try {
          await file.writeAsString('$logLine\n', mode: FileMode.writeOnlyAppend);
        } catch (e) {
          debugPrint('Failed to write to log file: $e');
        }
      }();
    }
  }

  void info(String message) => log(message, level: 'INFO');
  void warning(String message) => log(message, level: 'WARNING');
  void error(String message, [dynamic err, StackTrace? st]) => log(message, level: 'ERROR', error: err, stackTrace: st);

  List<String> getInMemoryLogs() => List.unmodifiable(_inMemoryLogs);

  Future<File?> getLogFile() async {
    if (_logFile == null) {
      final dir = await getApplicationSupportDirectory();
      _logFile = File('${dir.path}/watch_any.log');
    }
    return _logFile;
  }

  Future<void> clearLogs() async {
    _inMemoryLogs.clear();
    final file = _logFile;
    if (file != null && await file.exists()) {
      try {
        await file.writeAsString('', mode: FileMode.write);
      } catch (_) {}
    }
  }
}
