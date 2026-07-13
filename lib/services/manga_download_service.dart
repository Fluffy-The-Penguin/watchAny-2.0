import 'dart:async';
import 'dart:io';
import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/suwayomi_service.dart';
import '../state/app_settings.dart';
import '../state/library_state.dart';
import '../services/log_service.dart';

/// Download status for a manga chapter.
enum MangaDownloadStatus { queued, downloading, paused, completed, failed, cancelled }

/// Represents a manga chapter download task.
class MangaDownloadTask {
  final int mangaId;
  final String mangaTitle;
  final int chapterId;
  final String chapterName;
  final double chapterNumber;

  int totalPages;
  int downloadedPages;
  MangaDownloadStatus status;
  String? saveDirPath;
  double downloadSpeed; // bytes/sec
  String? errorMessage;

  MangaDownloadTask({
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterId,
    required this.chapterName,
    required this.chapterNumber,
    this.totalPages = 0,
    this.downloadedPages = 0,
    this.status = MangaDownloadStatus.queued,
    this.saveDirPath,
    this.downloadSpeed = 0.0,
    this.errorMessage,
  });

  /// Unique ID combining mangaId and chapterId.
  String get id => '${mangaId}_$chapterId';

  double get progress => totalPages > 0 ? downloadedPages / totalPages : 0.0;
}

/// Singleton service that manages the manga chapter download queue.
/// Downloads one chapter at a time; supports pause, cancel, and dismiss.
class MangaDownloadService extends ChangeNotifier {
  static final MangaDownloadService _instance = MangaDownloadService._internal();
  factory MangaDownloadService() => _instance;
  MangaDownloadService._internal();

  final List<MangaDownloadTask> tasks = [];

  bool _isRunning = false;
  CancelableCompleter<void>? _currentDownload;
  bool _paused = false;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Add a chapter download to the queue. If nothing is currently downloading,
  /// starts immediately. Idempotent — duplicate task IDs are ignored.
  void enqueue(MangaDownloadTask task) {
    if (tasks.any((t) => t.id == task.id)) return;
    tasks.add(task);
    notifyListeners();
    _startNextIfIdle();
  }

  /// Cancel a queued or active download. For active, cancels the HTTP ops.
  void cancel(String taskId) {
    final task = _findTask(taskId);
    if (task == null) return;
    if (task.status == MangaDownloadStatus.downloading) {
      _currentDownload?.operation.cancel();
    }
    task.status = MangaDownloadStatus.cancelled;
    // Delete partial download directory synchronously (fire-and-forget style)
    if (task.saveDirPath != null) {
      try { Directory(task.saveDirPath!).deleteSync(recursive: true); } catch (_) {}
    }
    tasks.remove(task);
    notifyListeners();
    _startNextIfIdle();
  }

  /// Dismiss (remove) a completed, failed, or cancelled task from the list.
  void dismiss(String taskId) {
    tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  /// Pause the currently active download (queued tasks keep their place).
  void pause(String taskId) {
    final task = _findTask(taskId);
    if (task == null || task.status != MangaDownloadStatus.downloading) return;
    _paused = true;
    _currentDownload?.operation.cancel();
    task.status = MangaDownloadStatus.paused;
    notifyListeners();
  }

  /// Resume a paused download.
  void resume(String taskId) {
    final task = _findTask(taskId);
    if (task == null || task.status != MangaDownloadStatus.paused) return;
    task.status = MangaDownloadStatus.queued;
    _paused = false;
    notifyListeners();
    _startNextIfIdle();
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  MangaDownloadTask? _findTask(String taskId) {
    try {
      return tasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      return null;
    }
  }

  void _startNextIfIdle() {
    if (_isRunning || _paused) return;
    final nextTask = tasks.firstWhere(
      (t) => t.status == MangaDownloadStatus.queued,
      orElse: () => MangaDownloadTask(
        mangaId: -1, mangaTitle: '', chapterId: -1,
        chapterName: '', chapterNumber: 0,
      ),
    );
    if (nextTask.mangaId == -1) return;
    _downloadChapter(nextTask);
  }

  Future<void> _downloadChapter(MangaDownloadTask task) async {
    _isRunning = true;
    task.status = MangaDownloadStatus.downloading;
    task.downloadedPages = 0;
    notifyListeners();

    final completer = CancelableCompleter<void>();
    _currentDownload = completer;

    completer.operation.then((_) {
      _isRunning = false;
      _startNextIfIdle();
    }, onCancel: () {
      _isRunning = false;
    });

    _doDownload(task, completer);
  }

  Future<void> _doDownload(MangaDownloadTask task, CancelableCompleter<void> completer) async {
    try {
      // 1. Fetch page proxy URLs from Suwayomi
      List<String> pageUrls;
      try {
        pageUrls = await SuwayomiService().getChapterPages(task.chapterId);
      } catch (e) {
        task.status = MangaDownloadStatus.failed;
        task.errorMessage = 'Failed to fetch page list: $e';
        _isRunning = false;
        notifyListeners();
        completer.complete();
        LogService().error('MangaDownload: page fetch failed for chapter ${task.chapterId}', e);
        _startNextIfIdle();
        return;
      }

      if (pageUrls.isEmpty) {
        task.status = MangaDownloadStatus.failed;
        task.errorMessage = 'No pages returned from server';
        _isRunning = false;
        notifyListeners();
        completer.complete();
        _startNextIfIdle();
        return;
      }

      task.totalPages = pageUrls.length;
      notifyListeners();

      // 2. Resolve save directory
      final saveDir = await _resolveSaveDir(task);
      task.saveDirPath = saveDir.path;
      if (!await saveDir.exists()) await saveDir.create(recursive: true);

      // 3. Download each page
      final client = http.Client();
      DateTime speedTimer = DateTime.now();
      int bytesInWindow = 0;

      try {
        for (int i = 0; i < pageUrls.length; i++) {
          if (completer.isCanceled) break;

          final pageFile = File('${saveDir.path}/page_${(i + 1).toString().padLeft(4, '0')}.jpg');

          // Skip already downloaded pages (resume support)
          if (await pageFile.exists() && (await pageFile.length()) > 100) {
            task.downloadedPages = i + 1;
            notifyListeners();
            continue;
          }

          try {
            final response = await client.get(Uri.parse(pageUrls[i])).timeout(const Duration(seconds: 30));
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              await pageFile.writeAsBytes(response.bodyBytes);
              bytesInWindow += response.bodyBytes.length;
            }
          } catch (e) {
            LogService().error('MangaDownload: page $i download error', e);
            // Continue to next page; partial chapters are still usable
          }

          task.downloadedPages = i + 1;

          // Update speed estimate every second
          final now = DateTime.now();
          final elapsed = now.difference(speedTimer).inMilliseconds;
          if (elapsed >= 1000) {
            task.downloadSpeed = (bytesInWindow / elapsed * 1000);
            bytesInWindow = 0;
            speedTimer = now;
          }

          notifyListeners();
        }
      } finally {
        client.close();
      }

      if (completer.isCanceled) {
        _isRunning = false;
        notifyListeners();
        completer.complete();
        return;
      }

      // 4. Mark complete
      task.status = MangaDownloadStatus.completed;
      task.downloadSpeed = 0.0;
      _isRunning = false;

      // 5. Persist to LibraryState so reader knows the chapter is available offline
      LibraryState().markChapterDownloaded(task.mangaId, task.chapterId, task.saveDirPath!);

      notifyListeners();
      completer.complete();
      _startNextIfIdle();
    } catch (e, stack) {
      task.status = MangaDownloadStatus.failed;
      task.errorMessage = e.toString();
      _isRunning = false;
      notifyListeners();
      LogService().error('MangaDownload: unexpected error', e, stack);
      completer.complete();
      _startNextIfIdle();
    }
  }

  /// Resolves the directory where a chapter's pages will be saved.
  /// Path: {basePath}/Manga/{mangaTitle}/Ch {chapterNumber}/
  /// On Android: external storage if available, else app documents dir.
  /// On Desktop: user's Downloads folder via path_provider, else app documents dir.
  Future<Directory> _resolveSaveDir(MangaDownloadTask task) async {
    String basePath = AppSettings().downloadPath;
    if (basePath.isEmpty) {
      if (!kIsWeb && Platform.isAndroid) {
        // Android: prefer external storage (SD card / shared storage)
        Directory? extDir;
        try {
          extDir = await getExternalStorageDirectory();
        } catch (_) {}
        if (extDir != null) {
          basePath = extDir.path;
        } else {
          basePath = (await getApplicationDocumentsDirectory()).path;
        }
      } else {
        // Windows / macOS / Linux: use the system Downloads folder
        Directory? dlDir;
        try {
          dlDir = await getDownloadsDirectory();
        } catch (_) {}
        if (dlDir != null) {
          basePath = dlDir.path;
        } else {
          basePath = (await getApplicationDocumentsDirectory()).path;
        }
      }
    }

    final safeMangaTitle = task.mangaTitle
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final chapterLabel = task.chapterNumber == task.chapterNumber.truncateToDouble()
        ? 'Ch ${task.chapterNumber.toInt()}'
        : 'Ch ${task.chapterNumber}';

    return Directory('$basePath/Manga/$safeMangaTitle/$chapterLabel');
  }
}
