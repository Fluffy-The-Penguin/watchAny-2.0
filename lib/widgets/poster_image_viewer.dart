import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Shows a full-screen interactive poster image viewer with pinch-to-zoom,
/// double-tap zoom, and glassmorphic UI.
void showPosterImageViewerDialog(
  BuildContext context, {
  required String imageUrl,
  String title = '',
}) {
  if (imageUrl.isEmpty) return;

  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => _PosterImageViewerDialog(
      imageUrl: imageUrl,
      title: title,
    ),
  );
}

class _PosterImageViewerDialog extends StatefulWidget {
  final String imageUrl;
  final String title;

  const _PosterImageViewerDialog({
    required this.imageUrl,
    required this.title,
  });

  @override
  State<_PosterImageViewerDialog> createState() => _PosterImageViewerDialogState();
}

class _PosterImageViewerDialogState extends State<_PosterImageViewerDialog> {
  final TransformationController _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _isZoomed = false;

  void _handleDoubleTap() {
    if (_isZoomed) {
      _transformationController.value = Matrix4.identity();
      setState(() => _isZoomed = false);
    } else {
      final position = _doubleTapDetails?.localPosition ?? const Offset(200, 300);
      final matrix = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
      _transformationController.value = matrix;
      setState(() => _isZoomed = true);
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    setState(() => _isZoomed = false);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Frosted Backdrop Filter
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              color: Colors.black.withValues(alpha: 0.85),
            ),
          ),

          // Interactive Zoomable Image
          GestureDetector(
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 5.0,
              clipBehavior: Clip.none,
              onInteractionEnd: (details) {
                final scale = _transformationController.value.getMaxScaleOnAxis();
                setState(() => _isZoomed = scale > 1.1);
              },
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    ),
                    errorWidget: (context, url, error) => const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image, size: 64, color: Colors.white24),
                        SizedBox(height: 12),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white54, fontFamily: 'Outfit'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top Header Bar (Title & Close Button)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12.0,
            left: 16.0,
            right: 16.0,
            child: Row(
              children: [
                if (widget.title.isNotEmpty)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20.0),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 12.0),
                Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: const CircleBorder(side: BorderSide(color: Colors.white12)),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Quick Controls Bar (Zoom reset hint)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20.0,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24.0),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.zoom_in, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Pinch or double-tap to zoom',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit'),
                        ),
                        if (_isZoomed) ...[
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: _resetZoom,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Reset Zoom',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
