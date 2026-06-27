import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/app_settings.dart';

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
}

class DownloadTask {
  final String id;
  final String hash;
  final int fileIndex;
  final String title;
  final String savePath;
  final String streamUrl;
  int downloadedBytes;
  int totalBytes;
  DownloadStatus status;
  double downloadSpeed; // Bytes per second

  // Anime metadata fields to unify player interfaces
  final int? anilistId;
  final List<String>? titles;
  final int? episodeCount;
  final int? episodeNumber;
  final bool? isMovie;
  final String? mediaJson;
  final String? episodesJson;
  final String? tmdbEpisodesMapJson;

  DownloadTask({
    required this.id,
    required this.hash,
    required this.fileIndex,
    required this.title,
    required this.savePath,
    required this.streamUrl,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.status = DownloadStatus.queued,
    this.downloadSpeed = 0,
    this.anilistId,
    this.titles,
    this.episodeCount,
    this.episodeNumber,
    this.isMovie,
    this.mediaJson,
    this.episodesJson,
    this.tmdbEpisodesMapJson,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hash': hash,
        'fileIndex': fileIndex,
        'title': title,
        'savePath': savePath,
        'streamUrl': streamUrl,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'status': status.index,
        'anilistId': anilistId,
        'titles': titles,
        'episodeCount': episodeCount,
        'episodeNumber': episodeNumber,
        'isMovie': isMovie,
        'mediaJson': mediaJson,
        'episodesJson': episodesJson,
        'tmdbEpisodesMapJson': tmdbEpisodesMapJson,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String,
        hash: json['hash'] as String,
        fileIndex: json['fileIndex'] as int,
        title: json['title'] as String,
        savePath: json['savePath'] as String,
        streamUrl: json['streamUrl'] as String,
        downloadedBytes: json['downloadedBytes'] as int,
        totalBytes: json['totalBytes'] as int,
        status: DownloadStatus.values[json['status'] as int],
        anilistId: json['anilistId'] as int?,
        titles: (json['titles'] as List<dynamic>?)?.map((e) => e as String).toList(),
        episodeCount: json['episodeCount'] as int?,
        episodeNumber: json['episodeNumber'] as int?,
        isMovie: json['isMovie'] as bool?,
        mediaJson: json['mediaJson'] as String?,
        episodesJson: json['episodesJson'] as String?,
        tmdbEpisodesMapJson: json['tmdbEpisodesMapJson'] as String?,
      );
}

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final List<DownloadTask> _tasks = [];
  bool _isLoopRunning = false;
  http.Client? _httpClient;
  StreamSubscription<List<int>>? _currentSubscription;
  IOSink? _currentFileSink;
  DownloadTask? _activeTask;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  DownloadTask? get activeTask => _activeTask;

  File get _dbFile {
    return File('${Directory.current.path}/downloads.json');
  }

  Future<void> init() async {
    await _loadTasks();
    // Start download loop on startup (resumes queued items)
    _startDownloadLoop();
  }

  Future<void> _loadTasks() async {
    try {
      if (await _dbFile.exists()) {
        final content = await _dbFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _tasks.clear();
        for (var item in list) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          // If app closed while downloading, reset to paused/failed
          if (task.status == DownloadStatus.downloading) {
            task.status = DownloadStatus.paused;
          }
          task.downloadSpeed = 0;
          _tasks.add(task);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading download tasks: $e");
    }
  }

  Future<void> _saveTasks() async {
    try {
      final list = _tasks.map((t) => t.toJson()).toList();
      await _dbFile.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint("Error saving download tasks: $e");
    }
  }

  String _cleanFilename(String title) {
    return title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> addDownloadTask({
    required String hash,
    required int fileIndex,
    required String title,
    required String streamUrl,
    int? anilistId,
    List<String>? titles,
    int? episodeCount,
    int? episodeNumber,
    bool? isMovie,
    String? mediaJson,
    String? episodesJson,
    String? tmdbEpisodesMapJson,
  }) async {
    final id = '${hash}_$fileIndex';
    
    // Check if task already exists
    if (_tasks.any((t) => t.id == id)) {
      debugPrint("Task $id already exists in download queue");
      return;
    }

    String baseDir = AppSettings().downloadPath;
    if (baseDir.isEmpty) {
      final homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
      baseDir = '$homeDir/Downloads/watchAny';
    }
    final downloadsDir = Directory(baseDir);
    if (!downloadsDir.existsSync()) {
      await downloadsDir.create(recursive: true);
    }

    // Try parsing extension from URL or use mp4 as fallback
    final cleanedTitle = _cleanFilename(title);
    final savePath = '${downloadsDir.path}/$cleanedTitle';

    final task = DownloadTask(
      id: id,
      hash: hash,
      fileIndex: fileIndex,
      title: title,
      savePath: savePath,
      streamUrl: streamUrl,
      status: DownloadStatus.queued,
      anilistId: anilistId,
      titles: titles,
      episodeCount: episodeCount,
      episodeNumber: episodeNumber,
      isMovie: isMovie,
      mediaJson: mediaJson,
      episodesJson: episodesJson,
      tmdbEpisodesMapJson: tmdbEpisodesMapJson,
    );

    _tasks.add(task);
    await _saveTasks();
    notifyListeners();
    _startDownloadLoop();
  }

  void pauseDownload(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (task.status == DownloadStatus.downloading) {
      _cancelCurrentDownload();
      task.status = DownloadStatus.paused;
      task.downloadSpeed = 0;
      _saveTasks();
      notifyListeners();
      _startDownloadLoop();
    } else if (task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.paused;
      _saveTasks();
      notifyListeners();
    }
  }

  void resumeDownload(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed) {
      task.status = DownloadStatus.queued;
      _saveTasks();
      notifyListeners();
      _startDownloadLoop();
    }
  }

  Future<void> removeDownload(String taskId, {bool deleteFile = false}) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _tasks[index];
      if (task.status == DownloadStatus.downloading) {
        _cancelCurrentDownload();
      }
      _tasks.removeAt(index);
      await _saveTasks();
      notifyListeners();

      if (deleteFile) {
        try {
          final file = File(task.savePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint("Failed to delete local download file: $e");
        }
      }
      _startDownloadLoop();
    }
  }

  void _cancelCurrentDownload() {
    _currentSubscription?.cancel();
    _currentSubscription = null;
    _currentFileSink?.close();
    _currentFileSink = null;
    _httpClient?.close();
    _httpClient = null;
    _activeTask = null;
  }

  void _startDownloadLoop() {
    if (_isLoopRunning) return;
    _isLoopRunning = true;
    _runNextTask();
  }

  Future<void> _runNextTask() async {
    // Find next queued task
    final queuedTasks = _tasks.where((t) => t.status == DownloadStatus.queued).toList();
    if (queuedTasks.isEmpty) {
      _isLoopRunning = false;
      return;
    }

    final task = queuedTasks.first;
    _activeTask = task;
    task.status = DownloadStatus.downloading;
    notifyListeners();

    Timer? speedTimer;
    try {
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(task.streamUrl));
      
      // Support resume
      if (task.downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=${task.downloadedBytes}-';
      }

      final response = await _httpClient!.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('Server returned status code: ${response.statusCode}');
      }

      // If range request was accepted, file matches length. If server returned 200 instead of 206, restart download.
      if (response.statusCode == 200) {
        task.downloadedBytes = 0;
      }

      if (task.totalBytes == 0 || response.statusCode == 200) {
        task.totalBytes = (response.contentLength ?? 0) + task.downloadedBytes;
      }

      final file = File(task.savePath);
      // Open in append mode if resuming, else write from scratch
      _currentFileSink = file.openWrite(
        mode: response.statusCode == 206 ? FileMode.append : FileMode.write,
      );

      int bytesSinceLastReport = 0;
      DateTime lastTime = DateTime.now();

      speedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (task.status != DownloadStatus.downloading) {
          timer.cancel();
          return;
        }
        final now = DateTime.now();
        final ms = now.difference(lastTime).inMilliseconds;
        if (ms > 0) {
          task.downloadSpeed = (bytesSinceLastReport * 1000) / ms;
        }
        bytesSinceLastReport = 0;
        lastTime = now;
        _saveTasks();
        notifyListeners();
      });

      final completer = Completer<void>();

      _currentSubscription = response.stream.listen(
        (chunk) {
          _currentFileSink?.add(chunk);
          task.downloadedBytes += chunk.length;
          bytesSinceLastReport += chunk.length;
        },
        onError: (err) {
          speedTimer?.cancel();
          completer.completeError(err);
        },
        onDone: () {
          speedTimer?.cancel();
          completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
      
      // Clean shutdown of current writers
      await _currentFileSink?.close();
      _currentFileSink = null;
      _httpClient?.close();
      _httpClient = null;
      _activeTask = null;

      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.completed;
        task.downloadSpeed = 0;
        await _saveTasks();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Download task ${task.id} failed: $e");
      speedTimer?.cancel();
      _cancelCurrentDownload();
      
      task.status = DownloadStatus.failed;
      task.downloadSpeed = 0;
      await _saveTasks();
      notifyListeners();
    }

    // Run next task in queue
    _runNextTask();
  }
}
