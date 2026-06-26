class TorrentFile {
  final int index;
  final String name;
  final int length;
  final String path;

  const TorrentFile({
    required this.index,
    required this.name,
    required this.length,
    required this.path,
  });

  factory TorrentFile.fromJson(Map<String, dynamic> json, int index) {
    final path = json['path'] as String? ?? '';
    var name = json['name'] as String? ?? '';
    if (name.isEmpty || name == 'Unknown') {
      name = path.split('/').last.split('\\').last;
    }
    if (name.isEmpty) {
      name = 'Unknown';
    }
    return TorrentFile(
      index: index,
      name: name,
      length: json['length'] as int? ?? 0,
      path: path,
    );
  }

  String get sizeLabel {
    if (length <= 0) return '0 B';
    if (length < 1024 * 1024) return '${(length / 1024).toStringAsFixed(1)} KB';
    if (length < 1024 * 1024 * 1024) {
      return '${(length / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(length / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get isVideo {
    final ext = name.toLowerCase().split('.').last;
    return ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'ogv'].contains(ext);
  }

  bool get isAudio {
    final ext = name.toLowerCase().split('.').last;
    return ['mp3', 'flac', 'aac', 'ogg', 'wav', 'm4a', 'opus'].contains(ext);
  }
}

class TorrentInfo {
  final String hash;
  final String title;
  final String stat;
  final int statCode;
  final List<TorrentFile> files;
  final double downloadSpeed;
  final int totalPeers;
  final int activePeers;

  const TorrentInfo({
    required this.hash,
    required this.title,
    required this.stat,
    required this.statCode,
    required this.files,
    this.downloadSpeed = 0,
    this.totalPeers = 0,
    this.activePeers = 0,
  });

  factory TorrentInfo.fromJson(Map<String, dynamic> json) {
    final rawFiles = (json['file_stats'] as List<dynamic>?)
        ?? (json['files'] as List<dynamic>?)
        ?? [];

    final files = rawFiles
        .asMap()
        .entries
        .map((e) => TorrentFile.fromJson(e.value as Map<String, dynamic>, e.key))
        .toList();

    return TorrentInfo(
      hash: json['hash'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown Torrent',
      stat: json['stat_string'] as String? ?? '',
      statCode: json['stat'] as int? ?? 0,
      files: files,
      downloadSpeed: (json['download_speed'] as num?)?.toDouble() ?? 0,
      totalPeers: json['total_peers'] as int? ?? 0,
      activePeers: json['active_peers'] as int? ?? 0,
    );
  }

  List<TorrentFile> get playableFiles =>
      files.where((f) => f.isVideo || f.isAudio).toList();
}
