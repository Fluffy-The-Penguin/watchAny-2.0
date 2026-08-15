import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HoverPreviewWrapper extends StatefulWidget {
  final Widget child;
  final dynamic item;
  final bool isMovie;
  final VoidCallback onTap;

  const HoverPreviewWrapper({
    super.key,
    required this.child,
    required this.item,
    this.isMovie = false,
    required this.onTap,
  });

  @override
  State<HoverPreviewWrapper> createState() => _HoverPreviewWrapperState();
}

class _HoverPreviewWrapperState extends State<HoverPreviewWrapper> {
  OverlayEntry? _overlayEntry;
  Timer? _hoverTimer;

  @override
  void dispose() {
    _removeOverlay();
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _showOverlay() {
    if (!mounted || _overlayEntry != null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // Calculate popover position: right of card by default, left if constrained
    double left = offset.dx + size.width + 12.0;
    if (left + 320.0 > screenSize.width - 20.0) {
      left = offset.dx - 320.0 - 12.0;
    }
    if (left < 10.0) left = 10.0;

    double top = offset.dy - 10.0;
    if (top + 340.0 > screenSize.height - 20.0) {
      top = screenSize.height - 350.0;
    }
    if (top < 10.0) top = 10.0;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: 320.0,
            child: Material(
              color: Colors.transparent,
              child: MouseRegion(
                onEnter: (_) => _hoverTimer?.cancel(),
                onExit: (_) => _removeOverlay(),
                child: _PreviewCard(
                  item: widget.item,
                  isMovie: widget.isMovie,
                  onTap: () {
                    _removeOverlay();
                    widget.onTap();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _hoverTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 750;

    if (isMobile) {
      return GestureDetector(
        onTap: widget.onTap,
        child: widget.child,
      );
    }

    return MouseRegion(
      onEnter: (_) {
        _hoverTimer?.cancel();
        _hoverTimer = Timer(const Duration(milliseconds: 60), _showOverlay);
      },
      onExit: (_) {
        _hoverTimer?.cancel();
        _hoverTimer = Timer(const Duration(milliseconds: 100), _removeOverlay);
      },
      child: GestureDetector(
        onTap: () {
          _removeOverlay();
          widget.onTap();
        },
        child: widget.child,
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final dynamic item;
  final bool isMovie;
  final VoidCallback onTap;

  const _PreviewCard({
    required this.item,
    required this.isMovie,
    required this.onTap,
  });

  String _cleanHtml(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&quot;', '"').replaceAll('&#039;', "'").replaceAll('&amp;', '&');
  }

  @override
  Widget build(BuildContext context) {
    final title = isMovie
        ? (item['name'] ?? item['title'] ?? 'Untitled')
        : ((item['title'] is Map)
            ? (item['title']['english'] ?? item['title']['romaji'] ?? 'Untitled')
            : (item['title']?.toString() ?? 'Untitled'));

    final coverUrl = isMovie
        ? (item['poster'] ?? item['background'] ?? '')
        : ((item['coverImage'] is Map)
            ? (item['coverImage']['large'] ?? item['coverImage']['extraLarge'] ?? '')
            : (item['coverImage']?.toString() ?? ''));

    final description = _cleanHtml(item['description']?.toString());
    final format = isMovie ? (item['type']?.toString().toUpperCase() ?? 'MOVIE') : (item['format']?.toString() ?? 'TV');
    final status = isMovie ? null : (item['status']?.toString() ?? '');
    
    double? rating;
    if (isMovie) {
      if (item['imdbRating'] != null) {
        rating = double.tryParse(item['imdbRating'].toString());
      }
    } else {
      if (item['averageScore'] != null) {
        rating = double.tryParse(item['averageScore'].toString());
        if (rating != null && rating > 10.0) rating = rating / 10.0;
      }
    }

    List<String> genres = [];
    if (item['genres'] is List) {
      genres = (item['genres'] as List).map((g) => g.toString()).take(4).toList();
    } else if (item['genre'] is String) {
      genres = (item['genre'] as String).split(',').map((g) => g.trim()).take(4).toList();
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F14),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 28,
              spreadRadius: 6,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Crimson Glow Accent Line
              Container(
                height: 3.0,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFB20710)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: SizedBox(
                            width: 58.0,
                            height: 84.0,
                            child: coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: coverUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 150,
                                    placeholder: (context, url) => Container(color: const Color(0xFF181820)),
                                    errorWidget: (context, url, err) => Container(color: const Color(0xFF181820)),
                                  )
                                : Container(color: const Color(0xFF181820)),
                          ),
                        ),
                        const SizedBox(width: 14.0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.0,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Outfit',
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              Wrap(
                                spacing: 6.0,
                                runSpacing: 4.0,
                                children: [
                                  if (rating != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(5.0),
                                        border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star_rounded, color: Colors.amber, size: 12.0),
                                          const SizedBox(width: 3.0),
                                          Text(
                                            rating.toStringAsFixed(1),
                                            style: const TextStyle(
                                              color: Colors.amber,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Outfit',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(5.0),
                                      border: Border.all(color: Colors.white12, width: 0.8),
                                    ),
                                    child: Text(
                                      format,
                                      style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                    ),
                                  ),
                                  if (status != null && status.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(5.0),
                                        border: Border.all(color: Colors.white12, width: 0.8),
                                      ),
                                      child: Text(
                                        status,
                                        style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontFamily: 'Outfit'),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (genres.isNotEmpty) ...[
                      const SizedBox(height: 12.0),
                      Wrap(
                        spacing: 6.0,
                        runSpacing: 4.0,
                        children: genres
                            .map(
                              (g) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(color: Colors.white12, width: 0.8),
                                ),
                                child: Text(
                                  g,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 12.0),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12.0,
                          height: 1.40,
                          fontStyle: FontStyle.italic,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ],
                    const SizedBox(height: 14.0),
                    ElevatedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.play_arrow_rounded, size: 16.0),
                      label: const Text('View Details'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(38.0),
                        elevation: 4,
                        shadowColor: const Color(0xFFE50914).withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        textStyle: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
