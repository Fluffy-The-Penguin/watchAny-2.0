import 'package:flutter/material.dart';
import '../state/navigation_state.dart';

class Sidebar extends StatelessWidget {
  final NavigationState state;

  const Sidebar({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final isExpanded = state.isSidebarExpanded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: isExpanded ? 220.0 : 60.0,
      color: Colors.black,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(
              color: Colors.white10,
              width: 1.0,
            ),
          ),
        ),
        child: Column(
          children: [
            // Top: Sidebar Collapse/Expand Toggle
            const SizedBox(height: 8.0),
            Align(
              alignment: isExpanded ? Alignment.centerRight : Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(right: isExpanded ? 8.0 : 0.0),
                child: IconButton(
                  icon: Icon(
                    isExpanded ? Icons.chevron_left : Icons.menu,
                    color: Colors.white70,
                  ),
                  onPressed: state.toggleSidebar,
                  tooltip: isExpanded ? 'Collapse' : 'Expand',
                ),
              ),
            ),
            const SizedBox(height: 24.0),

            // Navigation Items: Home, Search, Library
            Expanded(
              child: Column(
                children: [
                  _SidebarItem(
                    icon: Icons.home_filled,
                    label: 'Home',
                    isSelected: state.currentPage == TabPage.home,
                    isExpanded: isExpanded,
                    onTap: () => state.setPage(TabPage.home),
                  ),
                  const SizedBox(height: 8.0),
                  _SidebarItem(
                    icon: Icons.search,
                    label: 'Search',
                    isSelected: state.currentPage == TabPage.search,
                    isExpanded: isExpanded,
                    onTap: () => state.setPage(TabPage.search),
                  ),
                  const SizedBox(height: 8.0),
                  _SidebarItem(
                    icon: Icons.video_library,
                    label: 'Library',
                    isSelected: state.currentPage == TabPage.library,
                    isExpanded: isExpanded,
                    onTap: () => state.setPage(TabPage.library),
                  ),
                  const SizedBox(height: 8.0),
                  _SidebarItem(
                    icon: Icons.calendar_today,
                    label: 'Schedule',
                    isSelected: state.currentPage == TabPage.schedule,
                    isExpanded: isExpanded,
                    onTap: () => state.setPage(TabPage.schedule),
                  ),
                ],
              ),
            ),

            // Bottom-Left: Mode Selector
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? 12.0 : 6.0,
                vertical: 16.0,
              ),
              child: _ModeSelector(
                state: state,
                isExpanded: isExpanded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              vertical: 10.0,
              horizontal: widget.isExpanded ? 12.0 : 8.0,
            ),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? Colors.white.withValues(alpha: 0.08)
                  : (_isHovering ? Colors.white.withValues(alpha: 0.03) : Colors.transparent),
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: Row(
              mainAxisAlignment: widget.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  color: widget.isSelected ? Colors.white : Colors.white54,
                  size: 20.0,
                ),
                if (widget.isExpanded) ...[
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.isSelected ? Colors.white : Colors.white70,
                        fontSize: 14.0,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontFamily: 'Outfit',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSelector extends StatefulWidget {
  final NavigationState state;
  final bool isExpanded;

  const _ModeSelector({
    required this.state,
    required this.isExpanded,
  });

  @override
  State<_ModeSelector> createState() => _ModeSelectorState();
}

class _ModeSelectorState extends State<_ModeSelector> {
  bool _isHovering = false;

  IconData _getModeIcon(AppMode mode) {
    switch (mode) {
      case AppMode.anime:
        return Icons.tv;
      case AppMode.manga:
        return Icons.menu_book;
      case AppMode.movies:
        return Icons.movie;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMode = widget.state.currentMode;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: PopupMenuButton<AppMode>(
        tooltip: 'Change Mode',
        offset: Offset(widget.isExpanded ? 0 : 50, -120),
        color: Colors.grey[950],
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: const BorderSide(color: Colors.white10, width: 1.0),
        ),
        onSelected: (AppMode mode) {
          widget.state.setMode(mode);
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<AppMode>>[
          PopupMenuItem<AppMode>(
            value: AppMode.anime,
            child: Row(
              children: [
                Icon(
                  _getModeIcon(AppMode.anime),
                  color: activeMode == AppMode.anime ? Colors.white : Colors.white54,
                  size: 18.0,
                ),
                const SizedBox(width: 10),
                Text(
                  'Anime',
                  style: TextStyle(
                    color: activeMode == AppMode.anime ? Colors.white : Colors.white70,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem<AppMode>(
            value: AppMode.manga,
            child: Row(
              children: [
                Icon(
                  _getModeIcon(AppMode.manga),
                  color: activeMode == AppMode.manga ? Colors.white : Colors.white54,
                  size: 18.0,
                ),
                const SizedBox(width: 10),
                Text(
                  'Manga',
                  style: TextStyle(
                    color: activeMode == AppMode.manga ? Colors.white : Colors.white70,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem<AppMode>(
            value: AppMode.movies,
            child: Row(
              children: [
                Icon(
                  _getModeIcon(AppMode.movies),
                  color: activeMode == AppMode.movies ? Colors.white : Colors.white54,
                  size: 18.0,
                ),
                const SizedBox(width: 10),
                Text(
                  'Movies / Series',
                  style: TextStyle(
                    color: activeMode == AppMode.movies ? Colors.white : Colors.white70,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            vertical: 10.0,
            horizontal: widget.isExpanded ? 12.0 : 8.0,
          ),
          decoration: BoxDecoration(
            color: _isHovering ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: Colors.white10,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: widget.isExpanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                _getModeIcon(activeMode),
                color: Colors.white,
                size: 20.0,
              ),
              if (widget.isExpanded) ...[
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text(
                    widget.state.modeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Outfit',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  Icons.unfold_more,
                  color: Colors.white30,
                  size: 16.0,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
