import 'dart:math';
import 'package:flutter/material.dart';

class MovieStreamSelectorPanel extends StatefulWidget {
  final List<dynamic> streams;
  final String title;
  final void Function(dynamic stream) onStreamSelected;
  final bool isFromPlayer;

  const MovieStreamSelectorPanel({
    super.key,
    required this.streams,
    required this.title,
    required this.onStreamSelected,
    this.isFromPlayer = false,
  });

  @override
  State<MovieStreamSelectorPanel> createState() => _MovieStreamSelectorPanelState();
}

class _MovieStreamSelectorPanelState extends State<MovieStreamSelectorPanel> {
  final TextEditingController _searchController = TextEditingController();
  final List<String> _exclusions = [];
  final TextEditingController _excludeController = TextEditingController();

  String? _selectedResolution; // null means 'All'
  String _selectedTypeFilter = 'all'; // 'all', 'torrent', 'direct'
  int? _selectedMaxSize; // null means 'All'
  String _selectedSortOrder = 'default'; // 'default', 'seeders', 'size_desc', 'size_asc'

  @override
  void dispose() {
    _searchController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  // ── Helper parsing methods ──────────────────────────────────────────────────

  bool _hasTag(String title, String tag) {
    final t = title.toLowerCase();
    if (tag == '4K') {
      return t.contains('2160') || t.contains('4k') || t.contains('uhd');
    } else if (tag == '1080') {
      return t.contains('1080');
    } else if (tag == '720') {
      return t.contains('720');
    } else if (tag == '480') {
      return t.contains('480') || t.contains('360') || t.contains('sd');
    }
    return false;
  }

  int _extractSeeders(dynamic s) {
    if (s['seeders'] != null) return int.tryParse(s['seeders'].toString()) ?? 0;
    final t = s['title']?.toString() ?? s['description']?.toString() ?? '';
    final m = RegExp(r'(?:👤|seeders?:?\s*)(\d+)', caseSensitive: false).firstMatch(t);
    return m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
  }

  int _extractPeers(dynamic s) {
    if (s['peers'] != null) return int.tryParse(s['peers'].toString()) ?? 0;
    if (s['leechers'] != null) return int.tryParse(s['leechers'].toString()) ?? 0;
    final t = s['title']?.toString() ?? s['description']?.toString() ?? '';
    final m1 = RegExp(r'(?:👥|peers?:?\s*|leechers?:?\s*)(\d+)', caseSensitive: false).firstMatch(t);
    if (m1 != null) {
      return int.tryParse(m1.group(1)!) ?? 0;
    }
    final m2 = RegExp(r'(?:👤|seeders?:?\s*)(\d+)\s*/\s*(\d+)', caseSensitive: false).firstMatch(t);
    if (m2 != null) {
      return int.tryParse(m2.group(2)!) ?? 0;
    }
    return 0;
  }

  int _extractSize(dynamic s) {
    if (s['size'] != null) {
      return int.tryParse(s['size'].toString()) ?? 0;
    }
    final t = s['title']?.toString() ?? '';
    final m = RegExp(r'\b(\d+(?:\.\d+)?)\s*(GB|MB)\b', caseSensitive: false).firstMatch(t);
    if (m != null) {
      final val = double.tryParse(m.group(1)!) ?? 0.0;
      final unit = m.group(2)!.toUpperCase();
      if (unit == 'GB') {
        return (val * 1024 * 1024 * 1024).toInt();
      } else if (unit == 'MB') {
        return (val * 1024 * 1024).toInt();
      }
    }
    return 0;
  }

  String _formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return "";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) + ' ' + suffixes[i];
  }

  // ── Filter logic ────────────────────────────────────────────────────────────

  List<dynamic> get _processedStreams {
    List<dynamic> list = List.from(widget.streams);

    // 1. Text Search filter (matching stream name or description)
    final search = _searchController.text.trim().toLowerCase();
    if (search.isNotEmpty) {
      list = list.where((s) {
        final name = (s['name']?.toString() ?? '').toLowerCase();
        final title = (s['title']?.toString() ?? '').toLowerCase();
        return name.contains(search) || title.contains(search);
      }).toList();
    }

    // 2. Exclusions filter
    if (_exclusions.isNotEmpty) {
      list = list.where((s) {
        final title = (s['title']?.toString() ?? '').toLowerCase();
        final name = (s['name']?.toString() ?? '').toLowerCase();
        return !_exclusions.any((ex) => title.contains(ex) || name.contains(ex));
      }).toList();
    }

    // 3. Resolution/Quality filter
    if (_selectedResolution != null) {
      list = list.where((s) {
        final desc = s['title']?.toString() ?? s['description']?.toString() ?? '';
        return _hasTag(desc, _selectedResolution!);
      }).toList();
    }

    // 4. Type filter (Torrent vs Direct URL)
    if (_selectedTypeFilter == 'torrent') {
      list = list.where((s) => s['infoHash'] != null).toList();
    } else if (_selectedTypeFilter == 'direct') {
      list = list.where((s) => s['url'] != null).toList();
    }

    // 5. Size Filter
    if (_selectedMaxSize != null) {
      list = list.where((s) {
        final size = _extractSize(s);
        return size == 0 || size <= _selectedMaxSize!;
      }).toList();
    }

    // 6. Sorting
    if (_selectedSortOrder == 'seeders') {
      list.sort((a, b) => _extractSeeders(b).compareTo(_extractSeeders(a)));
    } else if (_selectedSortOrder == 'size_desc') {
      list.sort((a, b) => _extractSize(b).compareTo(_extractSize(a)));
    } else if (_selectedSortOrder == 'size_asc') {
      list.sort((a, b) => _extractSize(a).compareTo(_extractSize(b)));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
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
                      'Available Streams • ${widget.title}',
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
                      '${_processedStreams.length} of ${widget.streams.length} options matching',
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

        // Filter Controls
        _buildFilterRow(isMobile),

        // Stream List
        Expanded(
          child: _processedStreams.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.video_collection_outlined, color: Colors.white24, size: 40.0),
                      SizedBox(height: 12.0),
                      Text(
                        'No streams match active filters.',
                        style: TextStyle(color: Colors.white38, fontSize: 14.0, fontFamily: 'Outfit'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _processedStreams.length,
                  itemBuilder: (context, index) {
                    final stream = _processedStreams[index];
                    return _buildStreamCard(stream);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterRow(bool isMobile) {
    final qualitySelector = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Quality',
          style: TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
        ),
        const SizedBox(width: 8.0),
        Container(
          height: 36.0,
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedResolution,
              isDense: true,
              icon: const Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: Icon(Icons.arrow_drop_down, color: Colors.white38, size: 18),
              ),
              dropdownColor: const Color(0xFF0F0F11),
              style: const TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All')),
                DropdownMenuItem(value: '4K', child: Text('4K / UHD')),
                DropdownMenuItem(value: '1080', child: Text('1080p')),
                DropdownMenuItem(value: '720', child: Text('720p')),
                DropdownMenuItem(value: '480', child: Text('SD / 480p')),
              ],
              onChanged: (val) {
                setState(() => _selectedResolution = val);
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
          'Type',
          style: TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
        ),
        const SizedBox(width: 8.0),
        Container(
          height: 36.0,
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTypeFilter,
              isDense: true,
              icon: const Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: Icon(Icons.arrow_drop_down, color: Colors.white38, size: 18),
              ),
              dropdownColor: const Color(0xFF0F0F11),
              style: const TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'torrent', child: Text('Torrents')),
                DropdownMenuItem(value: 'direct', child: Text('Direct URLs')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedTypeFilter = val);
              },
            ),
          ),
        ),
      ],
    );

    final sizeSelector = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Size',
          style: TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
        ),
        const SizedBox(width: 8.0),
        Container(
          height: 36.0,
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: _selectedMaxSize,
              isDense: true,
              icon: const Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: Icon(Icons.arrow_drop_down, color: Colors.white38, size: 18),
              ),
              dropdownColor: const Color(0xFF0F0F11),
              style: const TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All Sizes')),
                DropdownMenuItem(value: 524288000, child: Text('< 500 MB')),
                DropdownMenuItem(value: 1073741824, child: Text('< 1 GB')),
                DropdownMenuItem(value: 2147483648, child: Text('< 2 GB')),
                DropdownMenuItem(value: 5368709120, child: Text('< 5 GB')),
                DropdownMenuItem(value: 10737418240, child: Text('< 10 GB')),
                DropdownMenuItem(value: 16106127360, child: Text('< 15 GB')),
                DropdownMenuItem(value: 21474836480, child: Text('< 20 GB')),
                DropdownMenuItem(value: 32212254720, child: Text('< 30 GB')),
                DropdownMenuItem(value: 53687091200, child: Text('< 50 GB')),
                DropdownMenuItem(value: 107374182400, child: Text('< 100 GB')),
              ],
              onChanged: (val) {
                setState(() => _selectedMaxSize = val);
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
          'Sort',
          style: TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
        ),
        const SizedBox(width: 8.0),
        Container(
          height: 36.0,
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedSortOrder,
              isDense: true,
              icon: const Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: Icon(Icons.arrow_drop_down, color: Colors.white38, size: 18),
              ),
              dropdownColor: const Color(0xFF0F0F11),
              style: const TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
              items: const [
                DropdownMenuItem(value: 'default', child: Text('Default')),
                DropdownMenuItem(value: 'seeders', child: Text('Seeders')),
                DropdownMenuItem(value: 'size_desc', child: Text('Size (Large)')),
                DropdownMenuItem(value: 'size_asc', child: Text('Size (Small)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedSortOrder = val);
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
        sizeSelector,
        sortSelector,
      ],
    );

    final searchField = SizedBox(
      height: 36.0,
      width: isMobile ? double.infinity : 180.0,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 12.0),
        decoration: InputDecoration(
          hintText: 'Search title...',
          hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 16),
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
        onChanged: (val) => setState(() {}),
      ),
    );

    final exclusionsInput = SizedBox(
      height: 36.0,
      child: TextField(
        controller: _excludeController,
        style: const TextStyle(color: Colors.white, fontSize: 12.0),
        decoration: InputDecoration(
          hintText: 'Add exclusions (comma separated)...',
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
              _exclusions.addAll(parts.map((p) => p.toLowerCase()));
            });
            _excludeController.clear();
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
            },
            tooltip: 'Clear exclusions',
          ),
        ],
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
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    selectorsWrap,
                    const SizedBox(height: 8.0),
                    Row(
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 8.0),
                        exclusionsActions,
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: selectorsWrap),
                    const SizedBox(width: 16.0),
                    searchField,
                    const SizedBox(width: 8.0),
                    exclusionsActions,
                  ],
                ),
          const SizedBox(height: 8.0),
          exclusionsInput,
        ],
      ),
    );
  }

  Widget _buildStreamCard(dynamic stream) {
    final String addonName =
        stream['addonName']?.toString() ?? stream['name']?.toString() ?? 'Addon';
    final String rawTitle =
        stream['title']?.toString() ?? stream['description']?.toString() ?? '';
    final String firstLine = _firstLine(rawTitle);
    final String displayTitle = firstLine.isNotEmpty ? firstLine : addonName;

    final tags = _extractTags(rawTitle);
    final seeders = _extractSeeders(stream);
    final peers = _extractPeers(stream);
    final sizeBytes = _extractSize(stream);
    final size = _formatBytes(sizeBytes);
    final bool isTorrent = stream['infoHash'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isTorrent
                ? Colors.green.withValues(alpha: 0.12)
                : Colors.blue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isTorrent ? Icons.download_rounded : Icons.play_circle_outline,
            color: isTorrent ? Colors.green : Colors.blue,
            size: 18,
          ),
        ),
        title: Text(
          displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Addon name badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                  addonName.split('\n').first.toUpperCase(),
                  style: const TextStyle(color: Colors.white60, fontSize: 9.0, fontWeight: FontWeight.bold),
                ),
              ),
              // Torrent badge
              if (isTorrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: const Text(
                    'TORRENT',
                    style: TextStyle(color: Colors.green, fontSize: 9.0, fontWeight: FontWeight.bold),
                  ),
                ),
              // Size
              if (size.isNotEmpty)
                Text(
                  size,
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
              // Seeders
              if (isTorrent && seeders >= 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_upward, color: Colors.green, size: 14.0),
                    const SizedBox(width: 2.0),
                    Text(
                      '$seeders',
                      style: const TextStyle(color: Colors.green, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              // Leechers (Peers)
              if (isTorrent && peers >= 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_downward, color: Colors.redAccent, size: 14.0),
                    const SizedBox(width: 2.0),
                    Text(
                      '$peers',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                    ),
                  ],
                ),
              // Quality tags
              ...tags.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: t == '4K'
                          ? Colors.amber.withValues(alpha: 0.15)
                          : t == '1080p'
                              ? Colors.blue.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4.0),
                      border: Border.all(
                        color: t == '4K'
                            ? Colors.amber.withValues(alpha: 0.3)
                            : t == '1080p'
                                ? Colors.blue.withValues(alpha: 0.3)
                                : Colors.white12,
                      ),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        color: t == '4K'
                            ? Colors.amber
                            : t == '1080p'
                                ? Colors.blue[300]!
                                : Colors.white70,
                        fontSize: 9.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )),
            ],
          ),
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
          ),
          onPressed: () => widget.onStreamSelected(stream),
          child: const Text('Play',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0)),
        ),
      ),
    );
  }



  String _firstLine(String s) {
    final i = s.indexOf('\n');
    return (i > 0 ? s.substring(0, i) : s).trim();
  }

  List<String> _extractTags(String title) {
    final t = title.toLowerCase();
    final tags = <String>[];
    if (t.contains('2160') || t.contains('4k') || t.contains('uhd')) {
      tags.add('4K');
    } else if (t.contains('1080')) {
      tags.add('1080p');
    } else if (t.contains('720')) {
      tags.add('720p');
    }
    if (t.contains('hdr')) tags.add('HDR');
    if (t.contains('dv') || t.contains('dolby vision')) tags.add('DV');
    if (t.contains('dual') || t.contains('multi')) tags.add('Dual Audio');
    return tags;
  }
}
