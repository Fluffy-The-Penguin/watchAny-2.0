import 'package:flutter/material.dart';
import '../services/update_service.dart';

/// A sleek circular progress badge that shows update download progress around an icon
/// and turns glowing green when the update is ready to install.
class UpdateCircularProgressBadge extends StatelessWidget {
  const UpdateCircularProgressBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UpdateService(),
      builder: (context, _) {
        final updateService = UpdateService();
        final isDownloading = updateService.isDownloading;
        final isReady = updateService.isUpdateReady;
        final error = updateService.error;

        if (!isDownloading && !isReady && error == null) {
          return const SizedBox.shrink();
        }

        final double progress = updateService.downloadProgress;
        final bool ready = isReady;

        final Color themeColor = ready
            ? const Color(0xFF2EC4B6)
            : (error != null ? Colors.redAccent : const Color(0xFFFF9F1C));
        final IconData iconData = ready
            ? Icons.system_update_rounded
            : (error != null ? Icons.error_outline_rounded : Icons.file_download_rounded);
        final String tooltipText = ready
            ? 'watchAny v${updateService.downloadedVersion ?? updateService.latestUpdate?.version} is ready to install! Tap now.'
            : (error != null
                ? 'Update failed: $error (Tap to retry)'
                : 'Downloading update... ${(progress * 100).toStringAsFixed(0)}%');

        return Tooltip(
          message: tooltipText,
          child: InkWell(
            onTap: () {
              if (ready) {
                updateService.launchInstaller();
              } else if (error != null) {
                updateService.startUpdate();
              } else {
                _showUpdateStatusDialog(context, updateService);
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(4.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Circular Progress Ring
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: ready ? 1.0 : (isDownloading && progress > 0 ? progress : null),
                        strokeWidth: 2.5,
                        backgroundColor: themeColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                      ),
                    ),
                    // Inner Icon
                    Icon(
                      iconData,
                      size: 13.0,
                      color: themeColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showUpdateStatusDialog(BuildContext context, UpdateService updateService) {
    showDialog(
      context: context,
      builder: (context) {
        return ListenableBuilder(
          listenable: updateService,
          builder: (context, _) {
            final isReady = updateService.isUpdateReady;
            final isDownloading = updateService.isDownloading;
            final progressPct = (updateService.downloadProgress * 100).toStringAsFixed(0);

            return AlertDialog(
              backgroundColor: const Color(0xFF16161A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Icon(
                    isReady ? Icons.system_update_rounded : Icons.downloading_rounded,
                    color: isReady ? const Color(0xFF2EC4B6) : const Color(0xFFFF9F1C),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isReady ? 'Update Ready to Install' : 'Downloading Update',
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isReady
                        ? 'watchAny v${updateService.downloadedVersion ?? updateService.latestUpdate?.version} has been downloaded and verified.'
                        : 'Downloading watchAny v${updateService.latestUpdate?.version ?? ''}... ($progressPct%)',
                    style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontSize: 13.5),
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: updateService.downloadProgress > 0 ? updateService.downloadProgress : null,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.white54, fontFamily: 'Outfit')),
                ),
                if (isReady)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2EC4B6),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      updateService.launchInstaller();
                    },
                    icon: const Icon(Icons.download_done_rounded, size: 16),
                    label: const Text('Install Now', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
