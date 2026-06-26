import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/extension_service.dart';
import '../services/torrserver_service.dart';
import '../models/torrent.dart';
import '../screens/player_screen.dart';

class TorrentSelectorPanel extends StatefulWidget {
  final int anilistId;
  final List<String> titles;
  final int episodeCount;
  final int episodeNumber;
  final bool isMovie;
  final Map<String, dynamic>? media;

  const TorrentSelectorPanel({
    super.key,
    required this.anilistId,
    required this.titles,
    required this.episodeCount,
    required this.episodeNumber,
    this.isMovie = false,
    this.media,
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
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    qualitySelector,
                    exclusionsActions,
                  ],
                ),
                const SizedBox(height: 8.0),
                exclusionsInput,
              ],
            )
          : Row(
              children: [
                qualitySelector,
                const SizedBox(width: 24.0),
                Expanded(child: exclusionsInput),
                if (_exclusions.isNotEmpty) const SizedBox(width: 12.0),
                exclusionsActions,
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
                  : _streams.isEmpty
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
                              itemCount: _streams.length,
                              itemBuilder: (context, index) {
                            final stream = _streams[index];
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
                                      
                                      // Optional type badge
                                      if (stream.type != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                          decoration: BoxDecoration(
                                            color: Colors.cyan.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4.0),
                                          ),
                                          child: Text(
                                            stream.type!.toUpperCase(),
                                            style: TextStyle(color: Colors.cyan[400], fontSize: 9.0, fontWeight: FontWeight.bold),
                                          ),
                                        ),
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

  const _PlaybackProgressDialog({
    required this.stream,
    required this.parentContext,
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

      // Pop the progress dialog first
      Navigator.of(context).pop();

      // 4. Handle files selection
      if (playableFiles.length == 1) {
        // Only one playable file, play it directly
        _navigateToPlayer(torrentInfo.hash, playableFiles[0]);
      } else {
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

  void _navigateToPlayer(String hash, TorrentFile file) {
    final streamUrl = _torrServerService.getStreamUrl(hash, file.index);
    final fileName = file.path.split('/').last.split('\\').last;

    // Capture the navigator state BEFORE we pop the parent context
    final navigator = Navigator.of(widget.parentContext);

    // Pop the bottom sheet so we return directly to details page when player closes
    navigator.pop();

    // Push the player screen using the captured navigator which remains safely mounted
    navigator.push(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamUrl: streamUrl,
          title: fileName.isNotEmpty ? fileName : file.name,
        ),
      ),
    );
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
                    _navigateToPlayer(hash, file);
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
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Outfit'),
              ),
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
