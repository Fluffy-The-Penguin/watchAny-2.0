import '../services/notification_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/download_service.dart';
import '../services/manga_download_service.dart';
import '../services/torrserver_service.dart';
import '../models/torrent.dart';
import '../state/player_state.dart';
import '../state/app_settings.dart';
import '../state/navigation_state.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';

class DownloadsPage extends StatefulWidget {
  final AppMode mode;
  const DownloadsPage({super.key, required this.mode});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

enum DownloadsTab { library, overview, settings }

class _DownloadsPageState extends State<DownloadsPage> {
  DownloadsTab _activeTab = DownloadsTab.library;
  String? _selectedTaskId;
  final Set<String> _selectedTaskIds = {};

  List<DownloadTask> get _tasks => DownloadService().tasks.where((t) {
    if (widget.mode == AppMode.movies) {
      return t.isMovie == true || (t.anilistId == null && t.mediaJson != null);
    } else if (widget.mode == AppMode.anime) {
      return t.anilistId != null || (t.isMovie != true && (t.mediaJson == null || (!t.mediaJson!.contains('"type":"series"') && !t.mediaJson!.contains('"type":"movie"'))));
    } else {
      return false;
    }
  }).toList();

  // Settings controllers
  late final TextEditingController _serverUrlController;
  late final TextEditingController _downloadPathController;
  late int _maxConcurrent;
  String _speedLimit = 'Unlimited';

  // Library filters
  String _libraryFilter = 'ALL'; // 'ALL', 'ACTIVE', 'COMPLETED'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Polling for selected task stats
  Timer? _statsTimer;
  TorrentInfo? _selectedTorrentInfo;
  bool _isFetchingStats = false;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(text: AppSettings().torrServerUrl);
    _downloadPathController = TextEditingController(text: AppSettings().downloadPath);
    _maxConcurrent = AppSettings().maxConcurrentDownloads;
    
    // Auto-select first task if available
    final tasks = _tasks;
    if (tasks.isNotEmpty) {
      _selectedTaskId = tasks.first.id;
    }

    // Listen to download changes to auto-select task if none selected
    DownloadService().addListener(_onDownloadTasksChanged);
    MangaDownloadService().addListener(_onDownloadTasksChanged);
    NavigationState().addListener(_onNavigationChanged);

    // Periodic stats polling
    _startStatsPolling();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    DownloadService().removeListener(_onDownloadTasksChanged);
    MangaDownloadService().removeListener(_onDownloadTasksChanged);
    NavigationState().removeListener(_onNavigationChanged);
    _serverUrlController.dispose();
    _downloadPathController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onNavigationChanged() {
    final nav = NavigationState();
    final isCurrentMode = nav.currentMode == widget.mode;
    final isCurrentPage = nav.currentPage == TabPage.downloads;
    if (isCurrentMode && isCurrentPage) {
      _onDownloadTasksChanged();
    }
  }

  void _onDownloadTasksChanged() {
    if (mounted) {
      final nav = NavigationState();
      final isCurrentMode = nav.currentMode == widget.mode;
      final isCurrentPage = nav.currentPage == TabPage.downloads;
      if (isCurrentMode && isCurrentPage) {
        setState(() {
          final tasks = _tasks;
          if (_selectedTaskId == null && tasks.isNotEmpty) {
            _selectedTaskId = tasks.first.id;
          }
        });
      }
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final nav = NavigationState();
      final isCurrentMode = nav.currentMode == widget.mode;
      final isCurrentPage = nav.currentPage == TabPage.downloads;
      if (mounted && isCurrentMode && isCurrentPage && _activeTab == DownloadsTab.overview) {
        _fetchActiveTorrentStats();
      }
    });
  }

  void _navigateToDetails(DownloadTask task) {
    final nav = NavigationState();
    
    if (task.anilistId != null) {
      nav.selectAnime(task.anilistId);
      return;
    }
    
    if (task.mediaJson != null) {
      try {
        final media = jsonDecode(task.mediaJson!);
        final id = media['id']?.toString();
        final type = media['type']?.toString().toLowerCase() ?? (task.isMovie == true ? 'movie' : 'series');
        final anilistId = media['anilistId'] ?? media['id'];
        
        if (widget.mode == AppMode.anime) {
          final parsedAniId = int.tryParse(anilistId.toString());
          if (parsedAniId != null) {
            nav.selectAnime(parsedAniId);
            return;
          }
        }
        
        if (id != null && id.isNotEmpty) {
          final formattedId = id.contains(':') ? id : '$type:$id';
          nav.selectMovie(formattedId);
          return;
        }
      } catch (_) {}
    }

    if (widget.mode == AppMode.anime && task.anilistId != null) {
      nav.selectAnime(task.anilistId);
    }
  }

  Future<void> _fetchActiveTorrentStats() async {
    if (_isFetchingStats) return;
    final tasks = _tasks;
    if (tasks.isEmpty) {
      if (mounted) {
        setState(() {
          _selectedTorrentInfo = null;
        });
      }
      return;
    }

    DownloadTask? selectedTask;
    if (_selectedTaskId != null) {
      for (var t in tasks) {
        if (t.id == _selectedTaskId) {
          selectedTask = t;
          break;
        }
      }
    }

    if (selectedTask == null) {
      selectedTask = tasks.first;
      if (mounted) {
        setState(() {
          _selectedTaskId = selectedTask!.id;
        });
      }
    }

    _isFetchingStats = true;
    try {
      final info = await TorrServerService().getTorrent(selectedTask.hash);
      if (mounted && _selectedTaskId == selectedTask.id) {
        setState(() {
          _selectedTorrentInfo = info;
        });
      }
    } catch (_) {
      // Gracefully handle server offline or torrent unregistered
    } finally {
      _isFetchingStats = false;
    }
  }

  void _selectTask(String taskId) {
    setState(() {
      _selectedTaskId = taskId;
      _selectedTorrentInfo = null; // Reset stats while loading
    });
    _fetchActiveTorrentStats();
  }

  String _formatBytes(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return "0 B/s";
    const suffixes = ["B/s", "KB/s", "MB/s", "GB/s"];
    var i = (log(bytesPerSecond) / log(1024)).floor();
    return '${(bytesPerSecond / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  void _playLocalFile(DownloadTask task) {
    final file = File(task.savePath);
    if (!file.existsSync()) {
      NotificationService().show(context, "Local download file not found! It might have been deleted from storage.", isError: true);
      return;
    }

    PlayerState().startPlayback(
      streamUrl: task.savePath,
      title: task.title,
      anilistId: task.anilistId,
      titles: task.titles ?? const [],
      episodeCount: task.episodeCount ?? 0,
      episodeNumber: task.episodeNumber ?? 1,
      isMovie: task.isMovie ?? false,
      media: task.mediaJson != null ? jsonDecode(task.mediaJson!) : null,
      episodes: task.episodesJson != null ? jsonDecode(task.episodesJson!) : null,
    );
  }

  void _showDeleteDialog(BuildContext context, List<String> taskIds) {
    bool deleteFromDisk = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F11),
              title: Text(
                taskIds.length == 1 ? "Delete Download?" : "Delete ${taskIds.length} Downloads?",
                style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    taskIds.length == 1
                        ? "Are you sure you want to remove this download task?"
                        : "Are you sure you want to remove the selected ${taskIds.length} download tasks?",
                    style: const TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit'),
                  ),
                  const SizedBox(height: 16.0),
                  CheckboxListTile(
                    title: const Text(
                      "Also delete files from device storage",
                      style: TextStyle(color: Colors.white60, fontSize: 12.0, fontFamily: 'Outfit'),
                    ),
                    value: deleteFromDisk,
                    dense: true,
                    activeColor: Colors.redAccent,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          deleteFromDisk = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white70, fontFamily: 'Outfit')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    for (var id in taskIds) {
                      await DownloadService().removeDownload(id, deleteFile: deleteFromDisk);
                    }
                    setState(() {
                      _selectedTaskIds.removeAll(taskIds);
                    });
                  },
                  child: const Text("Delete", style: TextStyle(fontFamily: 'Outfit')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 750;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // Sidebar Navigation
          if (!isMobile) _buildSidebar(),
          if (!isMobile) Container(width: 1.0, color: Colors.white10),
          
          // Main content pane
          Expanded(
            child: Column(
              children: [
                if (isMobile) _buildMobileHeader(),
                Expanded(
                  child: _buildActiveTabContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 220.0,
      color: const Color(0xFF09090B),
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Client Header
          const Text(
            'Downloads',
            style: TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 4.0),
          const Text(
            'Monitor and manage offline downloads.',
            style: TextStyle(color: Colors.white38, fontSize: 10.5, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 32.0),

          // Navigation Links
          _buildSidebarNavItem(DownloadsTab.library, 'Library', Icons.library_books_outlined),
          _buildSidebarNavItem(DownloadsTab.overview, 'Overview', Icons.dashboard_outlined),
          _buildSidebarNavItem(DownloadsTab.settings, 'Settings', Icons.settings_outlined),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem(DownloadsTab tab, String label, IconData icon) {
    final bool isActive = _activeTab == tab;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        onTap: () {
          setState(() {
            _activeTab = tab;
          });
          if (tab == DownloadsTab.overview) {
            _fetchActiveTorrentStats();
          }
        },
        borderRadius: BorderRadius.circular(8.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: isActive ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isActive ? const Color(0xFF3A86FF) : Colors.white54,
                size: 18.0,
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white54,
                    fontSize: 13.0,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    fontFamily: 'Outfit',
                  ),
                ),
              ),
              if (isActive)
                Container(
                  width: 4.0,
                  height: 4.0,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF3A86FF),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Container(
      color: const Color(0xFF09090B),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Downloads',
                style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
                onPressed: () {
                  setState(() {
                    _activeTab = DownloadsTab.settings;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildMobileHeaderTab(DownloadsTab.library, 'Library'),
                _buildMobileHeaderTab(DownloadsTab.overview, 'Overview'),
                _buildMobileHeaderTab(DownloadsTab.settings, 'Settings'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeaderTab(DownloadsTab tab, String label) {
    final bool isActive = _activeTab == tab;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = tab;
        });
        if (tab == DownloadsTab.overview) {
          _fetchActiveTorrentStats();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12.0),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white10,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white70,
            fontSize: 11.5,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            fontFamily: 'Outfit',
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case DownloadsTab.library:
        return _buildLibraryTab();
      case DownloadsTab.overview:
        return _buildOverviewTab();
      case DownloadsTab.settings:
        return _buildSettingsTab();
    }
  }

  // --- 1. LIBRARY TAB ---
  Widget _buildLibraryTab() {
    if (widget.mode == AppMode.manga) {
      return _buildMangaLibraryTab();
    }

    final bool isMobile = MediaQuery.of(context).size.width < 750;

    return ListenableBuilder(
      listenable: Listenable.merge([DownloadService(), MangaDownloadService()]),
      builder: (context, _) {
        final allTasks = _tasks;
        
        // Apply status filter
        List<DownloadTask> tasks = allTasks;
        if (_libraryFilter == 'ACTIVE') {
          tasks = allTasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued || t.status == DownloadStatus.paused || t.status == DownloadStatus.failed).toList();
        } else if (_libraryFilter == 'COMPLETED') {
          tasks = allTasks.where((t) => t.status == DownloadStatus.completed).toList();
        }

        // Apply search query
        if (_searchQuery.isNotEmpty) {
          tasks = tasks.where((t) => t.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
        }

        final inProgressTasks = tasks.where((t) => t.status != DownloadStatus.completed).toList();
        final completedTasks = tasks.where((t) => t.status == DownloadStatus.completed).toList();

        return Column(
          children: [
            _buildLibraryHeader(tasks, allTasks),
            Expanded(
              child: tasks.isEmpty
                  ? _buildEmptyState()
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      children: [
                        if (inProgressTasks.isNotEmpty) ...[
                          _buildSectionHeader('IN PROGRESS & QUEUED', inProgressTasks.length, Colors.blueAccent),
                          const SizedBox(height: 8.0),
                          ...inProgressTasks.map((t) => _buildDownloadCard(t, isMobile)),
                          const SizedBox(height: 16.0),
                        ],
                        if (completedTasks.isNotEmpty) ...[
                          _buildSectionHeader('DOWNLOADED & COMPLETED', completedTasks.length, Colors.green),
                          const SizedBox(height: 8.0),
                          ...completedTasks.map((t) => _buildDownloadCard(t, isMobile)),
                          const SizedBox(height: 16.0),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, top: 4.0),
      child: Row(
        children: [
          Container(
            width: 3.0,
            height: 14.0,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
          const SizedBox(width: 8.0),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              fontFamily: 'Outfit',
            ),
          ),
          const SizedBox(width: 8.0),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 10.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(DownloadTask task, bool isMobile) {
    final isSelected = _selectedTaskIds.contains(task.id);
    final double progress = task.totalBytes > 0 ? (task.downloadedBytes / task.totalBytes) : 0.0;
    
    Color statusColor = Colors.white30;
    String statusName = 'Queued';
    if (task.status == DownloadStatus.downloading) {
      statusColor = Colors.blueAccent;
      statusName = 'Downloading';
    } else if (task.status == DownloadStatus.completed) {
      statusColor = Colors.green;
      statusName = 'Completed';
    } else if (task.status == DownloadStatus.paused) {
      statusColor = Colors.white54;
      statusName = 'Paused';
    } else if (task.status == DownloadStatus.failed) {
      statusColor = Colors.redAccent;
      statusName = 'Failed';
    }

    final isCurrentTask = _selectedTaskId == task.id;

    Map<String, dynamic>? media;
    if (task.mediaJson != null) {
      try {
        media = jsonDecode(task.mediaJson!);
      } catch (_) {}
    }
    final String coverUrl = task.isMovie == true
        ? (media?['poster'] ?? '')
        : (media?['coverImage']?['large'] ?? media?['coverImage']?['medium'] ?? '');

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10.0),
        decoration: BoxDecoration(
          color: isCurrentTask ? Colors.white.withValues(alpha: 0.03) : const Color(0xFF0F0F11),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isCurrentTask ? Colors.white30 : Colors.white.withValues(alpha: 0.05),
            width: 1.0,
          ),
        ),
        child: InkWell(
          onTap: () {
            _selectTask(task.id);
          },
          onDoubleTap: () {
            _selectTask(task.id);
            setState(() {
              _activeTab = DownloadsTab.overview;
            });
          },
          borderRadius: BorderRadius.circular(11.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: isSelected,
                            activeColor: Colors.white,
                            checkColor: Colors.black,
                            side: const BorderSide(color: Colors.white38),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedTaskIds.add(task.id);
                                } else {
                                  _selectedTaskIds.remove(task.id);
                                }
                              });
                            },
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6.0),
                            child: SizedBox(
                              width: 36.0,
                              height: 52.0,
                              child: coverUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 100,
                                      placeholder: (c, u) => Container(color: Colors.white10),
                                      errorWidget: (c, u, e) => Container(color: Colors.white10),
                                    )
                                  : Container(color: Colors.white10, child: const Icon(Icons.movie, size: 16, color: Colors.white24)),
                            ),
                          ),
                          const SizedBox(width: 10.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4.0),
                                  ),
                                  child: Text(
                                    statusName.toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10.0),
                      // Progress Bar
                      Container(
                        height: 4.0,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(2.0),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(2.0),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)} · ${(progress * 100).toStringAsFixed(1)}%",
                            style: const TextStyle(color: Colors.white38, fontSize: 10.0, fontFamily: 'Outfit'),
                          ),
                          if (task.status == DownloadStatus.downloading)
                            Text(
                              _formatSpeed(task.downloadSpeed),
                              style: const TextStyle(color: Colors.blueAccent, fontSize: 10.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 18),
                            tooltip: 'Go to Details',
                            onPressed: () => _navigateToDetails(task),
                          ),
                          IconButton(
                            icon: const Icon(Icons.dashboard_outlined, color: Colors.white38, size: 18),
                            tooltip: 'Show Overview',
                            onPressed: () {
                              _selectTask(task.id);
                              setState(() {
                                _activeTab = DownloadsTab.overview;
                              });
                            },
                          ),
                          if (task.status == DownloadStatus.completed)
                            IconButton(
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.green, size: 22),
                              tooltip: 'Play Offline',
                              onPressed: () => _playLocalFile(task),
                            ),
                          if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
                            IconButton(
                              icon: const Icon(Icons.pause, color: Colors.white54, size: 18),
                              tooltip: 'Pause',
                              onPressed: () => DownloadService().pauseDownload(task.id),
                            )
                          else if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
                            IconButton(
                              icon: const Icon(Icons.play_arrow, color: Colors.white54, size: 18),
                              tooltip: 'Resume',
                              onPressed: () => DownloadService().resumeDownload(task.id),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                            tooltip: 'Remove',
                            onPressed: () => _showDeleteDialog(context, [task.id]),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        activeColor: Colors.white,
                        checkColor: Colors.black,
                        side: const BorderSide(color: Colors.white38),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedTaskIds.add(task.id);
                            } else {
                              _selectedTaskIds.remove(task.id);
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8.0),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6.0),
                        child: SizedBox(
                          width: 36.0,
                          height: 52.0,
                          child: coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: coverUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 100,
                                  placeholder: (c, u) => Container(color: Colors.white10),
                                  errorWidget: (c, u, e) => Container(color: Colors.white10),
                                )
                              : Container(color: Colors.white10, child: const Icon(Icons.movie, size: 16, color: Colors.white24)),
                        ),
                      ),
                      const SizedBox(width: 14.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    task.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12.0),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4.0),
                                  ),
                                  child: Text(
                                    statusName.toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 9.0,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8.0),
                            Container(
                              height: 4.0,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(2.0),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: progress.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      borderRadius: BorderRadius.circular(2.0),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6.0),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)} · ${(progress * 100).toStringAsFixed(1)}%",
                                  style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontFamily: 'Outfit'),
                                ),
                                if (task.status == DownloadStatus.downloading)
                                  Text(
                                    _formatSpeed(task.downloadSpeed),
                                    style: const TextStyle(color: Colors.blueAccent, fontSize: 10.5, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 18),
                            tooltip: 'Go to Details',
                            onPressed: () => _navigateToDetails(task),
                          ),
                          IconButton(
                            icon: const Icon(Icons.dashboard_outlined, color: Colors.white38, size: 18),
                            tooltip: 'Show Overview',
                            onPressed: () {
                              _selectTask(task.id);
                              setState(() {
                                _activeTab = DownloadsTab.overview;
                              });
                            },
                          ),
                          if (task.status == DownloadStatus.completed)
                            IconButton(
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.green, size: 22),
                              tooltip: 'Play Offline',
                              onPressed: () => _playLocalFile(task),
                            ),
                          if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
                            IconButton(
                              icon: const Icon(Icons.pause, color: Colors.white54, size: 18),
                              tooltip: 'Pause',
                              onPressed: () => DownloadService().pauseDownload(task.id),
                            )
                          else if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
                            IconButton(
                              icon: const Icon(Icons.play_arrow, color: Colors.white54, size: 18),
                              tooltip: 'Resume',
                              onPressed: () => DownloadService().resumeDownload(task.id),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                            tooltip: 'Remove',
                            onPressed: () => _showDeleteDialog(context, [task.id]),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildMangaLibraryTab() {
    return ListenableBuilder(
      listenable: MangaDownloadService(),
      builder: (context, _) {
        final allTasks = MangaDownloadService().tasks;
        List<MangaDownloadTask> tasks = allTasks;
        if (_libraryFilter == 'ACTIVE') {
          tasks = allTasks.where((t) => t.status == MangaDownloadStatus.downloading || t.status == MangaDownloadStatus.queued).toList();
        } else if (_libraryFilter == 'COMPLETED') {
          tasks = allTasks.where((t) => t.status == MangaDownloadStatus.completed).toList();
        }
        if (_searchQuery.isNotEmpty) {
          tasks = tasks.where((t) => '${t.mangaTitle} ${t.chapterName}'.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
        }

        return Column(
          children: [
            _buildMangaLibraryHeader(tasks, allTasks),
            Expanded(
              child: tasks.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final double progress = task.progress;
                        
                        Color statusColor = Colors.white30;
                        String statusName = 'Queued';
                        if (task.status == MangaDownloadStatus.downloading) {
                          statusColor = Colors.blueAccent;
                          statusName = 'Downloading';
                        } else if (task.status == MangaDownloadStatus.completed) {
                          statusColor = Colors.green;
                          statusName = 'Completed';
                        } else if (task.status == MangaDownloadStatus.paused) {
                          statusColor = Colors.white54;
                          statusName = 'Paused';
                        } else if (task.status == MangaDownloadStatus.failed) {
                          statusColor = Colors.redAccent;
                          statusName = 'Failed';
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F0F11),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                              width: 1.0,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 36.0,
                                  height: 52.0,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(6.0),
                                  ),
                                  child: const Icon(Icons.book_outlined, color: Colors.white38, size: 20),
                                ),
                                const SizedBox(width: 14.0),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "${task.mangaTitle} — ${task.chapterName}",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Outfit',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12.0),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(4.0),
                                            ),
                                            child: Text(
                                              statusName.toUpperCase(),
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 9.0,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Outfit',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8.0),
                                      Container(
                                        height: 4.0,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.04),
                                          borderRadius: BorderRadius.circular(2.0),
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FractionallySizedBox(
                                            widthFactor: progress.clamp(0.0, 1.0),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: statusColor,
                                                borderRadius: BorderRadius.circular(2.0),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6.0),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "${task.downloadedPages} / ${task.totalPages} pages · ${(progress * 100).toStringAsFixed(0)}%",
                                            style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontFamily: 'Outfit'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16.0),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (task.status == MangaDownloadStatus.downloading)
                                      IconButton(
                                        icon: const Icon(Icons.pause, color: Colors.white54, size: 18),
                                        onPressed: () => MangaDownloadService().pause(task.id),
                                      )
                                    else if (task.status == MangaDownloadStatus.paused)
                                      IconButton(
                                        icon: const Icon(Icons.play_arrow, color: Colors.white54, size: 18),
                                        onPressed: () => MangaDownloadService().resume(task.id),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                      onPressed: () => MangaDownloadService().cancel(task.id),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMangaLibraryHeader(List<MangaDownloadTask> tasks, List<MangaDownloadTask> allTasks) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manga Downloads',
                    style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    '${allTasks.length} total chapter downloads',
                    style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 12.0, fontFamily: 'Outfit'),
                  decoration: InputDecoration(
                    hintText: 'Search downloaded manga...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 12.0, fontFamily: 'Outfit'),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
                    filled: true,
                    fillColor: const Color(0xFF0F0F11),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0.0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12.0),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F11),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _libraryFilter,
                    dropdownColor: const Color(0xFF0F0F11),
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontFamily: 'Outfit'),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Downloads')),
                      DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                      DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _libraryFilter = val;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryHeader(List<DownloadTask> tasks, List<DownloadTask> allTasks) {
    final bool isMultiSelectActive = _selectedTaskIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Download Library',
                    style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    '${allTasks.length} tasks total · ${_selectedTaskIds.length} selected',
                    style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
                  ),
                ],
              ),
              
              // Filter options
              Container(
                height: 32.0,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: Colors.white10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _libraryFilter,
                    dropdownColor: const Color(0xFF0F0F11),
                    borderRadius: BorderRadius.circular(6.0),
                    style: const TextStyle(color: Colors.white70, fontSize: 11.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 16),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _libraryFilter = val;
                        });
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Downloads')),
                      DropdownMenuItem(value: 'ACTIVE', child: Text('Active Only')),
                      DropdownMenuItem(value: 'COMPLETED', child: Text('Completed Only')),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          
          // Action Bar (Multi-Select or Search)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: isMultiSelectActive
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selectedTaskIds.length == tasks.length && tasks.isNotEmpty,
                          activeColor: Colors.white,
                          checkColor: Colors.black,
                          side: const BorderSide(color: Colors.white38),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedTaskIds.addAll(tasks.map((t) => t.id));
                              } else {
                                _selectedTaskIds.removeAll(tasks.map((t) => t.id));
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          '${_selectedTaskIds.length} Selected',
                          style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                        ),
                        const Spacer(),
                        
                        // Action buttons
                        MediaQuery.of(context).size.width < 750
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.play_arrow_outlined, size: 20, color: Colors.white70),
                                    onPressed: () {
                                      for (var id in _selectedTaskIds) {
                                        DownloadService().resumeDownload(id);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.pause_outlined, size: 20, color: Colors.white70),
                                    onPressed: () {
                                      for (var id in _selectedTaskIds) {
                                        DownloadService().pauseDownload(id);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                    onPressed: () {
                                      _showDeleteDialog(context, _selectedTaskIds.toList());
                                    },
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.play_arrow_outlined, size: 16, color: Colors.white70),
                                    label: const Text('Resume', style: TextStyle(color: Colors.white70, fontSize: 11.0)),
                                    onPressed: () {
                                      for (var id in _selectedTaskIds) {
                                        DownloadService().resumeDownload(id);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8.0),
                                  TextButton.icon(
                                    icon: const Icon(Icons.pause_outlined, size: 16, color: Colors.white70),
                                    label: const Text('Pause', style: TextStyle(color: Colors.white70, fontSize: 11.0)),
                                    onPressed: () {
                                      for (var id in _selectedTaskIds) {
                                        DownloadService().pauseDownload(id);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8.0),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.delete_outline, size: 14, color: Colors.white),
                                    label: const Text('Delete', style: TextStyle(color: Colors.white, fontSize: 11.0, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
                                    ),
                                    onPressed: () {
                                      _showDeleteDialog(context, _selectedTaskIds.toList());
                                    },
                                  ),
                                ],
                              ),
                      ],
                    ),
                  )
                : Container(
                    height: 38.0,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8.0),
                        hintText: 'Search downloads list...',
                        hintStyle: TextStyle(color: Colors.white24, fontSize: 12.0, fontFamily: 'Outfit'),
                        prefixIcon: Icon(Icons.search, color: Colors.white38, size: 16),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 38,
                          maxHeight: 38,
                        ),
                        border: InputBorder.none,
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open_outlined, size: 48, color: Colors.white12),
          const SizedBox(height: 12.0),
          Text(
            _searchQuery.isNotEmpty ? 'No matches found in library' : 'No items in this category',
            style: const TextStyle(color: Colors.white38, fontSize: 13.0, fontFamily: 'Outfit'),
          ),
        ],
      ),
    );
  }

  // --- 2. OVERVIEW TAB ---
  Widget _buildOverviewTab() {
    final tasks = _tasks;
    final bool isMobile = MediaQuery.of(context).size.width < 750;

    double totalActiveSpeed = 0.0;
    int activeCount = 0;
    int completedCount = 0;
    int totalDownloadedBytes = 0;

    for (var t in tasks) {
      if (t.status == DownloadStatus.downloading) {
        totalActiveSpeed += t.downloadSpeed;
        activeCount++;
      } else if (t.status == DownloadStatus.queued) {
        activeCount++;
      } else if (t.status == DownloadStatus.completed) {
        completedCount++;
        totalDownloadedBytes += t.downloadedBytes;
      }
    }

    DownloadTask? selectedTask;
    if (_selectedTaskId != null) {
      for (var t in tasks) {
        if (t.id == _selectedTaskId) {
          selectedTask = t;
          break;
        }
      }
    }
    selectedTask ??= tasks.isNotEmpty ? tasks.first : null;

    return Padding(
      padding: isMobile
          ? const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0)
          : const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Summary Dashboard Banner
          _buildOverviewStatsBanner(totalActiveSpeed, activeCount, completedCount, totalDownloadedBytes, isMobile),
          const SizedBox(height: 20.0),

          // 2. Main Content Split View (Master-Detail Pane)
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptyState()
                : (isMobile
                    ? _buildMobileOverviewBody(tasks, selectedTask)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Task List Panel (Width 340)
                          SizedBox(
                            width: 340.0,
                            child: _buildOverviewTaskListPanel(tasks, selectedTask),
                          ),
                          const SizedBox(width: 20.0),
                          // Right Task Detail Inspector Panel
                          Expanded(
                            child: _buildOverviewTaskInspectorPanel(selectedTask),
                          ),
                        ],
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewStatsBanner(double totalSpeed, int activeCount, int completedCount, int totalStorage, bool isMobile) {
    return isMobile
        ? Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildOverviewStatCard(Icons.speed_rounded, Colors.cyanAccent, 'ACTIVE SPEED', totalSpeed > 0 ? _formatSpeed(totalSpeed) : 'Idle')),
                  const SizedBox(width: 10.0),
                  Expanded(child: _buildOverviewStatCard(Icons.downloading_rounded, Colors.blueAccent, 'IN PROGRESS', '$activeCount Active')),
                ],
              ),
              const SizedBox(height: 10.0),
              Row(
                children: [
                  Expanded(child: _buildOverviewStatCard(Icons.check_circle_outline_rounded, Colors.greenAccent, 'COMPLETED', '$completedCount Items')),
                  const SizedBox(width: 10.0),
                  Expanded(child: _buildOverviewStatCard(Icons.sd_storage_rounded, Colors.purpleAccent, 'STORAGE USED', _formatBytes(totalStorage))),
                ],
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: _buildOverviewStatCard(Icons.speed_rounded, Colors.cyanAccent, 'ACTIVE SPEED', totalSpeed > 0 ? _formatSpeed(totalSpeed) : 'Idle')),
              const SizedBox(width: 14.0),
              Expanded(child: _buildOverviewStatCard(Icons.downloading_rounded, Colors.blueAccent, 'IN PROGRESS', '$activeCount Active')),
              const SizedBox(width: 14.0),
              Expanded(child: _buildOverviewStatCard(Icons.check_circle_outline_rounded, Colors.greenAccent, 'COMPLETED', '$completedCount Items')),
              const SizedBox(width: 14.0),
              Expanded(child: _buildOverviewStatCard(Icons.sd_storage_rounded, Colors.purpleAccent, 'STORAGE USED', _formatBytes(totalStorage))),
            ],
          );
  }

  Widget _buildOverviewStatCard(IconData icon, Color iconColor, String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F11),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8.0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white38, fontSize: 10.0, fontWeight: FontWeight.bold, letterSpacing: 0.5, fontFamily: 'Outfit'),
                ),
                const SizedBox(height: 3.0),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileOverviewBody(List<DownloadTask> tasks, DownloadTask? selectedTask) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(
            height: 280,
            child: _buildOverviewTaskListPanel(tasks, selectedTask),
          ),
          const SizedBox(height: 16.0),
          _buildOverviewTaskInspectorPanel(selectedTask),
        ],
      ),
    );
  }

  Widget _buildOverviewTaskListPanel(List<DownloadTask> tasks, DownloadTask? selectedTask) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0E),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
            child: Row(
              children: [
                const Icon(Icons.list_alt_rounded, color: Colors.white70, size: 18),
                const SizedBox(width: 8.0),
                const Text(
                  'Tasks List',
                  style: TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1.0, color: Colors.white10),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
              itemCount: tasks.length,
              separatorBuilder: (c, i) => const SizedBox(height: 6.0),
              itemBuilder: (context, index) {
                final task = tasks[index];
                final isSelected = selectedTask?.id == task.id;
                final double progress = task.totalBytes > 0 ? (task.downloadedBytes / task.totalBytes) : 0.0;

                Map<String, dynamic>? media;
                if (task.mediaJson != null) {
                  try {
                    media = jsonDecode(task.mediaJson!);
                  } catch (_) {}
                }
                final String coverUrl = task.isMovie == true
                    ? (media?['poster'] ?? '')
                    : (media?['coverImage']?['large'] ?? media?['coverImage']?['medium'] ?? '');

                return InkWell(
                  onTap: () {
                    _selectTask(task.id);
                  },
                  borderRadius: BorderRadius.circular(10.0),
                  child: Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF3A86FF).withValues(alpha: 0.6) : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6.0),
                          child: SizedBox(
                            width: 38.0,
                            height: 52.0,
                            child: coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: coverUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 100,
                                    errorWidget: (c, u, e) => Container(color: Colors.white10, child: const Icon(Icons.movie, size: 16, color: Colors.white24)),
                                  )
                                : Container(color: Colors.white10, child: const Icon(Icons.movie, size: 16, color: Colors.white24)),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                              const SizedBox(height: 4.0),
                              Row(
                                children: [
                                  Text(
                                    task.status == DownloadStatus.completed
                                        ? _formatBytes(task.totalBytes)
                                        : (task.status == DownloadStatus.downloading
                                            ? _formatSpeed(task.downloadSpeed)
                                            : task.status.name.toUpperCase()),
                                    style: TextStyle(
                                      color: task.status == DownloadStatus.completed
                                          ? Colors.greenAccent
                                          : (task.status == DownloadStatus.downloading ? Colors.blueAccent : Colors.white38),
                                      fontSize: 10.0,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${(progress * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(color: Colors.white54, fontSize: 10.0, fontFamily: 'Outfit'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4.0),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2.0),
                                child: LinearProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  minHeight: 3.0,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    task.status == DownloadStatus.completed ? Colors.green : Colors.blueAccent,
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
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTaskInspectorPanel(DownloadTask? task) {
    if (task == null) {
      return _buildNoTaskPlaceholder("Select a download task to view full details.");
    }

    final double progress = task.totalBytes > 0 ? (task.downloadedBytes / task.totalBytes) : 0.0;
    final String progressPercent = (progress * 100).toStringAsFixed(1);

    Color statusColor = Colors.white30;
    String statusLabel = 'Queued';
    if (task.status == DownloadStatus.downloading) {
      statusColor = Colors.blueAccent;
      statusLabel = 'Downloading';
    } else if (task.status == DownloadStatus.completed) {
      statusColor = Colors.green;
      statusLabel = 'Completed';
    } else if (task.status == DownloadStatus.paused) {
      statusColor = Colors.white54;
      statusLabel = 'Paused';
    } else if (task.status == DownloadStatus.failed) {
      statusColor = Colors.redAccent;
      statusLabel = 'Failed';
    }

    String remainingTime = "Finished";
    if (task.status == DownloadStatus.paused) {
      remainingTime = "Paused";
    } else if (task.status == DownloadStatus.downloading && task.downloadSpeed > 0) {
      final remainingBytes = task.totalBytes - task.downloadedBytes;
      final seconds = remainingBytes / task.downloadSpeed;
      if (seconds < 60) {
        remainingTime = "${seconds.toStringAsFixed(0)}s";
      } else if (seconds < 3600) {
        remainingTime = "${(seconds / 60).floor()}m ${(seconds % 60).toStringAsFixed(0)}s";
      } else {
        remainingTime = "${(seconds / 3600).floor()}h ${((seconds % 3600) / 60).floor()}m";
      }
    }

    Map<String, dynamic>? media;
    if (task.mediaJson != null) {
      try {
        media = jsonDecode(task.mediaJson!);
      } catch (_) {}
    }
    final String coverUrl = task.isMovie == true
        ? (media?['poster'] ?? '')
        : (media?['coverImage']?['large'] ?? media?['coverImage']?['medium'] ?? '');

    final activePeers = _selectedTorrentInfo?.activePeers ?? 0;
    final totalPeers = _selectedTorrentInfo?.totalPeers ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0E),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10.0),
                  child: SizedBox(
                    width: 80.0,
                    height: 116.0,
                    child: coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            errorWidget: (c, u, e) => Container(color: Colors.white10, child: const Icon(Icons.movie, size: 32, color: Colors.white24)),
                          )
                        : Container(color: Colors.white10, child: const Icon(Icons.movie, size: 32, color: Colors.white24)),
                  ),
                ),
                const SizedBox(width: 18.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(color: Colors.white, fontSize: 17.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              statusLabel.toUpperCase(),
                              style: TextStyle(color: statusColor, fontSize: 9.5, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              task.isMovie == true ? 'MOVIE / SERIES' : 'ANIME',
                              style: const TextStyle(color: Colors.white60, fontSize: 9.5, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14.0),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('Play Video', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 12.0)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3A86FF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            ),
                            onPressed: () => _playLocalFile(task),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new_rounded, size: 14),
                            label: const Text('Details Page', style: TextStyle(fontFamily: 'Outfit', fontSize: 12.0)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            ),
                            onPressed: () => _navigateToDetails(task),
                          ),
                          if (task.status == DownloadStatus.downloading)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.pause_rounded, size: 14),
                              label: const Text('Pause', style: TextStyle(fontFamily: 'Outfit', fontSize: 12.0)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              ),
                              onPressed: () => DownloadService().pauseDownload(task.id),
                            )
                          else if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.play_arrow_rounded, size: 14),
                              label: const Text('Resume', style: TextStyle(fontFamily: 'Outfit', fontSize: 12.0)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              ),
                              onPressed: () => DownloadService().resumeDownload(task.id),
                            ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
                            label: const Text('Delete', style: TextStyle(fontFamily: 'Outfit', fontSize: 12.0, color: Colors.redAccent)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            ),
                            onPressed: () => _showDeleteDialog(context, [task.id]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20.0),
            const Divider(height: 1.0, color: Colors.white10),
            const SizedBox(height: 16.0),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Progress & Transfer Status',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                ),
                Text(
                  '$progressPercent%',
                  style: const TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            Container(
              height: 7.0,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [statusColor.withValues(alpha: 0.6), statusColor],
                      ),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            Row(
              children: [
                Expanded(child: _buildInspectorMetricTile(Icons.download_rounded, Colors.greenAccent, 'DOWNLOADED', _formatBytes(task.downloadedBytes))),
                const SizedBox(width: 10.0),
                Expanded(child: _buildInspectorMetricTile(Icons.storage_rounded, Colors.purpleAccent, 'FILE SIZE', _formatBytes(task.totalBytes))),
                const SizedBox(width: 10.0),
                Expanded(child: _buildInspectorMetricTile(Icons.speed_rounded, Colors.blueAccent, 'SPEED', task.status == DownloadStatus.downloading ? _formatSpeed(task.downloadSpeed) : '0 B/s')),
                const SizedBox(width: 10.0),
                Expanded(child: _buildInspectorMetricTile(Icons.hourglass_bottom_rounded, Colors.orangeAccent, 'REMAINING', remainingTime)),
              ],
            ),
            const SizedBox(height: 20.0),
            const Divider(height: 1.0, color: Colors.white10),
            const SizedBox(height: 16.0),

            const Text(
              'Storage & Save Location',
              style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
            ),
            const SizedBox(height: 10.0),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F11),
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined, color: Colors.white54, size: 15),
                      const SizedBox(width: 8.0),
                      const Text('Path: ', style: TextStyle(color: Colors.white54, fontSize: 11.0, fontFamily: 'Outfit')),
                      Expanded(
                        child: Text(
                          task.savePath,
                          style: const TextStyle(color: Colors.white, fontSize: 11.0, fontWeight: FontWeight.w500, fontFamily: 'Outfit'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (task.hash.isNotEmpty) ...[
                    const SizedBox(height: 6.0),
                    Row(
                      children: [
                        const Icon(Icons.tag_rounded, color: Colors.white54, size: 15),
                        const SizedBox(width: 8.0),
                        const Text('Torrent Hash: ', style: TextStyle(color: Colors.white54, fontSize: 11.0, fontFamily: 'Outfit')),
                        Expanded(
                          child: Text(
                            task.hash,
                            style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Row(
                      children: [
                        const Icon(Icons.people_outline_rounded, color: Colors.white54, size: 15),
                        const SizedBox(width: 8.0),
                        Text(
                          'TorrServer Peers: $activePeers / $totalPeers',
                          style: const TextStyle(color: Colors.white70, fontSize: 11.0, fontFamily: 'Outfit'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorMetricTile(IconData icon, Color iconColor, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F11),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 13),
              const SizedBox(width: 4.0),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 8.5, fontFamily: 'Outfit', fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildNoTaskPlaceholder(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dashboard_outlined, size: 48.0, color: Colors.white12),
          const SizedBox(height: 16.0),
          Text(
            msg,
            style: const TextStyle(color: Colors.white38, fontSize: 13.0, fontFamily: 'Outfit'),
          ),
        ],
      ),
    );
  }

  // --- 3. SETTINGS TAB ---
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Client Configurations',
            style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 4.0),
          const Text(
            'Adjust download speed limits and server connection details.',
            style: TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 24.0),

          // 1. TorrServer URL
          const Text(
            'TorrServer URL',
            style: TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 8.0),
          TextField(
            controller: _serverUrlController,
            style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              hintText: 'e.g. http://127.0.0.1:8090',
              hintStyle: const TextStyle(color: Colors.white24),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white10)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white38)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
            ),
          ),
          const SizedBox(height: 20.0),

          // 2. Download Save Directory
          const Text(
            'Default Download Path',
            style: TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 8.0),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _downloadPathController,
                  style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.03),
                    hintText: Platform.isAndroid
                        ? 'Leave empty for default app storage'
                        : 'Leave empty for default (Downloads/watchAny)',
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white10)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white10)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white38)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              IconButton(
                tooltip: 'Browse Folder',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                  padding: const EdgeInsets.all(12.0),
                ),
                icon: const Icon(Icons.folder_open_rounded, color: Colors.white),
                onPressed: () async {
                  try {
                    final path = await FilePicker.getDirectoryPath();
                    if (path != null && path.isNotEmpty) {
                      setState(() {
                        _downloadPathController.text = path;
                      });
                    }
                  } catch (e) {
                    if (mounted) {
                      NotificationService().show(context, 'Could not pick directory: $e');
                    }
                  }
                },
              ),
              const SizedBox(width: 4.0),
              IconButton(
                tooltip: 'Reset to Default',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                  padding: const EdgeInsets.all(12.0),
                ),
                icon: const Icon(Icons.restart_alt_rounded, color: Colors.redAccent),
                onPressed: () {
                  setState(() {
                    _downloadPathController.text = '';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 20.0),

          // 3. Max Concurrent Downloads
          const Text(
            'Max Active Downloads',
            style: TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 8.0),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _maxConcurrent,
                dropdownColor: const Color(0xFF0F0F11),
                style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
                isExpanded: true,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _maxConcurrent = val;
                    });
                    AppSettings().setMaxConcurrentDownloads(val);
                  }
                },
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 download')),
                  DropdownMenuItem(value: 2, child: Text('2 downloads (Recommended)')),
                  DropdownMenuItem(value: 3, child: Text('3 downloads')),
                  DropdownMenuItem(value: 5, child: Text('5 downloads')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20.0),

          // 4. Download Speed Limit
          const Text(
            'Download Speed Limit',
            style: TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 8.0),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _speedLimit,
                dropdownColor: const Color(0xFF0F0F11),
                style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
                isExpanded: true,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _speedLimit = val;
                    });
                  }
                },
                items: const [
                  DropdownMenuItem(value: 'Unlimited', child: Text('Unlimited speed')),
                  DropdownMenuItem(value: '1MB', child: Text('1 MB/s')),
                  DropdownMenuItem(value: '5MB', child: Text('5 MB/s')),
                  DropdownMenuItem(value: '10MB', child: Text('10 MB/s')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 36.0),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
              ),
              onPressed: () async {
                final url = _serverUrlController.text.trim();
                final path = _downloadPathController.text.trim();

                await AppSettings().setTorrServerUrl(url);
                await AppSettings().setDownloadPath(path);
                await AppSettings().setMaxConcurrentDownloads(_maxConcurrent);

                if (!mounted) return;
                NotificationService().show(context, 'Download settings saved successfully!');
              },
              child: const Text(
                'Save Settings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, fontFamily: 'Outfit'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
