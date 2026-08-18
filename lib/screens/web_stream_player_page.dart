import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';
import '../models/web_stream_server.dart';
import '../services/web_stream_service.dart';
import '../state/library_state.dart';
import '../state/navigation_state.dart';

class WebStreamPlayerPage extends StatefulWidget {
  final int anilistId;
  final int? malId;
  final String title;
  final int episode;
  final int totalEpisodes;
  final String? initialServerId;
  final AudioType initialAudioType;
  final NavigationState navigationState;

  const WebStreamPlayerPage({
    super.key,
    required this.anilistId,
    this.malId,
    required this.title,
    required this.episode,
    required this.totalEpisodes,
    this.initialServerId,
    this.initialAudioType = AudioType.sub,
    required this.navigationState,
  });

  @override
  State<WebStreamPlayerPage> createState() => _WebStreamPlayerPageState();
}

class _WebStreamPlayerPageState extends State<WebStreamPlayerPage> {
  late int _currentEpisode;
  late WebStreamServer _selectedServer;
  late AudioType _currentAudioType;
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _isFullscreen = false;
  bool _showControls = true;
  double _progress = 0.0;

  final bool _isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.episode;
    _currentAudioType = widget.initialAudioType;

    final initialId = widget.initialServerId ?? 'megaplay_ani';
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
    });

    final url = _currentStreamUrl;
    if (_webViewController != null) {
      _webViewController!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(url),
          headers: {
            'Referer': 'https://animedex.fun/',
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

  void _showServerSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dns_rounded, color: Colors.cyanAccent, size: 22),
                        const SizedBox(width: 10),
                        const Text(
                          'Select Streaming Server',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...WebStreamService.availableServers.map((server) {
                      final isSelected = server.id == _selectedServer.id;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.cyanAccent.withValues(alpha: 0.12)
                              : const Color(0xFF1E1E2C),
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(
                            color: isSelected ? Colors.cyanAccent : Colors.white12,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
                          leading: Container(
                            padding: const EdgeInsets.all(8.0),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.cyanAccent : Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: isSelected ? Colors.black : Colors.white70,
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                server.name,
                                style: TextStyle(
                                  color: isSelected ? Colors.cyanAccent : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                child: Text(
                                  server.badge,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            server.description,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: Colors.cyanAccent)
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            if (server.id != _selectedServer.id) {
                              setState(() {
                                _selectedServer = server;
                                if (!server.supportsDub && _currentAudioType == AudioType.dub) {
                                  _currentAudioType = AudioType.sub;
                                }
                              });
                              _loadCurrentStream();
                            }
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        child: Column(
          children: [
            // Top Bar
            if (!_isFullscreen || _showControls)
              Container(
                height: 56.0,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F18),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                'Episode $_currentEpisode${widget.totalEpisodes > 0 ? ' / ${widget.totalEpisodes}' : ''}',
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                child: Text(
                                  _selectedServer.name,
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // SUB / DUB Toggle
                    if (_selectedServer.supportsDub)
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2C),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildAudioTab('SUB', AudioType.sub),
                            _buildAudioTab('DUB', AudioType.dub),
                          ],
                        ),
                      ),

                    const SizedBox(width: 8),

                    // Server Switcher Button
                    IconButton(
                      icon: const Icon(Icons.dns_rounded, color: Colors.cyanAccent, size: 20),
                      tooltip: 'Change Server',
                      onPressed: _showServerSelector,
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
              ),

            // Loading Progress Indicator
            if (_isLoading)
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
              ),

            // WebView Stream Area
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
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
                      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
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
                      // Allow main embed hosts
                      if (target.contains('megaplay.buzz') ||
                          target.contains('vidnest.fun') ||
                          target.contains('2embed.cc') ||
                          target.contains('animedex.fun') ||
                          target.contains('cloudflare') ||
                          target.contains('m3u8') ||
                          target.contains('blob:') ||
                          target.contains('google') ||
                          target.contains('about:blank')) {
                        return NavigationActionPolicy.ALLOW;
                      }

                      // Block advertising / redirect popups
                      debugPrint('[WebStreamPlayer] Blocked popup/redirect: $target');
                      return NavigationActionPolicy.CANCEL;
                    },
                  ),

                  // Floating Navigation Controls
                  Positioned(
                    bottom: 16.0,
                    right: 16.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(25.0),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 20),
                            tooltip: 'Previous Episode',
                            onPressed: _currentEpisode > 1
                                ? () => _changeEpisode(_currentEpisode - 1)
                                : null,
                          ),
                          Text(
                            'EP $_currentEpisode',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 20),
                            tooltip: 'Next Episode',
                            onPressed: (widget.totalEpisodes == 0 || _currentEpisode < widget.totalEpisodes)
                                ? () => _changeEpisode(_currentEpisode + 1)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTab(String label, AudioType type) {
    final isSelected = _currentAudioType == type;
    return GestureDetector(
      onTap: () {
        if (_currentAudioType != type) {
          setState(() {
            _currentAudioType = type;
          });
          _loadCurrentStream();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(6.0),
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
}
