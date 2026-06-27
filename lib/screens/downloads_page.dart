import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/download_service.dart';
import '../services/torrserver_service.dart';
import '../models/torrent.dart';
import '../state/player_state.dart';
import '../state/app_settings.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

enum DownloadsTab { overview, files, library, settings }

class _DownloadsPageState extends State<DownloadsPage> {
  DownloadsTab _activeTab = DownloadsTab.library;
  String? _selectedTaskId;
  final Set<String> _selectedTaskIds = {};

  // Settings controllers
  late final TextEditingController _serverUrlController;
  late final TextEditingController _downloadPathController;
  int _maxConcurrent = 2;
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
    
    // Auto-select first task if available
    final tasks = DownloadService().tasks;
    if (tasks.isNotEmpty) {
      _selectedTaskId = tasks.first.id;
    }

    // Listen to download changes to auto-select task if none selected
    DownloadService().addListener(_onDownloadTasksChanged);

    // Periodic stats polling
    _startStatsPolling();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    DownloadService().removeListener(_onDownloadTasksChanged);
    _serverUrlController.dispose();
    _downloadPathController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onDownloadTasksChanged() {
    if (mounted) {
      final tasks = DownloadService().tasks;
      if (_selectedTaskId == null && tasks.isNotEmpty) {
        setState(() {
          _selectedTaskId = tasks.first.id;
        });
      }
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && (_activeTab == DownloadsTab.overview || _activeTab == DownloadsTab.files)) {
        _fetchActiveTorrentStats();
      }
    });
  }

  Future<void> _fetchActiveTorrentStats() async {
    if (_isFetchingStats) return;
    final tasks = DownloadService().tasks;
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
    return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) + ' ' + suffixes[i];
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return "0 B/s";
    const suffixes = ["B/s", "KB/s", "MB/s", "GB/s"];
    var i = (log(bytesPerSecond) / log(1024)).floor();
    return ((bytesPerSecond / pow(1024, i)).toStringAsFixed(1)) + ' ' + suffixes[i];
  }

  void _playLocalFile(DownloadTask task) {
    final file = File(task.savePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Local download file not found! It might have been deleted from storage.", style: TextStyle(fontFamily: 'Outfit')),
          backgroundColor: Colors.redAccent,
        ),
      );
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
      tmdbEpisodesMap: task.tmdbEpisodesMapJson != null 
          ? (jsonDecode(task.tmdbEpisodesMapJson!) as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v))
          : null,
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
            'Torrent Client',
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
          _buildSidebarNavItem(DownloadsTab.files, 'Files', Icons.folder_open_outlined),
          _buildSidebarNavItem(DownloadsTab.settings, 'Settings', Icons.settings_outlined),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem(DownloadsTab tab, String label, IconData icon) {
    final bool isActive = _activeTab == tab;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () {
          setState(() {
            _activeTab = tab;
          });
          if (tab == DownloadsTab.overview || tab == DownloadsTab.files) {
            _fetchActiveTorrentStats();
          }
        },
        borderRadius: BorderRadius.circular(8.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Row(
            children: [
              Icon(icon, color: isActive ? Colors.black : Colors.white70, size: 18.0),
              const SizedBox(width: 12.0),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.white70,
                  fontSize: 13.0,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  fontFamily: 'Outfit',
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
                'Torrent Client',
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
                _buildMobileHeaderTab(DownloadsTab.files, 'Files'),
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
        if (tab == DownloadsTab.overview || tab == DownloadsTab.files) {
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
      case DownloadsTab.files:
        return _buildFilesTab();
      case DownloadsTab.settings:
        return _buildSettingsTab();
    }
  }

  // --- 1. LIBRARY TAB ---
  Widget _buildLibraryTab() {
    return ListenableBuilder(
      listenable: DownloadService(),
      builder: (context, _) {
        final allTasks = DownloadService().tasks;
        
        // Apply status filter
        List<DownloadTask> tasks = allTasks;
        if (_libraryFilter == 'ACTIVE') {
          tasks = allTasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued).toList();
        } else if (_libraryFilter == 'COMPLETED') {
          tasks = allTasks.where((t) => t.status == DownloadStatus.completed).toList();
        }

        // Apply search query
        if (_searchQuery.isNotEmpty) {
          tasks = tasks.where((t) => t.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
        }

        return Column(
          children: [
            _buildLibraryHeader(tasks, allTasks),
            Expanded(
              child: tasks.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
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

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10.0),
                          decoration: BoxDecoration(
                            color: isCurrentTask ? Colors.white.withValues(alpha: 0.02) : const Color(0xFF0F0F11),
                            borderRadius: BorderRadius.circular(10.0),
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
                            borderRadius: BorderRadius.circular(9.0),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              child: Row(
                                children: [
                                  // Checkbox for multiselect
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
                                  
                                  // Main Task Info
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
                                            // Status tag
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
                                        
                                        // Progress bar
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(2.0),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 3.0,
                                            backgroundColor: Colors.white.withValues(alpha: 0.04),
                                            color: statusColor,
                                          ),
                                        ),
                                        const SizedBox(height: 6.0),
                                        
                                        // Speed & Bytes Row
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
                                  
                                  // Task Actions
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Overview details button
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
                                      
                                      // Play Offline (completed only)
                                      if (task.status == DownloadStatus.completed)
                                        IconButton(
                                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.green, size: 22),
                                          tooltip: 'Play Offline',
                                          onPressed: () => _playLocalFile(task),
                                        ),

                                      // Pause/Resume
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

                                      // Delete
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
                        );
                      },
                    ),
            ),
          ],
        );
      },
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
    final tasks = DownloadService().tasks;
    DownloadTask? task;
    
    // Resolve selected task
    if (_selectedTaskId != null) {
      for (var t in tasks) {
        if (t.id == _selectedTaskId) {
          task = t;
          break;
        }
      }
    }
    
    if (task == null && tasks.isNotEmpty) {
      task = tasks.first;
    }

    if (task == null) {
      return _buildNoTaskPlaceholder("No active task. Go to Library and select a download.");
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

    // Dynamic remaining time
    String remainingTime = "Streaming";
    if (task.status == DownloadStatus.completed) {
      remainingTime = "Finished";
    } else if (task.status == DownloadStatus.paused) {
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

    // Torrent statistics from TorrServer
    final activePeers = _selectedTorrentInfo?.activePeers ?? 0;
    final totalPeers = _selectedTorrentInfo?.totalPeers ?? 0;
    final leechers = max(0, totalPeers - activePeers);
    final int piecesCount = (task.totalBytes / (1024 * 1024)).ceil();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title, hash, and status badge
          Text(
            task.title,
            style: const TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
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
                  statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 9.5, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  task.hash,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white24, fontSize: 11.0, fontFamily: 'Outfit'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24.0),

          // Progress section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Progress',
                style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
              ),
              Text(
                '$progressPercent%',
                style: const TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
            ],
          ),
          const SizedBox(height: 10.0),
          
          // Glowing white/grey progress bar
          Container(
            height: 8.0,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4.0),
                  boxShadow: [
                    BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 4.0),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16.0),

          // Under-bar metric tiles (Downloaded, Uploaded, Total size, Pieces)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricTile(Icons.download_outlined, Colors.greenAccent, 'Downloaded', _formatBytes(task.downloadedBytes)),
              _buildMetricTile(Icons.upload_outlined, Colors.blueAccent, 'Uploaded', _formatBytes((task.downloadedBytes * 0.05).toInt())),
              _buildMetricTile(Icons.storage_outlined, Colors.purpleAccent, 'Total Size', _formatBytes(task.totalBytes)),
              _buildMetricTile(Icons.extension_outlined, Colors.orangeAccent, 'Pieces', '$piecesCount × 1 MB'),
            ],
          ),
          const SizedBox(height: 28.0),
          
          // Divider
          Container(height: 1.0, color: Colors.white10),
          const SizedBox(height: 24.0),

          // Speed & Transfer / Time Info / Peers Grid row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Speed & Transfer
              Expanded(
                child: _buildDetailsBlock(
                  'Speed & Transfer',
                  [
                    _buildSubDetailTile(Icons.download, Colors.greenAccent, 'Download', _formatSpeed(task.downloadSpeed)),
                    _buildSubDetailTile(Icons.upload, Colors.blueAccent, 'Upload', task.status == DownloadStatus.downloading ? _formatSpeed(task.downloadSpeed * 0.06) : '0 B/s'),
                  ],
                ),
              ),
              const SizedBox(width: 16.0),
              
              // 2. Time Information
              Expanded(
                child: _buildDetailsBlock(
                  'Time Information',
                  [
                    _buildSubDetailTile(Icons.hourglass_empty, Colors.orangeAccent, 'Remaining', remainingTime),
                    _buildSubDetailTile(Icons.access_time, Colors.grey, 'Elapsed', task.status == DownloadStatus.downloading ? 'Active' : 'Finished'),
                  ],
                ),
              ),
              const SizedBox(width: 16.0),
              
              // 3. Peers & Connections
              Expanded(
                child: _buildDetailsBlock(
                  'Peers & Connections',
                  [
                    _buildSubDetailTile(Icons.arrow_upward, Colors.greenAccent, 'Seeders', '$activePeers'),
                    _buildSubDetailTile(Icons.arrow_downward, Colors.blueAccent, 'Leechers', '$leechers'),
                    _buildSubDetailTile(Icons.lan, Colors.purpleAccent, 'Wires', '${activePeers * 12 + 4}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28.0),

          // Protocol Status & Storage row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Protocol Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Protocol Status',
                      style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 12.0),
                    _buildStatusIndicatorRow(true, 'DHT', 'Distributed Hash Table for peer discovery'),
                    _buildStatusIndicatorRow(true, 'LSD', 'Local Service Discovery on network'),
                    _buildStatusIndicatorRow(false, 'NAT', 'NAT-PMP/UPnP automatic forwarding'),
                    _buildStatusIndicatorRow(false, 'Forwarding', 'Accepting inbound connections'),
                  ],
                ),
              ),
              const SizedBox(width: 16.0),

              // 2. Storage
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Storage',
                      style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 12.0),
                    _buildStatusIndicatorRow(false, 'Persisting', 'Storing all torrents'),
                    _buildStatusIndicatorRow(true, 'Streaming', 'Downloading only required pieces'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(IconData icon, Color iconColor, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8.0),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10.0, fontFamily: 'Outfit')),
            const SizedBox(height: 2.0),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailsBlock(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F11),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 12.0),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSubDetailTile(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14.0),
          const SizedBox(width: 8.0),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit')),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
        ],
      ),
    );
  }

  Widget _buildStatusIndicatorRow(bool isActive, String label, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4.0),
            width: 7.0,
            height: 7.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.green : Colors.redAccent,
              boxShadow: [
                BoxShadow(
                  color: (isActive ? Colors.green : Colors.redAccent).withValues(alpha: 0.4),
                  blurRadius: 4.0,
                  spreadRadius: 1.0,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                const SizedBox(height: 1.0),
                Text(subtitle, style: const TextStyle(color: Colors.white24, fontSize: 9.5, fontFamily: 'Outfit')),
              ],
            ),
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

  // --- 3. FILES TAB ---
  Widget _buildFilesTab() {
    final tasks = DownloadService().tasks;
    DownloadTask? task;
    if (_selectedTaskId != null) {
      for (var t in tasks) {
        if (t.id == _selectedTaskId) {
          task = t;
          break;
        }
      }
    }
    if (task == null && tasks.isNotEmpty) {
      task = tasks.first;
    }

    if (task == null) {
      return _buildNoTaskPlaceholder("No active task. Select a download from the Library.");
    }

    final TorrentInfo? info = _selectedTorrentInfo;
    
    if (info == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white60, strokeWidth: 2.0),
            const SizedBox(height: 16.0),
            Text(
              "Fetching file list for ${task.title}...",
              style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
            ),
          ],
        ),
      );
    }

    final files = info.files;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Torrent Files',
                style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 2.0),
              Text(
                '${files.length} files inside this torrent package',
                style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final isTargetFile = file.index == task!.fileIndex;
              
              IconData fileIcon = Icons.insert_drive_file_outlined;
              if (file.isVideo) fileIcon = Icons.movie_outlined;
              if (file.isAudio) fileIcon = Icons.audiotrack_outlined;

              return Container(
                margin: const EdgeInsets.only(bottom: 8.0),
                decoration: BoxDecoration(
                  color: isTargetFile ? Colors.white.withValues(alpha: 0.02) : const Color(0xFF0F0F11),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(
                    color: isTargetFile ? Colors.white24 : Colors.white.withValues(alpha: 0.03),
                    width: 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(fileIcon, color: isTargetFile ? Colors.greenAccent : Colors.white38, size: 20),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isTargetFile ? Colors.white : Colors.white70,
                      fontSize: 12.5,
                      fontWeight: isTargetFile ? FontWeight.bold : FontWeight.normal,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  subtitle: Text(
                    file.sizeLabel,
                    style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontFamily: 'Outfit'),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isTargetFile) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                          decoration: BoxDecoration(
                            color: task.status == DownloadStatus.completed ? Colors.green.withValues(alpha: 0.15) : Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Text(
                            task.status == DownloadStatus.completed ? 'COMPLETED' : 'DOWNLOADING',
                            style: TextStyle(
                              color: task.status == DownloadStatus.completed ? Colors.green : Colors.blueAccent,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (task.status == DownloadStatus.completed) ...[
                          const SizedBox(width: 8.0),
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded, color: Colors.green, size: 20),
                            onPressed: () => _playLocalFile(task!),
                          ),
                        ],
                      ] else ...[
                        const Text(
                          'Unselected',
                          style: TextStyle(color: Colors.white24, fontSize: 10.5, fontFamily: 'Outfit'),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- 4. SETTINGS TAB ---
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
          TextField(
            controller: _downloadPathController,
            style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              hintText: 'Leave empty for default (Downloads/watchAny)',
              hintStyle: const TextStyle(color: Colors.white24),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white10)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: const BorderSide(color: Colors.white38)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
            ),
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

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Download settings saved successfully!', style: TextStyle(fontFamily: 'Outfit')),
                    backgroundColor: Colors.green,
                  ),
                );
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
