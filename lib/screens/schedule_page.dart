import 'package:flutter/material.dart';
import '../services/anilist_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';

class SchedulePage extends StatefulWidget {
  final NavigationState navigationState;

  const SchedulePage({
    super.key,
    required this.navigationState,
  });

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final AnilistService _anilistService = AnilistService();
  final GlobalKey _pageKey = GlobalKey();

  DateTime _selectedMonth = DateTime.now();
  int _selectedDay = DateTime.now().day;
  bool _myListOnly = false;
  bool _isLoading = true;
  String? _errorMessage;

  // Grouped schedules by day of month (1 to 31)
  Map<int, List<dynamic>> _schedulesByDay = {};

  // Hover states for the poster overlay card
  Map<String, dynamic>? _hoveredMedia;
  Rect? _hoverCardRect;

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _fetchSchedule();
  }

  Future<void> _fetchSchedule() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

    // Convert to Epoch seconds
    final int startTimestamp = firstDay.millisecondsSinceEpoch ~/ 1000;
    final int endTimestamp = lastDay.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

    try {
      final schedules = await _anilistService.fetchAiringSchedule(startTimestamp, endTimestamp);
      
      // Group by day in local time
      final Map<int, List<dynamic>> grouped = {};
      for (var s in schedules) {
        final int airingAt = s['airingAt'];
        final DateTime airTime = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
        if (airTime.year == _selectedMonth.year && airTime.month == _selectedMonth.month) {
          grouped.putIfAbsent(airTime.day, () => []).add(s);
        }
      }

      if (mounted) {
        setState(() {
          _schedulesByDay = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
      _selectedDay = 1;
    });
    _fetchSchedule();
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
      _selectedDay = 1;
    });
    _fetchSchedule();
  }

  void _onItemHover(BuildContext itemContext, Map<String, dynamic> media) {
    final RenderBox? box = itemContext.findRenderObject() as RenderBox?;
    if (box != null) {
      final position = box.localToGlobal(Offset.zero);
      // Convert global position to page-local position
      final RenderBox? pageBox = _pageKey.currentContext?.findRenderObject() as RenderBox?;
      if (pageBox != null) {
        final localPos = pageBox.globalToLocal(position);
        setState(() {
          _hoveredMedia = media;
          _hoverCardRect = Rect.fromLTWH(localPos.dx, localPos.dy, box.size.width, box.size.height);
        });
      }
    }
  }

  void _onItemLeave() {
    setState(() {
      _hoveredMedia = null;
      _hoverCardRect = null;
    });
  }

  String _getWeekdayAbbreviation(int weekday) {
    switch (weekday) {
      case 1: return 'Mon';
      case 2: return 'Tue';
      case 3: return 'Wed';
      case 4: return 'Thu';
      case 5: return 'Fri';
      case 6: return 'Sat';
      case 7: return 'Sun';
      default: return '';
    }
  }

  Widget _buildNavButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          width: 36.0,
          height: 36.0,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(
            icon,
            color: Colors.white70,
            size: 18.0,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F11),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildNavButton(
            icon: Icons.chevron_left,
            onTap: _prevMonth,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _months[_selectedMonth.month - 1],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 4.0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 20,
                    width: 32,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: Switch(
                        value: _myListOnly,
                        onChanged: (val) {
                          setState(() {
                            _myListOnly = val;
                          });
                        },
                        activeColor: Colors.white,
                        activeTrackColor: Colors.white30,
                        inactiveThumbColor: Colors.white38,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  const Text(
                    'My list',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.0,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
            ],
          ),
          _buildNavButton(
            icon: Icons.chevron_right,
            onTap: _nextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    const List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1.0),
        ),
      ),
      child: Row(
        children: weekdays.map((day) => Expanded(
          child: Center(
            child: Text(
              day,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildDayCell(int index) {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final int leadingEmptyCells = firstDay.weekday - 1;
    
    if (index < leadingEmptyCells) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
          ),
        ),
      );
    }

    final int dayNumber = index - leadingEmptyCells + 1;
    final List<dynamic> daySchedules = _schedulesByDay[dayNumber] ?? [];
    
    final List<dynamic> filteredSchedules = _myListOnly
        ? daySchedules.where((schedule) {
            final mediaId = schedule['mediaId'];
            return LibraryState().isSaved(mediaId, 'anime');
          }).toList()
        : daySchedules;

    final bool showMore = filteredSchedules.length > 5;
    final int displayCount = showMore ? 5 : filteredSchedules.length;
    final List<dynamic> displayedSchedules = filteredSchedules.take(displayCount).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 4.0),
            child: Text(
              '$dayNumber',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13.0,
                fontFamily: 'Outfit',
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedSchedules.length + (showMore ? 1 : 0),
              itemBuilder: (context, itemIndex) {
                if (itemIndex == displayedSchedules.length) {
                  final moreCount = filteredSchedules.length - 5;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
                    child: Text(
                      '+ $moreCount more...',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10.0,
                        fontFamily: 'Outfit',
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }

                final schedule = displayedSchedules[itemIndex];
                final mediaId = schedule['mediaId'];
                final isSaved = LibraryState().isSaved(mediaId, 'anime');

                return _ScheduleItemWidget(
                  key: ValueKey('sched_item_${schedule['id']}'),
                  schedule: schedule,
                  isSavedInLibrary: isSaved,
                  onHoverEnter: (itemContext, media) => _onItemHover(itemContext, media),
                  onHoverExit: _onItemLeave,
                  onTap: () {
                    widget.navigationState.selectAnime(mediaId);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final int leadingEmptyCells = firstDay.weekday - 1;
    final int totalCells = leadingEmptyCells + lastDay.day;
    final int totalRows = (totalCells / 7).ceil();

    return Column(
      children: [
        _buildWeekdayHeader(),
        Expanded(
          child: Column(
            children: List.generate(totalRows, (rowIndex) {
              return Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: List.generate(7, (colIndex) {
                      final int cellIndex = rowIndex * 7 + colIndex;
                      return Expanded(
                        child: _buildDayCell(cellIndex),
                      );
                    }),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildHoverCard() {
    if (_hoveredMedia == null || _hoverCardRect == null) {
      return const SizedBox.shrink();
    }

    final coverUrl = _hoveredMedia!['coverImage']?['extraLarge'] ??
        _hoveredMedia!['coverImage']?['large'] ??
        '';
    
    const double cardWidth = 180.0;
    const double cardHeight = 260.0;

    final double left = _hoverCardRect!.left + _hoverCardRect!.width / 2 - cardWidth / 2;
    final double top = _hoverCardRect!.top + _hoverCardRect!.height / 2 - cardHeight / 2;

    final double screenWidth = MediaQuery.of(context).size.width;
    double clampedLeft = left;
    if (clampedLeft < 16.0) clampedLeft = 16.0;
    if (clampedLeft + cardWidth > screenWidth - 16.0) {
      clampedLeft = screenWidth - cardWidth - 16.0;
    }

    return Positioned(
      left: clampedLeft,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: cardWidth,
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.85),
                blurRadius: 20.0,
                spreadRadius: 6.0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11.0),
            child: coverUrl.isNotEmpty
                ? Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Container(color: Colors.grey[950]),
                  )
                : Container(color: Colors.grey[950]),
          ),
        ),
      ),
    );
  }

  // Mobile views
  Widget _buildMobileDaySelector() {
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    return Container(
      height: 68.0,
      margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: lastDay,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemBuilder: (context, index) {
          final day = index + 1;
          final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
          final weekdayStr = _getWeekdayAbbreviation(date.weekday);
          final isSelected = day == _selectedDay;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedDay = day;
                });
              },
              borderRadius: BorderRadius.circular(8.0),
              child: Container(
                width: 48.0,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3A86FF) : Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(
                    color: isSelected ? Colors.white24 : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      weekdayStr,
                      style: TextStyle(
                        color: isSelected ? Colors.white70 : Colors.white38,
                        fontSize: 10.0,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      '$day',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileEpisodeList() {
    final List<dynamic> daySchedules = _schedulesByDay[_selectedDay] ?? [];
    final List<dynamic> filteredSchedules = _myListOnly
        ? daySchedules.where((schedule) {
            final mediaId = schedule['mediaId'];
            return LibraryState().isSaved(mediaId, 'anime');
          }).toList()
        : daySchedules;

    if (filteredSchedules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_today_outlined, color: Colors.white24, size: 40.0),
              const SizedBox(height: 12.0),
              const Text(
                'No episodes airing on this day.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 14.0,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: filteredSchedules.length,
      itemBuilder: (context, index) {
        final schedule = filteredSchedules[index];
        final media = schedule['media'] ?? {};
        final title = media['title']?['english'] ?? media['title']?['romaji'] ?? 'Untitled';
        final int episode = schedule['episode'] ?? 1;
        final int airingAt = schedule['airingAt'];
        final DateTime airTime = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
        final String timeStr = '${airTime.hour.toString().padLeft(2, '0')}:${airTime.minute.toString().padLeft(2, '0')}';
        final coverUrl = media['coverImage']?['large'] ?? '';
        final double? rating = media['averageScore'] != null
            ? (media['averageScore'] as num).toDouble() / 10
            : null;
        final genres = (media['genres'] as List<dynamic>?)?.take(2).join(', ') ?? '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: InkWell(
            onTap: () {
              widget.navigationState.selectAnime(media['id']);
            },
            borderRadius: BorderRadius.circular(8.0),
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F11),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6.0),
                    child: SizedBox(
                      width: 50.0,
                      height: 70.0,
                      child: coverUrl.isNotEmpty
                          ? Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(color: Colors.grey[950]),
                            )
                          : Container(color: Colors.grey[950]),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.0,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        if (genres.isNotEmpty) ...[
                          Text(
                            genres,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11.0,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          const SizedBox(height: 6.0),
                        ],
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A86FF).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: Text(
                                'Ep $episode',
                                style: const TextStyle(
                                  color: Color(0xFF3A86FF),
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10.0),
                            const Icon(Icons.access_time, color: Colors.white38, size: 12.0),
                            const SizedBox(width: 4.0),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11.0,
                                  fontFamily: 'Outfit'),
                            ),
                            if (rating != null) ...[
                              const SizedBox(width: 12.0),
                              const Icon(Icons.star, color: Colors.amber, size: 12.0),
                              const SizedBox(width: 4.0),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white24,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: LibraryState(),
        builder: (context, _) {
          return SafeArea(
            child: Stack(
              key: _pageKey,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Spacing to clear floating custom title bar on desktop
                    SizedBox(height: isMobile ? 8.0 : 58.0),

                    // Top Airing Calendar Title (Desktop/Widescreen Only)
                    if (!isMobile)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Airing Calendar',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24.0,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            SizedBox(height: 4.0),
                            Text(
                              'View upcoming episodes and their air times for the current season.',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 13.0,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Month Navigation Header
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12.0 : 20.0,
                        vertical: 8.0,
                      ),
                      child: _buildHeader(),
                    ),

                    // Main Content Section
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.0,
                              ),
                            )
                          : _errorMessage != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 40.0),
                                        const SizedBox(height: 12.0),
                                        Text(
                                          'Error loading schedule:\n$_errorMessage',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white70, fontSize: 14.0, fontFamily: 'Outfit'),
                                        ),
                                        const SizedBox(height: 16.0),
                                        ElevatedButton(
                                          onPressed: _fetchSchedule,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor: Colors.black,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                                          ),
                                          child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : isMobile
                                  ? Column(
                                      children: [
                                        _buildMobileDaySelector(),
                                        Expanded(child: _buildMobileEpisodeList()),
                                      ],
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 20.0),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
                                        ),
                                        child: _buildCalendarGrid(),
                                      ),
                                    ),
                    ),
                  ],
                ),

                // Hover Card Overlay
                if (!isMobile) _buildHoverCard(),
              ],
            ),
          );
        }
      ),
    );
  }
}

class _ScheduleItemWidget extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final bool isSavedInLibrary;
  final Function(BuildContext, Map<String, dynamic>) onHoverEnter;
  final VoidCallback onHoverExit;
  final VoidCallback onTap;

  const _ScheduleItemWidget({
    super.key,
    required this.schedule,
    required this.isSavedInLibrary,
    required this.onHoverEnter,
    required this.onHoverExit,
    required this.onTap,
  });

  @override
  State<_ScheduleItemWidget> createState() => _ScheduleItemWidgetState();
}

class _ScheduleItemWidgetState extends State<_ScheduleItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.schedule['media'] ?? {};
    final title = media['title']?['english'] ?? media['title']?['romaji'] ?? 'Untitled';
    final int episode = widget.schedule['episode'] ?? 1;
    final int airingAt = widget.schedule['airingAt'];
    final DateTime airTime = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
    final String timeStr = '${airTime.hour.toString().padLeft(2, '0')}:${airTime.minute.toString().padLeft(2, '0')}';

    return MouseRegion(
      onEnter: (event) {
        setState(() => _isHovered = true);
        widget.onHoverEnter(context, media);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        widget.onHoverExit();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 6.0),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Row(
            children: [
              if (widget.isSavedInLibrary) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3A86FF),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5.0),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _isHovered ? Colors.white : Colors.white70,
                    fontSize: 11.0,
                    fontFamily: 'Outfit',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6.0),
              Text(
                '#$episode',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10.0,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(width: 6.0),
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 10.0,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
