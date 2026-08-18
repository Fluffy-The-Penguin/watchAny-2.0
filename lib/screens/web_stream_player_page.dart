import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide X509Certificate;
import 'package:window_manager/window_manager.dart';
import '../models/web_stream_server.dart';
import '../services/web_stream_service.dart';
import '../state/library_state.dart';
import '../state/navigation_state.dart';
import '../main.dart';

class WebStreamPlayerPage extends StatefulWidget {
  final int anilistId;
  final int? malId;
  final String title;
  final int episode;
  final int totalEpisodes;
  final List<dynamic>? episodesData;
  final String? initialServerId;
  final AudioType initialAudioType;
  final NavigationState navigationState;
  final VoidCallback? onOpenTorrents;

  const WebStreamPlayerPage({
    super.key,
    required this.anilistId,
    this.malId,
    required this.title,
    required this.episode,
    required this.totalEpisodes,
    this.episodesData,
    this.initialServerId,
    this.initialAudioType = AudioType.sub,
    required this.navigationState,
    this.onOpenTorrents,
  });

  @override
  State<WebStreamPlayerPage> createState() => _WebStreamPlayerPageState();
}

class _WebStreamPlayerPageState extends State<WebStreamPlayerPage> {
  late int _currentEpisode;
  late WebStreamServer _selectedServer;
  late AudioType _currentAudioType;
  String? _customStreamUrl;
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _isFullscreen = false;
  double _progress = 0.0;
  int _webViewKeyIndex = 0;

  // Sidebar state
  bool _isGridView = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Auto Toggles state
  bool _autoOp = false;
  bool _autoEd = false;
  bool _autoFiller = false;

  final bool _isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.episode;
    _currentAudioType = widget.initialAudioType;

    final initialId = widget.initialServerId ?? 'vidnest_hd';
    _selectedServer = WebStreamService.availableServers.firstWhere(
      (s) => s.id == initialId,
      orElse: () => WebStreamService.availableServers.first,
    );

    _markEpisodeWatched();
  }

  void _markEpisodeWatched() {
    try {
      final existing = LibraryState().getItem(widget.anilistId, 'anime');
      if (existing != null) {
        LibraryState().saveItem(
          id: widget.anilistId,
          mode: 'anime',
          format: existing.format,
          libraryStatus: (widget.totalEpisodes > 0 && _currentEpisode >= widget.totalEpisodes)
              ? 'completed'
              : 'watching',
          rating: existing.rating,
          watchedEpisodes: _currentEpisode > existing.watchedEpisodes ? _currentEpisode : existing.watchedEpisodes,
          totalEpisodes: widget.totalEpisodes > 0 ? widget.totalEpisodes : existing.totalEpisodes,
        );
      }
    } catch (_) {}
  }

  String get _currentStreamUrl {
    if (_customStreamUrl != null && _customStreamUrl!.isNotEmpty) {
      return _customStreamUrl!;
    }
    return _selectedServer.urlBuilder(
      anilistId: widget.anilistId,
      episode: _currentEpisode,
      audioType: _currentAudioType,
      malId: widget.malId,
    );
  }

  void _loadCurrentStream() {
    setState(() {
      _isLoading = true;
      _progress = 0.0;
      _webViewKeyIndex++;
    });

    final url = _currentStreamUrl;
    if (_webViewController != null) {
      _webViewController!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(url),
          headers: {
            'Referer': 'https://animedex.fun/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ),
      );
    }
  }

  Future<void> _toggleFullscreen() async {
    final nextFS = !_isFullscreen;
    setState(() => _isFullscreen = nextFS);

    if (_isDesktop) {
      if (nextFS) {
        await windowManager.setBackgroundColor(Colors.black);
      }
      await windowManager.setFullScreen(nextFS);
    } else {
      if (nextFS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      }
    }
  }

  void _changeEpisode(int newEp) {
    if (newEp < 1 || (widget.totalEpisodes > 0 && newEp > widget.totalEpisodes)) {
      return;
    }
    setState(() {
      _currentEpisode = newEp;
    });
    _markEpisodeWatched();
    _loadCurrentStream();
  }

  void _promptCustomSourceDialog() {
    final textController = TextEditingController(text: _customStreamUrl ?? '');
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131322),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
          title: const Row(
            children: [
              Icon(Icons.link_rounded, color: Colors.cyanAccent, size: 22),
              SizedBox(width: 10),
              Text(
                'Custom Stream Embed URL',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter any direct stream or iframe embed URL to load into the player:',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF1C1C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Colors.cyanAccent),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                final val = textController.text.trim();
                if (val.isNotEmpty) {
                  setState(() {
                    _customStreamUrl = val;
                  });
                  _loadCurrentStream();
                }
              },
              child: const Text('Load URL', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_isDesktop) {
      windowManager.isFullScreen().then((isFS) {
        if (isFS) windowManager.setFullScreen(false);
      });
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktopLayout = size.width >= 850;

    return Scaffold(
      backgroundColor: const Color(0xFF07070C),
      body: SafeArea(
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        child: Column(
          children: [
            // Top Navigation Bar
            if (!_isFullscreen) _buildTopBar(),

            // Loading Bar
            if (_isLoading)
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 2.0,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
              ),

            // Main Workspace (Player + Episodes Sidebar)
            Expanded(
              child: _isFullscreen
                  ? _buildWebViewPlayer()
                  : isDesktopLayout
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Main Column: Video Player + Source Pills Card
                            Expanded(
                              flex: 7,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 12.0, bottom: 20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 16:9 Video Player Container
                                    AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: _buildWebViewPlayer(),
                                    ),
                                    const SizedBox(height: 12.0),
                                    // Bottom Sources & Controls Card
                                    _buildSourcesAndControlsCard(),
                                  ],
                                ),
                              ),
                            ),

                            // Right Column: Episode Selector Sidebar
                            SizedBox(
                              width: 320.0,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0, right: 16.0, top: 12.0, bottom: 20.0),
                                child: _buildEpisodeSidebarCard(),
                              ),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AspectRatio(
                                aspectRatio: 16 / 9,
                                child: _buildWebViewPlayer(),
                              ),
                              const SizedBox(height: 12.0),
                              _buildSourcesAndControlsCard(),
                              const SizedBox(height: 16.0),
                              SizedBox(
                                height: 420.0,
                                child: _buildEpisodeSidebarCard(),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52.0,
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C14),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    'EP $_currentEpisode${widget.totalEpisodes > 0 ? '/${widget.totalEpisodes}' : ''}',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // SUB / DUB Toggle Switcher
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF161622),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAudioToggleItem('SUB', AudioType.sub),
                _buildAudioToggleItem('DUB', AudioType.dub),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Open Torrents Panel Button
          if (widget.onOpenTorrents != null)
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white70, size: 20),
              tooltip: 'Torrents & P2P Streams',
              onPressed: widget.onOpenTorrents,
            ),

          // Fullscreen Toggle
          IconButton(
            icon: Icon(
              _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              color: Colors.white,
              size: 22,
            ),
            tooltip: _isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _buildAudioToggleItem(String label, AudioType type) {
    final isSelected = _currentAudioType == type;
    return GestureDetector(
      onTap: () {
        if (_currentAudioType != type) {
          setState(() {
            _currentAudioType = type;
            _customStreamUrl = null;
          });
          _loadCurrentStream();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(5.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildWebViewPlayer() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_isFullscreen ? 0 : 10.0),
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            InAppWebView(
              key: ValueKey('$_currentStreamUrl-$_webViewKeyIndex'),
              webViewEnvironment: appWebViewEnvironment,
              initialUrlRequest: URLRequest(
                url: WebUri(_currentStreamUrl),
                headers: {
                  'Referer': 'https://animedex.fun/',
                },
              ),
              initialSettings: InAppWebViewSettings(
                isInspectable: kDebugMode,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: false,
                transparentBackground: false,
                useShouldOverrideUrlLoading: true,
                preferredContentMode: UserPreferredContentMode.DESKTOP,
                userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100;
                  if (progress == 100) {
                    _isLoading = false;
                  }
                });
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri == null) return NavigationActionPolicy.CANCEL;

                final target = uri.toString().toLowerCase();
                // Allow core streaming hosts and media protocols
                if (target.contains('megaplay.buzz') ||
                    target.contains('vidnest.fun') ||
                    target.contains('2embed.cc') ||
                    target.contains('animedex.fun') ||
                    target.contains('cloudflare') ||
                    target.contains('m3u8') ||
                    target.contains('blob:') ||
                    target.contains('google') ||
                    target.contains('about:blank') ||
                    (_customStreamUrl != null && target.contains(_customStreamUrl!.toLowerCase()))) {
                  return NavigationActionPolicy.ALLOW;
                }

                // Block rogue ad popups/redirects
                debugPrint('[WebStreamPlayer] Blocked popup/redirect: $target');
                return NavigationActionPolicy.CANCEL;
              },
            ),

            // Shimmer / Spinner during loading
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.85),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2.5),
                      SizedBox(height: 12),
                      Text(
                        'Connecting to streaming server...',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit'),
                      ),
                    ],
                  ),
                ),
              ),

            // Fullscreen Floating Exit Button
            if (_isFullscreen)
              Positioned(
                top: 14.0,
                right: 14.0,
                child: InkWell(
                  onTap: _toggleFullscreen,
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesAndControlsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D16),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: SOURCES Label + Source Pills
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.layers_rounded, color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'SOURCES:',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

              // Server Pills
              ...WebStreamService.availableServers.map((server) {
                final isSelected = _customStreamUrl == null && server.id == _selectedServer.id;
                return _buildSourcePill(
                  title: server.name,
                  badge: server.badge,
                  isSelected: isSelected,
                  onTap: () {
                    if (_customStreamUrl != null || server.id != _selectedServer.id) {
                      setState(() {
                        _customStreamUrl = null;
                        _selectedServer = server;
                        if (!server.supportsDub && _currentAudioType == AudioType.dub) {
                          _currentAudioType = AudioType.sub;
                        }
                      });
                      _loadCurrentStream();
                    }
                  },
                );
              }),

              // Custom Source Pill
              _buildSourcePill(
                title: 'Custom Source',
                badge: 'Manual',
                isSelected: _customStreamUrl != null,
                onTap: _promptCustomSourceDialog,
              ),
            ],
          ),

          const SizedBox(height: 12.0),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1.0),
          const SizedBox(height: 10.0),

          // Row 2: Auto OP/ED/Filler Toggles
          Wrap(
            spacing: 12.0,
            runSpacing: 6.0,
            children: [
              _buildToggleChip(
                label: 'Auto OP: ${_autoOp ? 'ON' : 'OFF'}',
                isActive: _autoOp,
                onTap: () => setState(() => _autoOp = !_autoOp),
              ),
              _buildToggleChip(
                label: 'Auto ED: ${_autoEd ? 'ON' : 'OFF'}',
                isActive: _autoEd,
                onTap: () => setState(() => _autoEd = !_autoEd),
              ),
              _buildToggleChip(
                label: 'Auto Filler: ${_autoFiller ? 'ON' : 'OFF'}',
                isActive: _autoFiller,
                onTap: () => setState(() => _autoFiller = !_autoFiller),
              ),
              if (widget.onOpenTorrents != null)
                GestureDetector(
                  onTap: widget.onOpenTorrents,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_rounded, color: Colors.cyanAccent, size: 13),
                        SizedBox(width: 5),
                        Text(
                          'Open Torrent Streams',
                          style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourcePill({
    required String title,
    required String badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent : const Color(0xFF141420),
          borderRadius: BorderRadius.circular(7.0),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.white.withValues(alpha: 0.1),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12.0,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.black.withValues(alpha: 0.2)
                    : const Color(0xFF26263B),
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: isSelected ? Colors.black87 : Colors.cyanAccent,
                  fontSize: 9.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyanAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4.0),
          border: Border.all(
            color: isActive ? Colors.cyanAccent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.cyanAccent : Colors.white54,
            fontSize: 11.0,
            fontWeight: FontWeight.w600,
            fontFamily: 'Outfit',
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeSidebarCard() {
    final int epCount = widget.episodesData?.length ?? widget.totalEpisodes;
    final displayTotal = epCount > 0 ? epCount : 12;

    final List<int> allEps = List.generate(displayTotal, (i) => i + 1);
    final filteredEps = _searchQuery.isEmpty
        ? allEps
        : allEps.where((ep) {
            if (ep.toString().contains(_searchQuery)) return true;
            if (widget.episodesData != null && ep - 1 < widget.episodesData!.length) {
              final epObj = widget.episodesData![ep - 1];
              final title = (epObj['title'] ?? '').toString().toLowerCase();
              return title.contains(_searchQuery.toLowerCase());
            }
            return false;
          }).toList();

    int fillerCount = 0;
    if (widget.episodesData != null) {
      for (var ep in widget.episodesData!) {
        if (ep is Map && (ep['isFiller'] == true || ep['filler'] == true)) {
          fillerCount++;
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D16),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Header: Episodes + Total Badge + Grid/List Switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
            child: Row(
              children: [
                const Icon(Icons.tv_rounded, color: Colors.cyanAccent, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Episodes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    '$displayTotal Total',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // Grid Toggle
                InkWell(
                  onTap: () => setState(() => _isGridView = true),
                  borderRadius: BorderRadius.circular(4.0),
                  child: Container(
                    padding: const EdgeInsets.all(4.0),
                    decoration: BoxDecoration(
                      color: _isGridView ? Colors.cyanAccent.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Icon(
                      Icons.grid_view_rounded,
                      size: 16,
                      color: _isGridView ? Colors.cyanAccent : Colors.white38,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // List Toggle
                InkWell(
                  onTap: () => setState(() => _isGridView = false),
                  borderRadius: BorderRadius.circular(4.0),
                  child: Container(
                    padding: const EdgeInsets.all(4.0),
                    decoration: BoxDecoration(
                      color: !_isGridView ? Colors.cyanAccent.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Icon(
                      Icons.view_list_rounded,
                      size: 18,
                      color: !_isGridView ? Colors.cyanAccent : Colors.white38,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search / Filter Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0),
            child: SizedBox(
              height: 34.0,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Filter episode number or title...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 16),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.white38, size: 14),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF141422),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10.0),

          // Episode Grid or List
          Expanded(
            child: filteredEps.isEmpty
                ? const Center(
                    child: Text(
                      'No matching episodes',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : _isGridView
                    ? GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: 6.0,
                          mainAxisSpacing: 6.0,
                          childAspectRatio: 1.1,
                        ),
                        itemCount: filteredEps.length,
                        itemBuilder: (context, index) {
                          final epNum = filteredEps[index];
                          final isCurrent = epNum == _currentEpisode;
                          bool isFiller = false;
                          if (widget.episodesData != null && epNum - 1 < widget.episodesData!.length) {
                            final epObj = widget.episodesData![epNum - 1];
                            if (epObj is Map && (epObj['isFiller'] == true || epObj['filler'] == true)) {
                              isFiller = true;
                            }
                          }

                          return InkWell(
                            onTap: () => _changeEpisode(epNum),
                            borderRadius: BorderRadius.circular(6.0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? Colors.cyanAccent
                                    : const Color(0xFF151524),
                                borderRadius: BorderRadius.circular(6.0),
                                border: Border.all(
                                  color: isCurrent
                                      ? Colors.cyanAccent
                                      : (isFiller ? Colors.orangeAccent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.06)),
                                  width: isCurrent ? 1.5 : 1.0,
                                ),
                                boxShadow: isCurrent
                                    ? [
                                        BoxShadow(
                                          color: Colors.cyanAccent.withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Text(
                                '$epNum',
                                style: TextStyle(
                                  color: isCurrent ? Colors.black : Colors.white,
                                  fontSize: 13.0,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
                        itemCount: filteredEps.length,
                        itemBuilder: (context, index) {
                          final epNum = filteredEps[index];
                          final isCurrent = epNum == _currentEpisode;
                          String epTitle = 'Episode $epNum';
                          if (widget.episodesData != null && epNum - 1 < widget.episodesData!.length) {
                            final epObj = widget.episodesData![epNum - 1];
                            if (epObj is Map && epObj['title'] != null && epObj['title'].toString().isNotEmpty) {
                              epTitle = epObj['title'];
                            }
                          }

                          return InkWell(
                            onTap: () => _changeEpisode(epNum),
                            borderRadius: BorderRadius.circular(6.0),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6.0),
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                              decoration: BoxDecoration(
                                color: isCurrent ? Colors.cyanAccent.withValues(alpha: 0.15) : const Color(0xFF141420),
                                borderRadius: BorderRadius.circular(6.0),
                                border: Border.all(
                                  color: isCurrent ? Colors.cyanAccent : Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isCurrent ? Colors.cyanAccent : Colors.white10,
                                      borderRadius: BorderRadius.circular(4.0),
                                    ),
                                    child: Text(
                                      '$epNum',
                                      style: TextStyle(
                                        color: isCurrent ? Colors.black : Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      epTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent ? Colors.cyanAccent : Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                  ),
                                  if (isCurrent)
                                    const Icon(Icons.volume_up_rounded, color: Colors.cyanAccent, size: 16),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Footer Legend: Canon / Filler
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
            decoration: BoxDecoration(
              color: const Color(0xFF090910),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12.0)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, color: Colors.cyanAccent, size: 7.0),
                const SizedBox(width: 5),
                const Text('Canon', style: TextStyle(color: Colors.white54, fontSize: 10.5, fontFamily: 'Outfit')),
                const SizedBox(width: 14),
                const Icon(Icons.circle, color: Colors.orangeAccent, size: 7.0),
                const SizedBox(width: 5),
                Text('Filler ($fillerCount)', style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontFamily: 'Outfit')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
