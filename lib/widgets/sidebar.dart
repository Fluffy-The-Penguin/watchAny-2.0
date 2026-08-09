import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/navigation_state.dart';
import '../state/app_settings.dart';
import '../state/library_providers.dart';
import '../state/user_profile_state.dart';
import '../state/anilist_auth_state.dart';
import 'watch_together_dialog.dart';
import '../services/watch_together_service.dart';
import '../screens/watch_together_room_screen.dart';

import '../services/download_service.dart';

class Sidebar extends StatelessWidget {
  final NavigationState state;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onNotificationsTap;

  const Sidebar({
    super.key,
    required this.state,
    this.onHistoryTap,
    this.onNotificationsTap,
  });

  @override
  Widget build(BuildContext context) {
    final isExpanded = state.isSidebarExpanded;

    return ListenableBuilder(
      listenable: AppSettings(),
      builder: (context, child) {
        return Consumer(
          builder: (context, ref, child) {
            final int notifCount;
            if (state.currentMode == AppMode.anime) {
              notifCount = ref.watch(animeNotificationCountProvider);
            } else if (state.currentMode == AppMode.manga) {
              notifCount = ref.watch(mangaNotificationCountProvider);
            } else {
              notifCount = ref.watch(moviesNotificationCountProvider);
            }

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
                      if (state.currentMode == AppMode.anime) ...[
                        const SizedBox(height: 8.0),
                        _SidebarItem(
                          icon: Icons.calendar_today,
                          label: 'Schedule',
                          isSelected: state.currentPage == TabPage.schedule,
                          isExpanded: isExpanded,
                          onTap: () => state.setPage(TabPage.schedule),
                        ),
                      ],
                      if (state.currentMode != AppMode.manga) ...[
                        const SizedBox(height: 8.0),
                        ListenableBuilder(
                          listenable: DownloadService(),
                          builder: (context, _) {
                            final ds = DownloadService();
                            if (state.currentPage == TabPage.downloads) {
                              ds.clearUnseenCompletions();
                            }
                            
                            Widget? customLeading;
                            int badgeCount = 0;
                            IconData icon = Icons.download_for_offline;
                            
                            if (ds.isDownloading) {
                              badgeCount = ds.activeDownloadingCount;
                              customLeading = Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.downloading_rounded, color: Color(0xFF2EC4B6), size: 20.0),
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF2EC4B6),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            } else if (ds.hasFailed) {
                              customLeading = Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.download_for_offline_outlined, color: Colors.redAccent, size: 20.0),
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            } else if (ds.hasUnseenCompletions) {
                              customLeading = Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.task_alt_rounded, color: Colors.greenAccent, size: 20.0),
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.greenAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            return _SidebarItem(
                              icon: icon,
                              customLeading: customLeading,
                              badgeCount: badgeCount,
                              label: 'Downloads',
                              isSelected: state.currentPage == TabPage.downloads,
                              isExpanded: isExpanded,
                              onTap: () {
                                ds.clearUnseenCompletions();
                                state.setPage(TabPage.downloads);
                              },
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 8.0),
                      _SidebarItem(
                        icon: Icons.history,
                        label: 'History',
                        isSelected: state.currentPage == TabPage.history,
                        isExpanded: isExpanded,
                        onTap: onHistoryTap ?? () => state.setPage(TabPage.history),
                      ),
                      ListenableBuilder(
                        listenable: WatchTogetherService(),
                        builder: (ctx, _) {
                          final wt = WatchTogetherService();
                          return _SidebarItem(
                            icon: Icons.groups_rounded,
                            customLeading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.groups_rounded, color: Colors.deepPurpleAccent, size: 20.0),
                                if (wt.isActive)
                                  Positioned(
                                    top: -2,
                                    right: -2,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: Colors.greenAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            label: wt.isActive ? 'Room Active' : 'Watch Together',
                            isSelected: false,
                            isExpanded: isExpanded,
                            onTap: () {
                              if (wt.isActive) {
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) => const WatchTogetherRoomScreen(),
                                  ),
                                );
                              } else {
                                showDialog(
                                  context: context,
                                  builder: (_) => const WatchTogetherDialog(),
                                );
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 8.0),
                      _SidebarItem(
                        icon: Icons.notifications,
                        label: 'Notifications',
                        isSelected: state.currentPage == TabPage.notifications,
                        isExpanded: isExpanded,
                        badgeCount: notifCount,
                        onTap: onNotificationsTap ?? () => state.setPage(TabPage.notifications),
                      ),
                      const SizedBox(height: 8.0),
                      _SidebarItem(
                        icon: Icons.person,
                        customLeading: _ProfileSidebarAvatar(isSelected: state.currentPage == TabPage.profile),
                        label: 'Profile',
                        isSelected: state.currentPage == TabPage.profile,
                        isExpanded: isExpanded,
                        onTap: () => state.setPage(TabPage.profile),
                      ),
                      const SizedBox(height: 8.0),
                      _SidebarItem(
                        icon: Icons.settings,
                        label: 'Settings',
                        isSelected: state.currentPage == TabPage.settings,
                        isExpanded: isExpanded,
                        onTap: () => state.setPage(TabPage.settings),
                      ),
                    ],
                  ),
                ),

                // Bottom-Left: Mode Selector (hidden if only 1 mode enabled)
                if (AppSettings().enabledModesList.length > 1)
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
      },
    );
  },
);
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final Widget? customLeading;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final int badgeCount;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    this.customLeading,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    this.badgeCount = 0,
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (widget.customLeading != null)
                      widget.customLeading!
                    else
                      Icon(
                        widget.icon,
                        color: widget.isSelected ? Colors.white : Colors.white54,
                        size: 20.0,
                      ),
                    if (widget.badgeCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2EC4B6),
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 12.0,
                            minHeight: 12.0,
                          ),
                          child: Center(
                            child: Text(
                              '${widget.badgeCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 7.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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
        itemBuilder: (BuildContext context) {
          final enabledModes = AppSettings().enabledModesList;
          String _modeLabel(AppMode mode) {
            switch (mode) {
              case AppMode.anime: return 'Anime';
              case AppMode.manga: return 'Manga';
              case AppMode.movies: return 'Movies / Series';
            }
          }
          return enabledModes.map((mode) => PopupMenuItem<AppMode>(
            value: mode,
            child: Row(
              children: [
                Icon(
                  _getModeIcon(mode),
                  color: activeMode == mode ? Colors.white : Colors.white54,
                  size: 18.0,
                ),
                const SizedBox(width: 10),
                Text(
                  _modeLabel(mode),
                  style: TextStyle(
                    color: activeMode == mode ? Colors.white : Colors.white70,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          )).toList();
        },
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

class _ProfileSidebarAvatar extends StatelessWidget {
  final bool isSelected;
  const _ProfileSidebarAvatar({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([UserProfileState(), AnilistAuthState()]),
      builder: (context, _) {
        final userProfile = UserProfileState();
        final anilistAuth = AnilistAuthState();

        final imgProvider = userProfile.getAvatarImageProvider() ??
            (anilistAuth.isLoggedIn && anilistAuth.avatarUrl != null ? NetworkImage(anilistAuth.avatarUrl!) : null);

        if (imgProvider != null) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? const Color(0xFF2EC4B6) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: CircleAvatar(
              radius: 10.0,
              backgroundImage: imgProvider,
              backgroundColor: Colors.white10,
            ),
          );
        }

        final gradients = [
          [const Color(0xFF2EC4B6), const Color(0xFF0F4C81)],
          [const Color(0xFFFF9F1C), const Color(0xFFE71D36)],
          [const Color(0xFFA855F7), const Color(0xFF3B82F6)],
          [const Color(0xFF10B981), const Color(0xFF059669)],
          [const Color(0xFFEC4899), const Color(0xFF8B5CF6)],
          [const Color(0xFFF59E0B), const Color(0xFFD97706)],
          [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
          [const Color(0xFF6366F1), const Color(0xFF4338CA)],
        ];
        final icons = [
          Icons.auto_awesome,
          Icons.bolt,
          Icons.local_fire_department,
          Icons.star_rounded,
          Icons.psychology,
          Icons.favorite,
          Icons.explore,
          Icons.shield,
        ];
        final gradient = gradients[userProfile.avatarIndex % gradients.length];
        final icon = icons[userProfile.avatarIndex % icons.length];

        return Container(
          width: 20.0,
          height: 20.0,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: gradient),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Icon(icon, color: Colors.white, size: 10.0),
          ),
        );
      },
    );
  }
}
