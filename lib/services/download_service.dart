import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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

  // Anime / Movies / TV metadata fields to unify player interfaces
  final int? anilistId;
  final List<String>? titles;
  final int? episodeCount;
  final int? episodeNumber;
  final int? season;
  final bool? isMovie;
  final String? mediaJson;
  final String? episodesJson;
  final Map<String, String>? headers;

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
    this.season,
    this.isMovie,
    this.mediaJson,
    this.episodesJson,
    this.headers,
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
        'season': season,
        'isMovie': isMovie,
        'mediaJson': mediaJson,
        'episodesJson': episodesJson,
        'headers': headers,
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
        season: json['season'] as int?,
        isMovie: json['isMovie'] as bool?,
        mediaJson: json['mediaJson'] as String?,
        episodesJson: json['episodesJson'] as String?,
        headers: (json['headers'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())),
      );
}

class _ActiveWorker {
  final http.Client client;
  final StreamSubscription<List<int>> subscription;
  final IOSink fileSink;
  final Timer speedTimer;

  _ActiveWorker({
    required this.client,
    required this.subscription,
    required this.fileSink,
    required this.speedTimer,
  });

  void cancel() {
    speedTimer.cancel();
    subscription.cancel();
    fileSink.close();
    client.close();
  }
}

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final List<DownloadTask> _tasks = [];
  final Map<String, _ActiveWorker> _activeWorkers = {};
  bool _hasUnseenCompletions = false;

  bool get hasUnseenCompletions => _hasUnseenCompletions;
  bool get isDownloading => _tasks.any((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued);
  bool get hasFailed => _tasks.any((t) => t.status == DownloadStatus.failed);
  int get activeDownloadingCount => _tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued).length;

  void clearUnseenCompletions() {
    if (_hasUnseenCompletions) {
      _hasUnseenCompletions = false;
      notifyListeners();
    }
  }

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  DownloadTask? get activeTask {
    for (var t in _tasks) {
      if (t.status == DownloadStatus.downloading) return t;
    }
    return _tasks.isNotEmpty ? _tasks.first : null;
  }

  Future<File> get _dbFile async {
    final dir = await getApplicationDocumentsDirectory();
    final newFile = File('${dir.path}/downloads.json');
    final legacyFile = File('${Directory.current.path}/downloads.json');
    if (await legacyFile.exists() && !await newFile.exists()) {
      try {
        await legacyFile.copy(newFile.path);
        await legacyFile.delete();
      } catch (e) {
        debugPrint("Error migrating downloads database: $e");
      }
    }
    return newFile;
  }

  Future<void> init() async {
    await _loadTasks();
    _processQueue();
  }

  Future<void> _loadTasks() async {
    try {
      final file = await _dbFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _tasks.clear();
        for (var item in list) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          if (task.status == DownloadStatus.downloading) {
            task.status = DownloadStatus.queued;
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
      final file = await _dbFile;
      final list = _tasks.map((t) => t.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
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
    int? season,
    bool? isMovie,
    String? mediaJson,
    String? episodesJson,
    Map<String, String>? headers,
  }) async {
    final id = '${hash}_$fileIndex';
    
    if (_tasks.any((t) => t.id == id)) {
      debugPrint("Task $id already exists in download queue");
      return;
    }

    final baseDir = await getEffectiveDownloadPath();
    final downloadsDir = Directory(baseDir);
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }

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
      season: season,
      isMovie: isMovie,
      mediaJson: mediaJson,
      episodesJson: episodesJson,
      headers: headers,
    );

    _tasks.add(task);
    await _saveTasks();
    notifyListeners();
    _processQueue();
  }

  void pauseDownload(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = _tasks[index];
    if (task.status == DownloadStatus.downloading) {
      _stopWorker(taskId);
      task.status = DownloadStatus.paused;
      task.downloadSpeed = 0;
      _saveTasks();
      notifyListeners();
      _processQueue();
    } else if (task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.paused;
      _saveTasks();
      notifyListeners();
    }
  }

  void resumeDownload(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = _tasks[index];
    if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed) {
      task.status = DownloadStatus.queued;
      _saveTasks();
      notifyListeners();
      _processQueue();
    }
  }

  Future<void> removeDownload(String taskId, {bool deleteFile = false}) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _tasks[index];
      if (task.status == DownloadStatus.downloading) {
        _stopWorker(taskId);
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
      _processQueue();
    }
  }

  Future<void> removeAllDownloads({bool deleteFiles = true}) async {
    final taskIds = _tasks.map((t) => t.id).toList();
    for (final id in taskIds) {
      await removeDownload(id, deleteFile: deleteFiles);
    }
  }

  Future<void> removeCompletedDownloads({bool deleteFiles = true}) async {
    final completedIds = _tasks.where((t) => t.status == DownloadStatus.completed).map((t) => t.id).toList();
    for (final id in completedIds) {
      await removeDownload(id, deleteFile: deleteFiles);
    }
  }

  void _stopWorker(String taskId) {
    final worker = _activeWorkers.remove(taskId);
    worker?.cancel();
  }

  void _processQueue() {
    final maxConcurrent = AppSettings().maxConcurrentDownloads.clamp(1, 10);
    final currentlyDownloading = _tasks.where((t) => t.status == DownloadStatus.downloading).length;
    int availableSlots = maxConcurrent - currentlyDownloading;

    if (availableSlots <= 0) return;

    final queuedTasks = _tasks.where((t) => t.status == DownloadStatus.queued).toList();
    for (var task in queuedTasks) {
      if (availableSlots <= 0) break;
      if (_activeWorkers.containsKey(task.id)) continue;

      task.status = DownloadStatus.downloading;
      availableSlots--;
      _startWorkerForTask(task);
    }
    notifyListeners();
  }

  Future<void> _startWorkerForTask(DownloadTask task) async {
    Timer? speedTimer;
    http.Client? client;
    IOSink? fileSink;
    StreamSubscription<List<int>>? subscription;

    try {
      client = http.Client();
      final request = http.Request('GET', Uri.parse(task.streamUrl));

      if (task.headers != null) {
        request.headers.addAll(task.headers!);
      }
      if (task.downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=${task.downloadedBytes}-';
      }

      final response = await client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('Server returned status code: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        task.downloadedBytes = 0;
      }

      if (task.totalBytes == 0 || response.statusCode == 200) {
        task.totalBytes = (response.contentLength ?? 0) + task.downloadedBytes;
      }

      final file = File(task.savePath);
      fileSink = file.openWrite(
        mode: response.statusCode == 206 ? FileMode.append : FileMode.write,
      );

      int bytesSinceLastReport = 0;
      final List<int> sampleBytes = [];
      final List<int> sampleMs = [];
      DateTime lastTime = DateTime.now();

      speedTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (task.status != DownloadStatus.downloading) {
          timer.cancel();
          return;
        }
        final now = DateTime.now();
        final ms = max(1, now.difference(lastTime).inMilliseconds);
        lastTime = now;

        sampleBytes.add(bytesSinceLastReport);
        sampleMs.add(ms);
        bytesSinceLastReport = 0;

        if (sampleBytes.length > 4) {
          sampleBytes.removeAt(0);
          sampleMs.removeAt(0);
        }

        final totalBytes = sampleBytes.reduce((a, b) => a + b);
        final totalMs = sampleMs.reduce((a, b) => a + b);

        if (totalMs > 0) {
          task.downloadSpeed = (totalBytes * 1000.0) / totalMs;
        }

        _saveTasks();
        notifyListeners();
      });

      final completer = Completer<void>();

      subscription = response.stream.listen(
        (chunk) {
          fileSink?.add(chunk);
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

      _activeWorkers[task.id] = _ActiveWorker(
        client: client,
        subscription: subscription,
        fileSink: fileSink,
        speedTimer: speedTimer,
      );

      await completer.future;

      _activeWorkers.remove(task.id);
      await fileSink.close();
      client.close();

      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.completed;
        task.downloadSpeed = 0;
        _hasUnseenCompletions = true;
        await _saveTasks();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Download task ${task.id} failed: $e");
      speedTimer?.cancel();
      _stopWorker(task.id);

      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.failed;
        task.downloadSpeed = 0;
        await _saveTasks();
        notifyListeners();
      }
    }

    _processQueue();
  }

  Future<String> getEffectiveDownloadPath() async {
    String baseDir = AppSettings().downloadPath;
    if (baseDir.isNotEmpty) {
      final dir = Directory(baseDir);
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return baseDir;
      } catch (e) {
        debugPrint("Error accessing custom download path $baseDir: $e");
      }
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final path = '${extDir.path}/watchAny';
          final dir = Directory(path);
          if (!await dir.exists()) await dir.create(recursive: true);
          return path;
        }
      } catch (_) {}
      const publicDir = '/storage/emulated/0/Download/watchAny';
      try {
        final dir = Directory(publicDir);
        if (!await dir.exists()) await dir.create(recursive: true);
        return publicDir;
      } catch (_) {}
      final appDoc = await getApplicationDocumentsDirectory();
      final path = '${appDoc.path}/watchAnyDownloads';
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      return path;
    } else {
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          final path = '${downloadsDir.path}${Platform.pathSeparator}watchAny';
          final dir = Directory(path);
          if (!await dir.exists()) await dir.create(recursive: true);
          return path;
        }
      } catch (_) {}
      final homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
      final path = '$homeDir${Platform.pathSeparator}Downloads${Platform.pathSeparator}watchAny';
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      return path;
    }
  }

  Future<int> getDownloadsDirectorySize() async {
    try {
      final baseDir = await getEffectiveDownloadPath();
      final dir = Directory(baseDir);
      if (!await dir.exists()) return 0;
      int totalSize = 0;
      await for (final file in dir.list(recursive: true, followLinks: false)) {
        if (file is File) {
          try {
            totalSize += await file.length();
          } catch (_) {}
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint("Error calculating downloads directory size: $e");
      return 0;
    }
  }

  Future<bool> preCheckStorageLimit(int incomingFileBytes) async {
    try {
      final limitBytes = (AppSettings().downloadsLimitGB * 1024 * 1024 * 1024).round();
      final currentSize = await getDownloadsDirectorySize();
      if (currentSize + incomingFileBytes <= limitBytes) {
        return true;
      }
      if (AppSettings().autoManageStorage) {
        return await forceAutoDeleteToFit(incomingFileBytes);
      }
      return false;
    } catch (e) {
      debugPrint("Error checking storage limit: $e");
      return true;
    }
  }

  Future<bool> forceAutoDeleteToFit(int incomingFileBytes) async {
    try {
      final limitBytes = (AppSettings().downloadsLimitGB * 1024 * 1024 * 1024).round();
      final completedTasks = _tasks.where((t) => t.status == DownloadStatus.completed).toList();
      
      int currentSize = await getDownloadsDirectorySize();
      for (var task in completedTasks) {
        if (currentSize + incomingFileBytes <= limitBytes) {
          return true;
        }
        await removeDownload(task.id, deleteFile: true);
        currentSize = await getDownloadsDirectorySize();
      }
      return (currentSize + incomingFileBytes <= limitBytes);
    } catch (e) {
      debugPrint("Error in forceAutoDeleteToFit: $e");
      return false;
    }
  }
}
