import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/extension_service.dart';
import '../services/torrserver_service.dart';
import '../services/batch_mapping_service.dart';
import '../models/torrent.dart';
import '../screens/player_screen.dart';

extension TorrentStreamExtension on TorrentStream {
  String get computedType {
    if (type != null && type!.isNotEmpty) {
      final t = type!.toLowerCase();
      if (t == 'batch' || t == 'episode' || t == 'movie') return t;
    }
    
    final t = title.toLowerCase();
    
    final batchPatterns = [
      r'\bbatch\b',
      r'\bcomplete\b',
      r'\bseason\b',
      r'\bs\d+\b',
      r'\bepisodes?\s*\d+\s*-\s*\d+\b',
      r'\b\d+\s*-\s*\d+\b',
      r'\b\d+\s*~\s*\d+\b',
      r'\b\d+\s*to\s*\d+\b',
      r'\bpack\b',
      r'\bmulti-sub\b',
      r'\bdisc\s*\d+\b',
    ];
    
    for (var pattern in batchPatterns) {
      if (RegExp(pattern).hasMatch(t)) {
        return 'batch';
      }
    }
    
    return 'episode';
  }

  List<String> get tags {
    final List<String> extracted = [];
    final t = title.toLowerCase();

    // Resolution tags
    if (t.contains('1080p') || t.contains('1080')) extracted.add('1080p');
    else if (t.contains('720p') || t.contains('720')) extracted.add('720p');
    else if (t.contains('480p') || t.contains('480')) extracted.add('480p');
    else if (t.contains('2160p') || t.contains('4k') || t.contains('2160')) extracted.add('4K');

    // Audio/Dub tags
    if (t.contains('dual audio') || t.contains('dual-audio') || t.contains('multi-audio')) {
      extracted.add('Dual Audio');
    } else if (t.contains('dubbed') || t.contains('dub') || t.contains('multi-dub')) {
      if (!t.contains('double')) extracted.add('Dubbed');
    }
    if (t.contains('subbed') || t.contains('sub') || t.contains('multi-sub')) {
      if (!t.contains('subject') && !t.contains('subsplease') && !t.contains('subscrib')) extracted.add('Subbed');
    }

    // Video Codec tags
    if (t.contains('x265') || t.contains('hevc')) {
      extracted.add('HEVC/x265');
    } else if (t.contains('x264') || t.contains('avc')) {
      extracted.add('x264');
    }
    if (t.contains('10bit') || t.contains('10-bit')) {
      extracted.add('10-bit');
    }

    // Source tags
    if (t.contains('bd') || t.contains('blu-ray') || t.contains('bluray')) {
      extracted.add('Blu-ray');
    } else if (t.contains('web-dl') || t.contains('web') || t.contains('webrip')) {
      extracted.add('WEB');
    }

    return extracted;
  }
}

class TorrentSelectorPanel extends StatefulWidget {
  final int anilistId;
  final List<String> titles;
  final int episodeCount;
  final int episodeNumber;
  final bool isMovie;
  final Map<String, dynamic>? media;
  final List<dynamic>? episodes;
  final Map<int, dynamic>? tmdbEpisodesMap;
  final void Function(String streamUrl, String title)? onStreamSelected;

  const TorrentSelectorPanel({
    super.key,
    required this.anilistId,
    required this.titles,
    required this.episodeCount,
    required this.episodeNumber,
    this.isMovie = false,
    this.media,
    this.episodes,
    this.tmdbEpisodesMap,
    this.onStreamSelected,
  });

  @override
  State<TorrentSelectorPanel> createState() => _TorrentSelectorPanelState();
}

class _TorrentSelectorPanelState extends State<TorrentSelectorPanel> {
  final ExtensionService _extensionService = ExtensionService();
  StreamSubscription<List<TorrentStream>>? _streamSubscription;
  
  bool _isLoading = true;
  String? _errorMessage;
  List<TorrentStream> _streams = [];
  
  // Filters state
  String? _selectedResolution; // null means 'All'
  final List<String> _exclusions = [];
  final TextEditingController _excludeController = TextEditingController();
  String _selectedTypeFilter = 'all'; // 'all', 'episode', 'batch'
  String _selectedSortOrder = 'seeders'; // 'seeders', 'size_desc', 'size_asc', 'leechers'

  @override
  void initState() {
    super.initState();
    _fetchStreams();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _excludeController.dispose();
    super.dispose();
  }

  List<TorrentStream> get _processedStreams {
    List<TorrentStream> list = List.from(_streams);

    // 1. Type Filter
    if (_selectedTypeFilter == 'episode') {
      list = list.where((s) => s.computedType == 'episode').toList();
    } else if (_selectedTypeFilter == 'batch') {
      list = list.where((s) => s.computedType == 'batch').toList();
    }

    // 2. Sorting
    if (_selectedSortOrder == 'seeders') {
      list.sort((a, b) => b.seeders.compareTo(a.seeders));
    } else if (_selectedSortOrder == 'size_desc') {
      list.sort((a, b) => b.size.compareTo(a.size));
    } else if (_selectedSortOrder == 'size_asc') {
      list.sort((a, b) => a.size.compareTo(b.size));
    } else if (_selectedSortOrder == 'leechers') {
      list.sort((a, b) => b.leechers.compareTo(a.leechers));
    }

    return list;
  }

  Future<void> _fetchStreams() async {
    await _streamSubscription?.cancel();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _streams = [];
    });

    _streamSubscription = _extensionService.searchStreamsStream(
      anilistId: widget.anilistId,
      titles: widget.titles,
      episodeCount: widget.episodeCount,
      episodeNumber: widget.episodeNumber,
      media: widget.media,
      resolution: _selectedResolution,
      exclusions: _exclusions,
      isMovie: widget.isMovie,
    ).listen(
      (results) {
        if (mounted) {
          setState(() {
            _streams = results;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
    );
  }

  String _formatBytes(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) + ' ' + suffixes[i];
  }

  Widget _buildFilterRow(bool isMobile) {
    final resolutions = [
      {'label': 'All', 'value': null},
      {'label': '1080p', 'value': '1080'},
      {'label': '720p', 'value': '720'},
      {'label': '480p', 'value': '480'},
    ];

    final qualitySelector = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Quality:',
          style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit'),
        ),
        const SizedBox(width: 8.0),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedResolution,
              dropdownColor: const Color(0xFF0F0F11),
              style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
              items: resolutions.map((res) {
                return DropdownMenuItem<String?>(
                  value: res['value'],
                  child: Text(res['label'] as String),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedResolution = val;
                });
                _fetchStreams();
              },
            ),
          ),
        ),
      ],
    );

    final typeSelector = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Type:',
          style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit'),
        ),
        const SizedBox(width: 8.0),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTypeFilter,
              dropdownColor: const Color(0xFF0F0F11),
              style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'episode', child: Text('Episodes')),
                DropdownMenuItem(value: 'batch', child: Text('Batches')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedTypeFilter = val;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );

    final sortSelector = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Sort:',
          style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit'),
        ),
        const SizedBox(width: 8.0),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedSortOrder,
              dropdownColor: const Color(0xFF0F0F11),
              style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
              items: const [
                DropdownMenuItem(value: 'seeders', child: Text('Seeders')),
                DropdownMenuItem(value: 'size_desc', child: Text('Size (Large)')),
                DropdownMenuItem(value: 'size_asc', child: Text('Size (Small)')),
                DropdownMenuItem(value: 'leechers', child: Text('Leechers')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedSortOrder = val;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );

    final selectorsWrap = Wrap(
      spacing: 16.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        qualitySelector,
        typeSelector,
        sortSelector,
      ],
    );

    final exclusionsInput = SizedBox(
      height: 36.0,
      child: TextField(
        controller: _excludeController,
        style: const TextStyle(color: Colors.white, fontSize: 12.0),
        decoration: InputDecoration(
          hintText: 'Add filter exclusions (comma separated)...',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.03),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6.0),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6.0),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6.0),
            borderSide: const BorderSide(color: Colors.white30),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
        ),
        onSubmitted: (val) {
          final parts = val.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty);
          if (parts.isNotEmpty) {
            setState(() {
              _exclusions.addAll(parts);
            });
            _excludeController.clear();
            _fetchStreams();
          }
        },
      ),
    );

    final exclusionsActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_exclusions.isNotEmpty) ...[
          Text(
            '${_exclusions.length} Excl.',
            style: const TextStyle(color: Colors.white38, fontSize: 12.0),
          ),
          IconButton(
            icon: const Icon(Icons.clear_all, color: Colors.white54, size: 18.0),
            onPressed: () {
              setState(() {
                _exclusions.clear();
              });
              _fetchStreams();
            },
            tooltip: 'Clear exclusions',
          ),
        ],
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white70, size: 20.0),
          onPressed: _fetchStreams,
          tooltip: 'Reload streams',
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: selectorsWrap),
              exclusionsActions,
            ],
          ),
          const SizedBox(height: 8.0),
          exclusionsInput,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleLabel = widget.isMovie ? 'Movie' : 'Episode ${widget.episodeNumber}';
    
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return Column(
      children: [
        // Title Bar Header
        Container(
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: isMobile ? 12.0 : 16.0),
          color: Colors.white.withValues(alpha: 0.01),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available Streams • $titleLabel',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      widget.titles[0],
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 11.0),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        
        // Filters
        _buildFilterRow(isMobile),
        
        // Main list area
        Expanded(
          child: _isLoading && _streams.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                      SizedBox(height: 16.0),
                      Text(
                        'Querying active extensions...',
                        style: TextStyle(color: Colors.white54, fontSize: 13.0, fontFamily: 'Outfit'),
                      ),
                    ],
                  ),
                )
              : _errorMessage != null && _streams.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                            const SizedBox(height: 12.0),
                            Text(
                              'Search failed: $_errorMessage',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 13.0),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _processedStreams.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.video_collection_outlined, color: Colors.white24, size: 40.0),
                              SizedBox(height: 12.0),
                              Text(
                                'No streams found.',
                                style: TextStyle(color: Colors.white38, fontSize: 14.0, fontFamily: 'Outfit'),
                              ),
                              SizedBox(height: 4.0),
                              Text(
                                'Verify extensions are enabled and synced in Settings.',
                                style: TextStyle(color: Colors.white24, fontSize: 11.5),
                              ),
                            ],
                          ),
                        )
                      : Stack(
                          children: [
                            ListView.builder(
                              padding: const EdgeInsets.all(16.0),
                              itemCount: _processedStreams.length,
                              itemBuilder: (context, index) {
                            final stream = _processedStreams[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10.0),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                title: Text(
                                  stream.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Wrap(
                                    spacing: 8.0,
                                    runSpacing: 4.0,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      // Extension badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(4.0),
                                        ),
                                        child: Text(
                                          stream.extensionName.toUpperCase(),
                                          style: const TextStyle(color: Colors.white60, fontSize: 9.0, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      
                                      // Size
                                      Text(
                                        _formatBytes(stream.size),
                                        style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                                      ),
                                      
                                      // Seeders
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.arrow_upward, color: Colors.green, size: 14.0),
                                          const SizedBox(width: 2.0),
                                          Text(
                                            '${stream.seeders}',
                                            style: const TextStyle(color: Colors.green, fontSize: 11.5, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      
                                      // Leechers
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.arrow_downward, color: Colors.redAccent, size: 14.0),
                                          const SizedBox(width: 2.0),
                                          Text(
                                            '${stream.leechers}',
                                            style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                                          ),
                                        ],
                                      ),
                                      
                                      // Computed type badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                        decoration: BoxDecoration(
                                          color: stream.computedType == 'batch'
                                              ? Colors.amber.withValues(alpha: 0.15)
                                              : Colors.blue.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4.0),
                                        ),
                                        child: Text(
                                          stream.computedType.toUpperCase(),
                                          style: TextStyle(
                                            color: stream.computedType == 'batch'
                                                ? Colors.amber[400]
                                                : Colors.blue[400],
                                            fontSize: 9.0,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),

                                      // Tags
                                      ...stream.tags.map((tag) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(4.0),
                                          border: Border.all(color: Colors.white12),
                                        ),
                                        child: Text(
                                          tag,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 9.0,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      )),
                                    ],
                                  ),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (dialogContext) {
                                        return _PlaybackProgressDialog(
                                          stream: stream,
                                          parentContext: context,
                                          anilistId: widget.anilistId,
                                          episodeNumber: widget.episodeNumber,
                                          titles: widget.titles,
                                          episodeCount: widget.episodeCount,
                                          isMovie: widget.isMovie,
                                          media: widget.media,
                                          episodes: widget.episodes,
                                          tmdbEpisodesMap: widget.tmdbEpisodesMap,
                                          onStreamSelected: widget.onStreamSelected,
                                        );
                                      },
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                                  ),
                                  child: const Text('Play', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0)),
                                ),
                              ),
                            );
                          },
                        ),
                        if (_isLoading)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.transparent,
                              color: Colors.white24,
                              minHeight: 2.0,
                            ),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}

class _PlaybackProgressDialog extends StatefulWidget {
  final TorrentStream stream;
  final BuildContext parentContext;
  final int anilistId;
  final int episodeNumber;
  final List<String> titles;
  final int episodeCount;
  final bool isMovie;
  final Map<String, dynamic>? media;
  final List<dynamic>? episodes;
  final Map<int, dynamic>? tmdbEpisodesMap;
  final void Function(String streamUrl, String title)? onStreamSelected;

  const _PlaybackProgressDialog({
    required this.stream,
    required this.parentContext,
    required this.anilistId,
    required this.episodeNumber,
    required this.titles,
    required this.episodeCount,
    required this.isMovie,
    this.media,
    this.episodes,
    this.tmdbEpisodesMap,
    this.onStreamSelected,
  });

  @override
  State<_PlaybackProgressDialog> createState() => _PlaybackProgressDialogState();
}

class _PlaybackProgressDialogState extends State<_PlaybackProgressDialog> {
  final TorrServerService _torrServerService = TorrServerService();
  String _status = "Checking TorrServer status...";
  bool _hasError = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _startPlaybackFlow();
  }

  int? extractEpisodeNumber(String fileName) {
    final nameWithoutExt = fileName.contains('.') 
        ? fileName.substring(0, fileName.lastIndexOf('.')) 
        : fileName;
    
    // Try pattern: S01E01 / E01 / Ep01
    final sEPattern = RegExp(r'\b[sS]\d+[eE](\d+)\b');
    var match = sEPattern.firstMatch(nameWithoutExt);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    // Try pattern: ep / episode / e 01
    final epPattern = RegExp(r'\b(?:ep|episode|e)\.?\s*(\d+)\b', caseSensitive: false);
    match = epPattern.firstMatch(nameWithoutExt);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    // Try pattern: - 01
    final dashPattern = RegExp(r'\s-\s(\d+)\b');
    match = dashPattern.firstMatch(nameWithoutExt);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    // Try pattern: [01]
    final bracketPattern = RegExp(r'\[(\d+)\]');
    match = bracketPattern.firstMatch(nameWithoutExt);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    // Try pattern: (01)
    final parenPattern = RegExp(r'\((\d+)\)');
    match = parenPattern.firstMatch(nameWithoutExt);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    final numbers = RegExp(r'\b(\d+)\b').allMatches(nameWithoutExt).map((m) => m.group(1)!).toList();
    for (var numStr in numbers.reversed) {
      final val = int.tryParse(numStr);
      if (val != null) {
        if (val == 1080 || val == 720 || val == 480 || val == 10 || val == 8 || val == 264 || val == 265 || val == 5 || val == 1) {
          continue;
        }
        return val;
      }
    }

    return null;
  }

  int? _saveBatchMappingIfApplicable(String hash, List<TorrentFile> playableFiles) {
    if (playableFiles.length <= 1) return null;
    
    final Map<int, int> episodeToIndex = {};
    int? matchedIndex;
    for (var file in playableFiles) {
      final fileName = file.path.split('/').last.split('\\').last;
      final nameToUse = fileName.isNotEmpty ? fileName : file.name;
      final epNum = extractEpisodeNumber(nameToUse);
      if (epNum != null) {
        episodeToIndex[epNum] = file.index;
        if (epNum == widget.episodeNumber) {
          matchedIndex = file.index;
        }
      }
    }
    
    if (episodeToIndex.isNotEmpty) {
      BatchMappingService().saveMapping(
        anilistId: widget.anilistId,
        torrentLink: widget.stream.link,
        torrentHash: hash,
        torrentTitle: widget.stream.title,
        episodeToIndex: episodeToIndex,
      );
    }
    return matchedIndex;
  }

  TorrentFile? _playingFile;
  String? _playingHash;

  Future<void> _startPlaybackFlow() async {
    try {
      // 1. Ping TorrServer to check if online
      final bool online = await _torrServerService.ping();
      if (!online) {
        setState(() {
          _status = "TorrServer starting up, waiting...";
        });
        // Wait 2 seconds and retry
        await Future.delayed(const Duration(seconds: 2));
        final bool retryOnline = await _torrServerService.ping();
        if (!retryOnline) {
          throw Exception("TorrServer is not running. Please restart the app.");
        }
      }

      // 2. Add torrent and fetch metadata
      setState(() {
        _status = "Adding torrent & fetching metadata...";
      });

      final TorrentInfo torrentInfo = await _torrServerService.addTorrent(
        widget.stream.link,
        title: widget.stream.title,
      );

      if (!mounted) return;

      // 3. Find video/audio files
      final List<TorrentFile> playableFiles = torrentInfo.playableFiles;

      if (playableFiles.isEmpty) {
        throw Exception("No playable media files found in this torrent.");
      }

      int? autoPlayIndex = _saveBatchMappingIfApplicable(torrentInfo.hash, playableFiles);

      if (playableFiles.length == 1 || autoPlayIndex != null) {
        final file = playableFiles.length == 1
            ? playableFiles[0]
            : playableFiles.firstWhere((f) => f.index == autoPlayIndex);

        _playingFile = file;
        _playingHash = torrentInfo.hash;

        // Prebuffering phase inside the dialog
        setState(() {
          _status = "Preloading stream...";
        });

        await _torrServerService.preloadTorrentFile(torrentInfo.hash, file.index);

        int secondsElapsed = 0;
        bool isReady = false;
        while (secondsElapsed < 20 && !isReady) {
          await Future.delayed(const Duration(seconds: 1));
          secondsElapsed++;
          if (!mounted) return;

          try {
            final updatedInfo = await _torrServerService.getTorrent(torrentInfo.hash);
            final speedMb = updatedInfo.downloadSpeed / (1024 * 1024);
            setState(() {
              _status = "Prebuffering stream...\n"
                  "${speedMb.toStringAsFixed(1)} MB/s • ${updatedInfo.activePeers} peers\n"
                  "State: ${updatedInfo.stat.isNotEmpty ? updatedInfo.stat : 'Buffering'}";
            });

            if (updatedInfo.statCode >= 5) {
              isReady = true;
            }
          } catch (e) {
            debugPrint("Error polling prebuffer: $e");
          }
        }

        if (!mounted) return;
        Navigator.of(context).pop(); // pop progress dialog
        _navigateToPlayer(torrentInfo.hash, file, shouldPopParent: true);
      } else {
        // Pop the progress dialog first
        Navigator.of(context).pop();
        // Multiple playable files, let the user choose
        _showFileSelectionDialog(torrentInfo.hash, playableFiles);
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString().replaceAll("Exception: ", "");
        });
      }
    }
  }

  void _navigateToPlayer(String hash, TorrentFile file, {bool shouldPopParent = true}) {
    final streamUrl = _torrServerService.getStreamUrl(hash, file.index);
    final fileName = file.path.split('/').last.split('\\').last;
    final displayName = fileName.isNotEmpty ? fileName : file.name;

    if (widget.onStreamSelected != null) {
      widget.onStreamSelected!(streamUrl, displayName);
    } else {
      // Capture the navigator state BEFORE we pop the parent context
      final navigator = Navigator.of(widget.parentContext);

      // Pop the bottom sheet so we return directly to details page when player closes
      if (shouldPopParent) {
        navigator.pop();
      }

      // Push the player screen using the captured navigator which remains safely mounted
      navigator.push(
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            streamUrl: streamUrl,
            title: displayName,
            anilistId: widget.anilistId,
            titles: widget.titles,
            episodeCount: widget.episodeCount,
            episodeNumber: widget.episodeNumber,
            isMovie: widget.isMovie,
            media: widget.media,
            episodes: widget.episodes,
            tmdbEpisodesMap: widget.tmdbEpisodesMap,
          ),
        ),
      );
    }
  }

  void _showFileSelectionDialog(String hash, List<TorrentFile> files) {
    showDialog(
      context: widget.parentContext,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0F11),
          title: const Text(
            "Select File to Play",
            style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0),
          ),
          content: SizedBox(
            width: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final fileName = file.path.split('/').last.split('\\').last;
                final displayName = fileName.isNotEmpty ? fileName : file.name;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  title: Text(
                    displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 13.0),
                  ),
                  subtitle: Text(
                    file.sizeLabel,
                    style: const TextStyle(color: Colors.white38, fontSize: 11.0),
                  ),
                  onTap: () {
                    Navigator.of(context).pop(); // pop selection dialog
                    // Show buffering progress dialog
                    showDialog(
                      context: widget.parentContext,
                      barrierDismissible: false,
                      builder: (dialogContext) {
                        return _BufferingProgressDialog(
                          hash: hash,
                          file: file,
                          parentContext: widget.parentContext,
                          anilistId: widget.anilistId,
                          episodeNumber: widget.episodeNumber,
                          titles: widget.titles,
                          episodeCount: widget.episodeCount,
                          isMovie: widget.isMovie,
                          media: widget.media,
                          episodes: widget.episodes,
                          tmdbEpisodesMap: widget.tmdbEpisodesMap,
                          onStreamSelected: widget.onStreamSelected,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // pop selection dialog
              },
              child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0F11),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_hasError) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Outfit', height: 1.4),
              ),
              if (_playingFile != null && _playingHash != null) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // pop dialog
                    _navigateToPlayer(_playingHash!, _playingFile!, shouldPopParent: true);
                  },
                  child: const Text("Skip Buffering", style: TextStyle(color: Colors.white54, fontSize: 12.0)),
                ),
              ],
            ] else ...[
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                "Playback Failed",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close", style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _errorMessage = "";
                        _playingFile = null;
                        _playingHash = null;
                      });
                      _startPlaybackFlow();
                    },
                    child: const Text("Retry"),
                  ),
                ],
              )
            ],
          ],
        ),
      ),
    );
  }
}

class _BufferingProgressDialog extends StatefulWidget {
  final String hash;
  final TorrentFile file;
  final BuildContext parentContext;
  final int anilistId;
  final int episodeNumber;
  final List<String> titles;
  final int episodeCount;
  final bool isMovie;
  final Map<String, dynamic>? media;
  final List<dynamic>? episodes;
  final Map<int, dynamic>? tmdbEpisodesMap;
  final void Function(String streamUrl, String title)? onStreamSelected;

  const _BufferingProgressDialog({
    required this.hash,
    required this.file,
    required this.parentContext,
    required this.anilistId,
    required this.episodeNumber,
    required this.titles,
    required this.episodeCount,
    required this.isMovie,
    this.media,
    this.episodes,
    this.tmdbEpisodesMap,
    this.onStreamSelected,
  });

  @override
  State<_BufferingProgressDialog> createState() => _BufferingProgressDialogState();
}

class _BufferingProgressDialogState extends State<_BufferingProgressDialog> {
  final TorrServerService _torrServerService = TorrServerService();
  String _status = "Initializing buffering...";
  bool _hasError = false;
  String _errorMessage = "";
  Timer? _pollTimer;
  int _secondsElapsed = 0;

  @override
  void initState() {
    super.initState();
    _startPrebuffering();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startPrebuffering() async {
    try {
      // 1. Trigger preload
      await _torrServerService.preloadTorrentFile(widget.hash, widget.file.index);

      // 2. Poll progress every second
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        _secondsElapsed++;
        if (!mounted) {
          timer.cancel();
          return;
        }

        try {
          final info = await _torrServerService.getTorrent(widget.hash);
          
          if (!mounted) {
            timer.cancel();
            return;
          }

          final speedMb = info.downloadSpeed / (1024 * 1024);
          setState(() {
            _status = "Prebuffering stream...\n"
                "${speedMb.toStringAsFixed(1)} MB/s • ${info.activePeers} peers\n"
                "State: ${info.stat.isNotEmpty ? info.stat : 'Buffering'}";
          });

          if (info.statCode >= 5 || _secondsElapsed >= 20) {
            timer.cancel();
            _launchPlayer();
          }
        } catch (e) {
          debugPrint("Error polling prebuffer: $e");
          if (_secondsElapsed >= 20) {
            timer.cancel();
            _launchPlayer();
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString().replaceAll("Exception: ", "");
        });
      }
    }
  }

  void _launchPlayer() {
    if (!mounted) return;
    Navigator.of(context).pop(); // pop this buffering dialog

    final streamUrl = _torrServerService.getStreamUrl(widget.hash, widget.file.index);
    final fileName = widget.file.path.split('/').last.split('\\').last;
    final displayName = fileName.isNotEmpty ? fileName : widget.file.name;

    if (widget.onStreamSelected != null) {
      widget.onStreamSelected!(streamUrl, displayName);
    } else {
      final navigator = Navigator.of(widget.parentContext);
      // Pop the bottom sheet so we return directly to details page when player closes
      navigator.pop();

      navigator.push(
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            streamUrl: streamUrl,
            title: displayName,
            anilistId: widget.anilistId,
            titles: widget.titles,
            episodeCount: widget.episodeCount,
            episodeNumber: widget.episodeNumber,
            isMovie: widget.isMovie,
            media: widget.media,
            episodes: widget.episodes,
            tmdbEpisodesMap: widget.tmdbEpisodesMap,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0F11),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_hasError) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Outfit', height: 1.4),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _pollTimer?.cancel();
                  _launchPlayer();
                },
                child: const Text("Skip Buffering", style: TextStyle(color: Colors.white54, fontSize: 12.0)),
              ),
            ] else ...[
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                "Buffering Failed",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close", style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _errorMessage = "";
                        _secondsElapsed = 0;
                        _status = "Initializing buffering...";
                      });
                      _startPrebuffering();
                    },
                    child: const Text("Retry"),
                  ),
                ],
              )
            ],
          ],
        ),
      ),
    );
  }
}
