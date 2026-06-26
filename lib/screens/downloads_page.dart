import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/download_service.dart';
import '../state/player_state.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

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

  void _showDeleteDialog(BuildContext context, DownloadTask task) {
    bool deleteFromDisk = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F11),
              title: const Text(
                "Delete Download?",
                style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Are you sure you want to remove '${task.title}' from your download list?",
                    style: const TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit'),
                  ),
                  const SizedBox(height: 16.0),
                  CheckboxListTile(
                    title: const Text(
                      "Also delete file from device storage",
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
                    await DownloadService().removeDownload(task.id, deleteFile: deleteFromDisk);
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

  void _playLocalFile(BuildContext context, DownloadTask task) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: DownloadService(),
        builder: (context, _) {
          final tasks = DownloadService().tasks;
          
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_for_offline_outlined, color: Colors.white24, size: 64.0),
                  SizedBox(height: 16.0),
                  Text(
                    "No downloads yet",
                    style: TextStyle(color: Colors.white38, fontSize: 16.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6.0),
                  Text(
                    "Add torrent streams to download from details page.",
                    style: TextStyle(color: Colors.white24, fontSize: 12.0, fontFamily: 'Outfit'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final double progress = task.totalBytes > 0 ? (task.downloadedBytes / task.totalBytes) : 0.0;
              final String progressPercent = (progress * 100).toStringAsFixed(1);
              
              Color statusColor = Colors.white24;
              IconData statusIcon = Icons.hourglass_empty;
              String statusText = "Queued";

              switch (task.status) {
                case DownloadStatus.queued:
                  statusColor = Colors.amber;
                  statusIcon = Icons.query_builder;
                  statusText = "Queued";
                  break;
                case DownloadStatus.downloading:
                  statusColor = Colors.blue;
                  statusIcon = Icons.downloading;
                  statusText = "Downloading";
                  break;
                case DownloadStatus.paused:
                  statusColor = Colors.white54;
                  statusIcon = Icons.pause_circle_outline;
                  statusText = "Paused";
                  break;
                case DownloadStatus.completed:
                  statusColor = Colors.green;
                  statusIcon = Icons.check_circle_outline;
                  statusText = "Completed";
                  break;
                case DownloadStatus.failed:
                  statusColor = Colors.redAccent;
                  statusIcon = Icons.error_outline;
                  statusText = "Failed";
                  break;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F11),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Title and Status Badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.0,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, color: statusColor, size: 14),
                                const SizedBox(width: 4.0),
                                Text(
                                  statusText,
                                  style: TextStyle(color: statusColor, fontSize: 10.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16.0),

                      // Progress indicator (unless completed or failed without progress info)
                      if (task.status != DownloadStatus.completed) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            color: statusColor,
                            minHeight: 4.0,
                          ),
                        ),
                        const SizedBox(height: 12.0),
                      ],

                      // Stats & Controls Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Sizes & Speed
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)} ($progressPercent%)",
                                style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontFamily: 'Outfit'),
                              ),
                              if (task.status == DownloadStatus.downloading) ...[
                                const SizedBox(height: 2.0),
                                Text(
                                  _formatSpeed(task.downloadSpeed),
                                  style: const TextStyle(color: Colors.blueAccent, fontSize: 11.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                ),
                              ],
                            ],
                          ),

                          // Action Buttons
                          Row(
                            children: [
                              // Play Offline (Completed only)
                              if (task.status == DownloadStatus.completed)
                                IconButton(
                                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.greenAccent, size: 28),
                                  tooltip: 'Play offline',
                                  onPressed: () => _playLocalFile(context, task),
                                ),

                              // Pause / Resume (Active / Paused / Queued only)
                              if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
                                IconButton(
                                  icon: const Icon(Icons.pause, color: Colors.white70),
                                  tooltip: 'Pause download',
                                  onPressed: () => DownloadService().pauseDownload(task.id),
                                )
                              else if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
                                IconButton(
                                  icon: const Icon(Icons.play_arrow, color: Colors.white70),
                                  tooltip: 'Resume download',
                                  onPressed: () => DownloadService().resumeDownload(task.id),
                                ),

                              const SizedBox(width: 4.0),

                              // Delete
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                tooltip: 'Remove task',
                                onPressed: () => _showDeleteDialog(context, task),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
