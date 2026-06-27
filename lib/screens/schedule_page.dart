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

  Widget _buildHeader(bool isMobile) {
    if (isMobile) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _buildNavButton(icon: Icons.chevron_left, onTap: _prevMonth),
              const SizedBox(width: 12.0),
              Text(
                _months[_selectedMonth.month - 1],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(width: 12.0),
              _buildNavButton(icon: Icons.chevron_right, onTap: _nextMonth),
            ],
          ),
          _buildMyListToggle(),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Column(
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
        Row(
          children: [
            _buildMyListToggle(),
            const SizedBox(width: 20.0),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F11),
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  _buildNavButton(icon: Icons.chevron_left, onTap: _prevMonth),
                  Container(
                    constraints: const BoxConstraints(minWidth: 100.0),
                    alignment: Alignment.center,
                    child: Text(
                      '${_months[_selectedMonth.month - 1]} ${_selectedMonth.year}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ),
                  _buildNavButton(icon: Icons.chevron_right, onTap: _nextMonth),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMyListToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F11),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(
          color: _myListOnly 
              ? const Color(0xFF3A86FF).withValues(alpha: 0.3) 
              : Colors.white.withValues(alpha: 0.05)
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _myListOnly = !_myListOnly;
          });
        },
        borderRadius: BorderRadius.circular(10.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _myListOnly ? Icons.bookmark : Icons.bookmark_border,
                color: _myListOnly ? const Color(0xFF3A86FF) : Colors.white54,
                size: 14.0,
              ),
              const SizedBox(width: 6.0),
              Text(
                'My List Only',
                style: TextStyle(
                  color: _myListOnly ? Colors.white : Colors.white54,
                  fontSize: 12.0,
                  fontWeight: _myListOnly ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
        ),
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

    final bool showMore = filteredSchedules.length > 3;
    final int displayCount = showMore ? 3 : filteredSchedules.length;
    final List<dynamic> displayedSchedules = filteredSchedules.take(displayCount).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDayDetailsDialog(dayNumber),
        child: Container(
          decoration: BoxDecoration(
            color: _selectedDay == dayNumber && _selectedMonth.month == DateTime.now().month && _selectedMonth.year == DateTime.now().year
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.transparent,
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
                  style: TextStyle(
                    color: (dayNumber == DateTime.now().day && _selectedMonth.month == DateTime.now().month && _selectedMonth.year == DateTime.now().year)
                        ? const Color(0xFF3A86FF)
                        : Colors.white,
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
                      final moreCount = filteredSchedules.length - 3;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                        child: Text(
                          '+ $moreCount more...',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9.0,
                            fontFamily: 'Outfit',
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      );
                    }

                    final schedule = displayedSchedules[itemIndex];
                    final media = schedule['media'] ?? {};
                    final title = media['title']?['english'] ?? media['title']?['romaji'] ?? 'Untitled';
                    final int airingAt = schedule['airingAt'];
                    final DateTime airTime = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
                    final String timeStr = '${airTime.hour.toString().padLeft(2, '0')}:${airTime.minute.toString().padLeft(2, '0')}';
                    final mediaId = schedule['mediaId'];
                    final isSaved = LibraryState().isSaved(mediaId, 'anime');

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          if (isSaved) ...[
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                color: Color(0xFF3A86FF),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4.0),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10.0,
                                fontFamily: 'Outfit',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 9.0,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDayDetailsDialog(int dayNumber) {
    final DateTime targetDate = DateTime(_selectedMonth.year, _selectedMonth.month, dayNumber);
    final String dateString = '${_months[targetDate.month - 1]} ${targetDate.day}, ${targetDate.year}';
    final List<dynamic> daySchedules = _schedulesByDay[dayNumber] ?? [];
    
    final List<dynamic> filteredSchedules = _myListOnly
        ? daySchedules.where((schedule) {
            final mediaId = schedule['mediaId'];
            return LibraryState().isSaved(mediaId, 'anime');
          }).toList()
        : daySchedules;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0F11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          titlePadding: const EdgeInsets.all(20.0),
          contentPadding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 20.0),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Airing on $dateString',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    '${_getWeekdayAbbreviation(targetDate.weekday)} • ${filteredSchedules.length} episodes',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12.0,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          content: SizedBox(
            width: 550.0,
            child: filteredSchedules.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    alignment: Alignment.center,
                    child: const Text(
                      'No airing episodes found.',
                      style: TextStyle(color: Colors.white38, fontFamily: 'Outfit'),
                    ),
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
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
                        final genres = (media['genres'] as List<dynamic>?)?.take(3).join(', ') ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          padding: const EdgeInsets.all(10.0),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(10.0),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context); // Close dialog
                              widget.navigationState.selectAnime(media['id']);
                            },
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6.0),
                                  child: SizedBox(
                                    width: 48.0,
                                    height: 68.0,
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
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.0,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                      const SizedBox(height: 4.0),
                                      Text(
                                        'Episode $episode • $timeStr',
                                        style: const TextStyle(
                                          color: Color(0xFF3A86FF),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                      if (genres.isNotEmpty) ...[
                                        const SizedBox(height: 4.0),
                                        Text(
                                          genres,
                                          style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 10.5,
                                            fontFamily: 'Outfit',
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (rating != null) ...[
                                  const SizedBox(width: 12.0),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4.0),
                                      border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star, color: Colors.amber, size: 10.0),
                                        const SizedBox(width: 4.0),
                                        Text(
                                          rating.toStringAsFixed(1),
                                          style: const TextStyle(
                                            color: Colors.amber,
                                            fontSize: 10.0,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Outfit',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        );
      },
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
      key: _pageKey,
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Spacing to clear floating custom title bar on desktop
                    SizedBox(height: isMobile ? 8.0 : 58.0),

                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12.0 : 20.0,
                        vertical: 12.0,
                      ),
                      child: _buildHeader(isMobile),
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

              ],
            ),
          );
        }
      ),
    );
  }
}
