import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../state/anilist_auth_state.dart';
import '../state/library_state.dart';
import '../state/navigation_state.dart';
import '../state/player_state.dart';
import '../state/user_profile_state.dart';
import '../services/download_service.dart';
import '../services/cloud_sync_service.dart';

class ProfilePage extends StatefulWidget {
  final NavigationState navigationState;
  const ProfilePage({super.key, required this.navigationState});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  final TextEditingController _anilistTokenController = TextEditingController();
  bool _isConnectingAnilist = false;
  String? _anilistError;
  bool _isImportingAnilist = false;
  String? _importSuccessMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  List<Map<String, dynamic>> _watchHistory = [];

  static const List<List<Color>> _presetGradients = [
    [Color(0xFF2EC4B6), Color(0xFF0F4C81)], // Cyan Ocean
    [Color(0xFFFF9F1C), Color(0xFFE71D36)], // Crimson Sunset
    [Color(0xFFA855F7), Color(0xFF3B82F6)], // Electric Violet
    [Color(0xFF10B981), Color(0xFF059669)], // Emerald Forest
    [Color(0xFFEC4899), Color(0xFF8B5CF6)], // Neon Pink
    [Color(0xFFF59E0B), Color(0xFFD97706)], // Amber Monarch
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // Deep Sapphire
    [Color(0xFF6366F1), Color(0xFF4338CA)], // Indigo Galaxy
  ];

  static const List<IconData> _presetIcons = [
    Icons.auto_awesome,
    Icons.bolt,
    Icons.local_fire_department,
    Icons.star_rounded,
    Icons.psychology,
    Icons.favorite,
    Icons.explore,
    Icons.shield,
  ];

  @override
  void initState() {
    super.initState();
    _anilistTokenController.addListener(_onTokenChanged);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _loadHistoryData();
    _animController.forward();
  }

  Future<void> _loadHistoryData() async {
    final history = await PlayerState.getHistoryList();
    if (mounted) {
      setState(() {
        _watchHistory = history;
      });
    }
  }

  void _onTokenChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _anilistTokenController.removeListener(_onTokenChanged);
    _anilistTokenController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _launchAniListUrl() async {
    const url = 'https://anilist.co/api/v2/oauth/authorize?client_id=45910&response_type=token';
    if (Platform.isWindows) {
      try {
        await Process.run('powershell', ['-Command', 'Start-Process', "'$url'"]);
      } catch (_) {
        try {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
    } else {
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {
        try {
          await launchUrl(Uri.parse(url));
        } catch (_) {}
      }
    }
  }

  // --- Smooth Non-Buggy Edit Profile Modal ---
  void _showEditProfileDialog() {
    final userProfile = UserProfileState();
    final nameCtrl = TextEditingController(text: userProfile.displayName);
    final titleCtrl = TextEditingController(text: userProfile.userTitle);
    final bioCtrl = TextEditingController(text: userProfile.bio);
    final quoteCtrl = TextEditingController(text: userProfile.favoriteQuote);
    final avatarUrlCtrl = TextEditingController(text: userProfile.customAvatarUrl);
    final bannerUrlCtrl = TextEditingController(text: userProfile.customBannerUrl);

    int selectedAvatar = userProfile.avatarIndex;
    int selectedBanner = userProfile.bannerIndex;

    final modalScrollController = ScrollController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF141416),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Container(
            width: 560,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(22.0),
            child: StatefulBuilder(
              builder: (context, setDlgState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Modal Header
                    Row(
                      children: [
                        const Icon(Icons.tune, color: Color(0xFF2EC4B6), size: 22),
                        const SizedBox(width: 10),
                        const Text(
                          'Customize Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                          onPressed: () {
                            modalScrollController.dispose();
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 24),

                    // Scrollable Options Content
                    Expanded(
                      child: Scrollbar(
                        controller: modalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: modalScrollController,
                          physics: const ClampingScrollPhysics(),
                          clipBehavior: Clip.antiAlias,
                          padding: const EdgeInsets.only(right: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            const Text('Display Name', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: nameCtrl,
                              style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                            const SizedBox(height: 14),

                            const Text('Bio / Tagline', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: bioCtrl,
                              style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                            const SizedBox(height: 14),

                            const Text('Favorite Quote', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: quoteCtrl,
                              style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Custom Avatar Image
                            const Text('Custom Profile Image (URL or Local File)', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: avatarUrlCtrl,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 12.5),
                                    decoration: InputDecoration(
                                      hintText: 'https://... or C:\\path\\image.png',
                                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.04),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.folder_open, size: 14),
                                  label: const Text('Browse', style: TextStyle(fontSize: 12, fontFamily: 'Outfit')),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () async {
                                    final result = await FilePicker.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
                                    );
                                    if (result != null && result.files.single.path != null) {
                                      avatarUrlCtrl.text = result.files.single.path!;
                                      setDlgState(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            const Text('Choose Preset Avatar Badge', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: List.generate(_presetGradients.length, (index) {
                                final isSelected = selectedAvatar == index;
                                return GestureDetector(
                                  onTap: () => setDlgState(() => selectedAvatar = index),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(colors: _presetGradients[index]),
                                      border: Border.all(
                                        color: isSelected ? Colors.white : Colors.transparent,
                                        width: 2.5,
                                      ),
                                      boxShadow: isSelected
                                          ? [BoxShadow(color: _presetGradients[index][0].withValues(alpha: 0.6), blurRadius: 8)]
                                          : [],
                                    ),
                                    child: Icon(_presetIcons[index % _presetIcons.length], color: Colors.white, size: 20),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 20),

                            // Custom Banner Image
                            const Text('Custom Header Banner (URL or Local File)', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: bannerUrlCtrl,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 12.5),
                                    decoration: InputDecoration(
                                      hintText: 'https://... or C:\\path\\banner.png',
                                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.04),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.folder_open, size: 14),
                                  label: const Text('Browse', style: TextStyle(fontSize: 12, fontFamily: 'Outfit')),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () async {
                                    final result = await FilePicker.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
                                    );
                                    if (result != null && result.files.single.path != null) {
                                      bannerUrlCtrl.text = result.files.single.path!;
                                      setDlgState(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            const Text('Choose Preset Banner Theme', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: List.generate(_presetGradients.length, (index) {
                                final isSelected = selectedBanner == index;
                                return GestureDetector(
                                  onTap: () => setDlgState(() => selectedBanner = index),
                                  child: Container(
                                    width: 60,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      gradient: LinearGradient(colors: _presetGradients[index]),
                                      border: Border.all(
                                        color: isSelected ? Colors.white : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ),
                    const Divider(color: Colors.white10, height: 24),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            modalScrollController.dispose();
                            Navigator.pop(context);
                          },
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontFamily: 'Outfit')),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2EC4B6),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await userProfile.saveProfile(
                              name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'watchAny Explorer',
                              userTitle: titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : 'Otaku & Cinephile',
                              bio: bioCtrl.text.trim(),
                              quote: quoteCtrl.text.trim(),
                              avatarIdx: selectedAvatar,
                              bannerIdx: selectedBanner,
                              customAvatar: avatarUrlCtrl.text.trim(),
                              customBanner: bannerUrlCtrl.text.trim(),
                            );
                            modalScrollController.dispose();
                            if (mounted) navigator.pop();
                          },
                          child: const Text('Save Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // --- Profile Statistics Computation ---
  Map<String, dynamic> _computeProfileStats() {
    final items = LibraryState().items;
    
    final animeItems = items.where((i) => i.mode == 'anime').toList();
    final mangaItems = items.where((i) => i.mode == 'manga').toList();
    final movieItems = items.where((i) => i.mode == 'movies').toList();

    int watchedEpisodes = 0;
    int animeCompleted = 0;
    int animeWatching = 0;
    int animePlanning = 0;
    int animeDropped = 0;

    for (var item in animeItems) {
      watchedEpisodes += item.watchedEpisodes;
      if (item.libraryStatus == 'completed') {
        animeCompleted++;
      } else if (item.libraryStatus == 'watching') {
        animeWatching++;
      } else if (item.libraryStatus == 'planning') {
        animePlanning++;
      } else if (item.libraryStatus == 'paused_dropped') {
        animeDropped++;
      }
    }

    int readChapters = 0;
    final Map<String, int> mangaCategoriesBreakdown = {};
    final mangaCategories = LibraryState().categories.where((c) => c.mode == 'manga').toList();
    final Map<String, String> catIdToName = { for (var c in mangaCategories) c.id : c.name };

    for (var item in mangaItems) {
      readChapters += item.watchedEpisodes;
      if (item.categoryIds.isEmpty) {
        String statusLabel;
        switch (item.libraryStatus.toLowerCase()) {
          case 'watching':
          case 'reading':
            statusLabel = 'Reading';
            break;
          case 'completed':
            statusLabel = 'Completed';
            break;
          case 'planning':
            statusLabel = 'Planning';
            break;
          case 'paused_dropped':
          case 'dropped':
          case 'paused':
            statusLabel = 'Dropped';
            break;
          default:
            statusLabel = item.libraryStatus.isNotEmpty ? item.libraryStatus : 'Uncategorized';
        }
        final catName = statusLabel;
        mangaCategoriesBreakdown[catName] = (mangaCategoriesBreakdown[catName] ?? 0) + 1;
      } else {
        for (var catId in item.categoryIds) {
          final catName = catIdToName[catId] ?? catId;
          mangaCategoriesBreakdown[catName] = (mangaCategoriesBreakdown[catName] ?? 0) + 1;
        }
      }
    }
    if (mangaCategoriesBreakdown.isEmpty) {
      mangaCategoriesBreakdown['Default'] = 0;
    }

    int moviesCompleted = 0;
    int moviesWatching = 0;
    int moviesPlanning = 0;

    for (var item in movieItems) {
      if (item.libraryStatus == 'completed') {
        moviesCompleted++;
      } else if (item.libraryStatus == 'watching') {
        moviesWatching++;
      } else if (item.libraryStatus == 'planning') {
        moviesPlanning++;
      }
    }

    // Downloads
    final downloads = DownloadService().tasks;
    final completedDownloads = downloads.where((t) => t.status == DownloadStatus.completed).toList();
    int totalDownloadBytes = completedDownloads.fold(0, (sum, t) => sum + t.downloadedBytes);
    final double downloadGB = totalDownloadBytes / (1024 * 1024 * 1024);

    // Watch time estimation (approx 24 mins per episode)
    final double watchHours = (watchedEpisodes * 24) / 60.0;
    final double watchDays = watchHours / 24.0;

    // Rating Distribution (1 to 10)
    final Map<int, int> ratingsDistribution = { for (int i = 1; i <= 10; i++) i: 0 };
    for (var item in items) {
      final rating = item.rating.round();
      if (rating >= 1 && rating <= 10) {
        ratingsDistribution[rating] = (ratingsDistribution[rating] ?? 0) + 1;
      }
    }

    // Weekly Watch Activity Graph (Last 7 Days)
    final now = DateTime.now();
    final List<Map<String, dynamic>> dailyActivity = List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      final dayName = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];
      
      int count = 0;
      for (var record in _watchHistory) {
        final recDate = _parseTimestamp(record['timestamp']);
        if (recDate != null) {
          if (recDate.year == date.year && recDate.month == date.month && recDate.day == date.day) {
            count++;
          }
        }
      }
      return {'day': dayName, 'count': count};
    });

    // Level & XP Calculation
    final int totalXP = (watchedEpisodes * 15) + (readChapters * 8) + (items.length * 20);
    final int level = (sqrt(totalXP) / 4).floor() + 1;
    final int currentLevelXP = ((level - 1) * 4) * ((level - 1) * 4);
    final int nextLevelXP = (level * 4) * (level * 4);
    final double levelProgress = (nextLevelXP - currentLevelXP) > 0
        ? ((totalXP - currentLevelXP) / (nextLevelXP - currentLevelXP)).clamp(0.0, 1.0)
        : 1.0;

    String levelTitle = 'Novice Watcher';
    if (level >= 50) {
      levelTitle = 'Legendary Sovereign';
    } else if (level >= 35) {
      levelTitle = 'Anime Mastermind';
    } else if (level >= 20) {
      levelTitle = 'Otaku Veteran';
    } else if (level >= 10) {
      levelTitle = 'Binge Scholar';
    } else if (level >= 5) {
      levelTitle = 'Avid Explorer';
    }

    return {
      'animeCount': animeItems.length,
      'watchedEpisodes': watchedEpisodes,
      'animeCompleted': animeCompleted,
      'animeWatching': animeWatching,
      'animePlanning': animePlanning,
      'animeDropped': animeDropped,

      'mangaCount': mangaItems.length,
      'readChapters': readChapters,
      'mangaCategoriesBreakdown': mangaCategoriesBreakdown,

      'movieCount': movieItems.length,
      'moviesCompleted': moviesCompleted,
      'moviesWatching': moviesWatching,
      'moviesPlanning': moviesPlanning,

      'downloadCount': completedDownloads.length,
      'downloadGB': downloadGB,

      'watchHours': watchHours,
      'watchDays': watchDays,
      'ratingsDistribution': ratingsDistribution,
      'dailyActivity': dailyActivity,

      'totalXP': totalXP,
      'level': level,
      'levelTitle': levelTitle,
      'levelProgress': levelProgress,
    };
  }

  // --- Hero Header Widget ---
  Widget _buildWatchAnyProfileHeader(Map<String, dynamic> stats) {
    final userProfile = UserProfileState();
    final gradient = _presetGradients[userProfile.bannerIndex % _presetGradients.length];
    final avatarGradient = _presetGradients[userProfile.avatarIndex % _presetGradients.length];
    final avatarIcon = _presetIcons[userProfile.avatarIndex % _presetIcons.length];

    final int level = stats['level'];
    final String levelTitle = stats['levelTitle'];
    final double levelProgress = stats['levelProgress'];

    Widget bannerWidget;
    if (userProfile.customBannerUrl.isNotEmpty) {
      final url = userProfile.customBannerUrl;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        bannerWidget = Image.network(url, height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 150, color: gradient[0]));
      } else {
        final file = File(url);
        bannerWidget = file.existsSync()
            ? Image.file(file, height: 150, width: double.infinity, fit: BoxFit.cover)
            : Container(height: 150, decoration: BoxDecoration(gradient: LinearGradient(colors: gradient)));
      }
    } else {
      bannerWidget = Container(
        height: 150,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
      );
    }

    Widget avatarWidget;
    final customAvatar = userProfile.getAvatarImageProvider();
    final anilistAuth = AnilistAuthState();
    final avatarImg = customAvatar ?? (anilistAuth.isLoggedIn && anilistAuth.avatarUrl != null ? NetworkImage(anilistAuth.avatarUrl!) : null);

    if (avatarImg != null) {
      avatarWidget = CircleAvatar(
        radius: 38.0,
        backgroundImage: avatarImg,
        backgroundColor: Colors.white10,
      );
    } else {
      avatarWidget = Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: avatarGradient),
          boxShadow: [BoxShadow(color: avatarGradient[0].withValues(alpha: 0.5), blurRadius: 10.0)],
        ),
        child: Center(
          child: Icon(avatarIcon, color: Colors.white, size: 38),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withValues(alpha: 0.12),
            blurRadius: 20.0,
            spreadRadius: 2.0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              bannerWidget,
              Container(
                height: 150,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.75)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: ElevatedButton.icon(
                  onPressed: _showEditProfileDialog,
                  icon: const Icon(Icons.tune, size: 14, color: Colors.white),
                  label: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -32,
                left: 24,
                child: Container(
                  padding: const EdgeInsets.all(4.0),
                  decoration: const BoxDecoration(
                    color: Color(0xFF141416),
                    shape: BoxShape.circle,
                  ),
                  child: avatarWidget,
                ),
              ),
            ],
          ),

          const SizedBox(height: 42.0),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      userProfile.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        userProfile.userTitle,
                        style: const TextStyle(
                          color: Color(0xFFA855F7),
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2EC4B6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'LVL $level $levelTitle',
                        style: const TextStyle(
                          color: Color(0xFF2EC4B6),
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                  ],
                ),
                if (userProfile.bio.isNotEmpty) ...[
                  const SizedBox(height: 4.0),
                  Text(
                    userProfile.bio,
                    style: const TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit'),
                  ),
                ],
                if (userProfile.favoriteQuote.isNotEmpty) ...[
                  const SizedBox(height: 6.0),
                  Text(
                    '"${userProfile.favoriteQuote}"',
                    style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontStyle: FontStyle.italic, fontFamily: 'Outfit'),
                  ),
                ],
                const SizedBox(height: 16.0),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Level $level Experience',
                          style: const TextStyle(color: Colors.white54, fontSize: 11.0, fontFamily: 'Outfit'),
                        ),
                        Text(
                          '${(levelProgress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: Color(0xFF2EC4B6), fontSize: 11.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
                      child: LinearProgressIndicator(
                        value: levelProgress,
                        minHeight: 6.0,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Graphs Cards ---
  Widget _buildActivityGraphCard(List<Map<String, dynamic>> dailyActivity) {
    int maxCount = 1;
    for (var item in dailyActivity) {
      if ((item['count'] as int) > maxCount) maxCount = item['count'];
    }

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.insights, color: Color(0xFF2EC4B6), size: 18),
              SizedBox(width: 8),
              Text(
                'Weekly Watch Activity',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              Spacer(),
              Text('Last 7 Days', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit')),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: dailyActivity.map((item) {
                final day = item['day'] as String;
                final count = item['count'] as int;
                final double heightFactor = count > 0 ? (count / maxCount).clamp(0.12, 1.0) : 0.06;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        color: count > 0 ? const Color(0xFF2EC4B6) : Colors.white24,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 24,
                      height: 70 * heightFactor,
                      decoration: BoxDecoration(
                        color: count > 0 ? const Color(0xFF2EC4B6) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        gradient: count > 0
                            ? const LinearGradient(
                                colors: [Color(0xFF2EC4B6), Color(0xFF0F4C81)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      day,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Outfit'),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingsGraphCard(Map<int, int> ratingsDist) {
    int maxCount = 1;
    ratingsDist.forEach((_, count) {
      if (count > maxCount) maxCount = count;
    });

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star, color: Color(0xFFF59E0B), size: 18),
              SizedBox(width: 8),
              Text(
                'Library Ratings Distribution',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              Spacer(),
              Text('Score 1-10', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit')),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(10, (idx) {
                final score = idx + 1;
                final count = ratingsDist[score] ?? 0;
                final double heightFactor = count > 0 ? (count / maxCount).clamp(0.12, 1.0) : 0.06;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        color: count > 0 ? const Color(0xFFF59E0B) : Colors.white24,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 16,
                      height: 70 * heightFactor,
                      decoration: BoxDecoration(
                        color: count > 0 ? const Color(0xFFF59E0B) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                        gradient: count > 0
                            ? const LinearGradient(
                                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$score★',
                      style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'Outfit'),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // --- Metrics & Composition Cards ---
  Widget _buildMetricCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24.0),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
                ),
                const SizedBox(height: 2.0),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 20.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
                const SizedBox(height: 2.0),
                Text(
                  subtitle,
                  style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompositionCard({
    required String title,
    required IconData icon,
    required Color color,
    required int total,
    required Map<String, int> breakdown,
  }) {
    final List<Color> palette = [
      color,
      const Color(0xFFA855F7),
      const Color(0xFF3B82F6),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFFEC4899),
      const Color(0xFF6366F1),
      const Color(0xFFE71D36),
    ];

    Color getEntryColor(String key, int idx) {
      final s = key.toLowerCase();
      if (s == 'completed' || s == 'read') return Colors.green;
      if (s == 'watching' || s == 'reading') return Colors.blueAccent;
      if (s == 'planning') return Colors.amber;
      if (s == 'dropped') return Colors.redAccent;
      return palette[idx % palette.length];
    }

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              const Spacer(),
              Text(
                '$total Items',
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: breakdown.entries.toList().asMap().entries.map((item) {
                    final idx = item.key;
                    final entry = item.value;
                    final count = entry.value;
                    if (count == 0) return const SizedBox.shrink();
                    final segColor = getEntryColor(entry.key, idx);

                    return Expanded(
                      flex: count,
                      child: Container(color: segColor),
                    );
                  }).toList(),
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(height: 8, color: Colors.white.withValues(alpha: 0.05)),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: breakdown.entries.toList().asMap().entries.map((item) {
              final idx = item.key;
              final entry = item.value;
              final count = entry.value;
              final dotColor = getEntryColor(entry.key, idx);

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(
                    '${entry.key}: ',
                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit'),
                  ),
                  Text(
                    '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // --- AniList Sub-Section ---
  Widget _buildAniListLoggedOutView() {
    return Container(
      padding: const EdgeInsets.all(22.0),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFF3DB4F2).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.sync, color: Color(0xFF3DB4F2), size: 22.0),
              SizedBox(width: 10.0),
              Text(
                'Connect AniList Account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          const Text(
            'Link your AniList account to automatically sync watch progress, bookmarks, and list status across devices.',
            style: TextStyle(color: Colors.white54, fontSize: 12.0, height: 1.4, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 20.0),
          _buildStepRow(
            stepNumber: '1',
            title: 'Authorize watchAny',
            description: 'Open the AniList authorization page to generate your secure login token.',
            child: Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_browser, color: Colors.white, size: 16.0),
                  label: const Text(
                    'Open AniList Authorization',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  onPressed: _launchAniListUrl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3DB4F2),
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          _buildStepRow(
            stepNumber: '2',
            title: 'Copy & Paste Token Below',
            description: 'Copy the token provided on the webpage and paste it here.',
            child: Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _anilistTokenController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontFamily: 'Outfit'),
                    decoration: InputDecoration(
                      hintText: 'Paste access token here...',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12.5),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.03),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                      prefixIcon: const Icon(Icons.key, color: Colors.white30, size: 16.0),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste, color: Color(0xFF3DB4F2), size: 16.0),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            _anilistTokenController.text = data!.text!.trim();
                          }
                        },
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Color(0xFF3DB4F2), width: 1.0),
                      ),
                    ),
                  ),
                  if (_anilistError != null) ...[
                    const SizedBox(height: 10.0),
                    Text(
                      _anilistError!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.0, fontWeight: FontWeight.w500),
                    ),
                  ],
                  const SizedBox(height: 14.0),
                  ElevatedButton(
                    onPressed: (_isConnectingAnilist || _anilistTokenController.text.trim().isEmpty)
                        ? null
                        : () async {
                            final token = _anilistTokenController.text.trim();
                            setState(() {
                              _isConnectingAnilist = true;
                              _anilistError = null;
                            });
                            final success = await AnilistAuthState().login(token);
                            if (mounted) {
                              setState(() {
                                _isConnectingAnilist = false;
                                if (!success) {
                                  _anilistError = 'Authentication failed. Please verify the token.';
                                } else {
                                  _anilistTokenController.clear();
                                }
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3DB4F2),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
                      disabledForegroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    ),
                    child: _isConnectingAnilist
                        ? const SizedBox(
                            height: 16.0,
                            width: 16.0,
                            child: CircularProgressIndicator(strokeWidth: 2.0, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Text(
                            'Connect Account',
                            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAniListLoggedInView(AnilistAuthState authState) {
    final daysWatched = (authState.minutesWatched / 1440).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(22.0),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFF3DB4F2).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: authState.avatarUrl != null ? NetworkImage(authState.avatarUrl!) : null,
                backgroundColor: const Color(0xFF3DB4F2),
                child: authState.avatarUrl == null ? const Icon(Icons.person, color: Colors.white, size: 20) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          authState.username ?? 'AniList User',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle, color: Color(0xFF3DB4F2), size: 14),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Connected to AniList Cloud',
                      style: TextStyle(color: const Color(0xFF3DB4F2).withValues(alpha: 0.8), fontSize: 11, fontFamily: 'Outfit'),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white54, size: 18),
                tooltip: 'Disconnect AniList',
                onPressed: () async => await authState.logout(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('Anime Count', style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Outfit')),
                      const SizedBox(height: 4),
                      Text('${authState.animeCount}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                    ],
                  ),
                ),
                Container(width: 1, height: 26, color: Colors.white10),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Episodes Watched', style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Outfit')),
                      const SizedBox(height: 4),
                      Text('${authState.episodesWatched}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                    ],
                  ),
                ),
                Container(width: 1, height: 26, color: Colors.white10),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Time Spent', style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Outfit')),
                      const SizedBox(height: 4),
                      Text('${daysWatched}d', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-Sync Progress', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                    SizedBox(height: 2),
                    Text('Automatically update AniList when anime episode progress changes.', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit')),
                  ],
                ),
              ),
              Switch(
                value: authState.isAutoSyncEnabled,
                activeColor: const Color(0xFF3DB4F2),
                onChanged: (val) async => await authState.setAutoSync(val),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isImportingAnilist) ...[
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF3DB4F2)))),
                SizedBox(width: 10),
                Text('Syncing AniList entries...', style: TextStyle(color: Color(0xFF3DB4F2), fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Outfit')),
              ],
            ),
          ] else ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download, size: 16),
              label: const Text('Sync Anime List from AniList', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
              onPressed: () async {
                setState(() {
                  _isImportingAnilist = true;
                  _importSuccessMessage = null;
                });
                final count = await LibraryState().importFromAnilist('ANIME', authState.accessToken!);
                if (mounted) {
                  setState(() {
                    _isImportingAnilist = false;
                    _importSuccessMessage = count > 0
                        ? 'Successfully synced $count anime items from AniList!'
                        : 'Your anime library is already up to date with AniList.';
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3DB4F2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
          if (_importSuccessMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _importSuccessMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required String stepNumber,
    required String title,
    required String description,
    Widget? child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 10.0,
          backgroundColor: const Color(0xFF3DB4F2),
          child: Text(
            stepNumber,
            style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
        ),
        const SizedBox(width: 14.0),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 2.0),
              Text(
                description,
                style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.4, fontFamily: 'Outfit'),
              ),
              if (child != null) child,
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AnilistAuthState(), LibraryState(), DownloadService(), UserProfileState()]),
      builder: (context, _) {
        final authState = AnilistAuthState();
        final stats = _computeProfileStats();
        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isLargeScreen = screenWidth > 900;
        final bool isMediumScreen = screenWidth > 600 && screenWidth <= 900;

        final List<Map<String, dynamic>> dailyActivity = List<Map<String, dynamic>>.from(stats['dailyActivity']);
        final Map<int, int> ratingsDist = Map<int, int>.from(stats['ratingsDistribution']);

        return Scaffold(
          backgroundColor: Colors.black,
          body: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth > 1200 ? 64.0 : (screenWidth > 600 ? 32.0 : 16.0),
                  vertical: 24.0,
                ),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profile & Analytics',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26.0,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        const Text(
                          'Track your watchAny stats, level progression, activity graphs, and cloud accounts.',
                          style: TextStyle(color: Colors.white54, fontSize: 13.0, fontFamily: 'Outfit'),
                        ),
                        const SizedBox(height: 24.0),

                        const SizedBox(height: 24.0),

                        // 1. Top watchAny Profile Header
                        _buildWatchAnyProfileHeader(stats),
                        const SizedBox(height: 28.0),

                        // 2. Favorite Media Showcase ("Hall of Fame")
                        _buildFavoriteShowcaseSection(),
                        const SizedBox(height: 28.0),

                        // 3. Highlights Metrics Grid
                        if (isLargeScreen || isMediumScreen)
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  icon: Icons.timer_outlined,
                                  color: const Color(0xFF2EC4B6),
                                  title: 'Estimated Watch Time',
                                  value: '${stats['watchHours'].toStringAsFixed(1)} hrs',
                                  subtitle: '${stats['watchDays'].toStringAsFixed(1)} days spent watching',
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: Icons.play_circle_fill,
                                  color: const Color(0xFF3B82F6),
                                  title: 'Episodes & Chapters',
                                  value: '${stats['watchedEpisodes']} Ep / ${stats['readChapters']} Ch',
                                  subtitle: 'Watched & Read in library',
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: Icons.download_done_rounded,
                                  color: const Color(0xFF10B981),
                                  title: 'Offline Downloads',
                                  value: '${stats['downloadCount']} Files',
                                  subtitle: '${stats['downloadGB'].toStringAsFixed(1)} GB stored locally',
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _buildMetricCard(
                                icon: Icons.timer_outlined,
                                color: const Color(0xFF2EC4B6),
                                title: 'Estimated Watch Time',
                                value: '${stats['watchHours'].toStringAsFixed(1)} hrs',
                                subtitle: '${stats['watchDays'].toStringAsFixed(1)} days spent watching',
                              ),
                              const SizedBox(height: 12),
                              _buildMetricCard(
                                icon: Icons.play_circle_fill,
                                color: const Color(0xFF3B82F6),
                                title: 'Episodes & Chapters',
                                value: '${stats['watchedEpisodes']} Ep / ${stats['readChapters']} Ch',
                                subtitle: 'Watched & Read in library',
                              ),
                              const SizedBox(height: 12),
                              _buildMetricCard(
                                icon: Icons.download_done_rounded,
                                color: const Color(0xFF10B981),
                                title: 'Offline Downloads',
                                value: '${stats['downloadCount']} Files',
                                subtitle: '${stats['downloadGB'].toStringAsFixed(1)} GB stored locally',
                              ),
                            ],
                          ),
                        const SizedBox(height: 28.0),

                        // 4. Continue Watching / Recent Activity Carousel
                        _buildRecentWatchHistoryCarousel(),
                        const SizedBox(height: 28.0),

                        // 5. Activity & Ratings Interactive Graphs
                        if (isLargeScreen)
                          Row(
                            children: [
                              Expanded(child: _buildActivityGraphCard(dailyActivity)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildRatingsGraphCard(ratingsDist)),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _buildActivityGraphCard(dailyActivity),
                              const SizedBox(height: 16),
                              _buildRatingsGraphCard(ratingsDist),
                            ],
                          ),
                        const SizedBox(height: 28.0),

                        // 6. Media Breakdown & Top Genre Preferences
                        if (isLargeScreen)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildCompositionCard(
                                  title: 'Anime Library',
                                  icon: Icons.tv,
                                  color: const Color(0xFF2EC4B6),
                                  total: stats['animeCount'],
                                  breakdown: {
                                    'Watching': stats['animeWatching'],
                                    'Completed': stats['animeCompleted'],
                                    'Planning': stats['animePlanning'],
                                    'Dropped': stats['animeDropped'],
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildCompositionCard(
                                  title: 'Manga Categories',
                                  icon: Icons.book,
                                  color: const Color(0xFFA855F7),
                                  total: stats['mangaCount'],
                                  breakdown: Map<String, int>.from(stats['mangaCategoriesBreakdown']),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildCompositionCard(
                                  title: 'Movies & Series',
                                  icon: Icons.movie_outlined,
                                  color: const Color(0xFFF59E0B),
                                  total: stats['movieCount'],
                                  breakdown: {
                                    'Watching': stats['moviesWatching'],
                                    'Completed': stats['moviesCompleted'],
                                    'Planning': stats['moviesPlanning'],
                                  },
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _buildCompositionCard(
                                title: 'Anime Library',
                                icon: Icons.tv,
                                color: const Color(0xFF2EC4B6),
                                total: stats['animeCount'],
                                breakdown: {
                                  'Watching': stats['animeWatching'],
                                  'Completed': stats['animeCompleted'],
                                  'Planning': stats['animePlanning'],
                                  'Dropped': stats['animeDropped'],
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildCompositionCard(
                                title: 'Manga Categories',
                                icon: Icons.book,
                                color: const Color(0xFFA855F7),
                                total: stats['mangaCount'],
                                breakdown: Map<String, int>.from(stats['mangaCategoriesBreakdown']),
                              ),
                              const SizedBox(height: 16),
                              _buildCompositionCard(
                                title: 'Movies & Series',
                                icon: Icons.movie_outlined,
                                color: const Color(0xFFF59E0B),
                                total: stats['movieCount'],
                                breakdown: {
                                  'Watching': stats['moviesWatching'],
                                  'Completed': stats['moviesCompleted'],
                                  'Planning': stats['moviesPlanning'],
                                },
                              ),
                            ],
                          ),
                        const SizedBox(height: 28.0),

                        // 7. Genre Preferences
                        _buildGenreBreakdownSection(),
                        const SizedBox(height: 28.0),

                        // 8. Milestones & Achievements
                        _buildAchievementsSection(stats),
                        const SizedBox(height: 32.0),

                        // 9. Cloud Integration Section Header
                        const Row(
                          children: [
                            Icon(Icons.cloud_sync, color: Color(0xFF3DB4F2), size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Cloud Services & Integrations',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14.0),

                        // watchAny Native Cloud Account Sync
                        _buildCloudSyncSection(),

                        // AniList Sub-Section below
                        if (authState.isLoggedIn)
                          _buildAniListLoggedInView(authState)
                        else
                          _buildAniListLoggedOutView(),

                        const SizedBox(height: 40.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- watchAny Cloud Account & Sync Widgets ---

  Widget _buildCloudSyncSection() {
    return ListenableBuilder(
      listenable: CloudSyncService(),
      builder: (context, _) {
        final syncService = CloudSyncService();
        final isLoggedIn = syncService.isLoggedIn;
        final isSyncing = syncService.isSyncing;
        final lastTime = syncService.lastSyncTime;

        String syncTimeText = 'Never synced';
        if (lastTime != null) {
          final diff = DateTime.now().difference(lastTime);
          if (diff.inSeconds < 60) {
            syncTimeText = 'Just now';
          } else if (diff.inMinutes < 60) {
            syncTimeText = '${diff.inMinutes}m ago';
          } else if (diff.inHours < 24) {
            syncTimeText = '${diff.inHours}h ago';
          } else {
            syncTimeText = '${diff.inDays}d ago';
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 24.0),
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: isLoggedIn ? const Color(0xFF2EC4B6).withValues(alpha: 0.3) : Colors.white12,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isLoggedIn ? const Color(0xFF2EC4B6) : const Color(0xFF3B82F6)).withValues(alpha: 0.08),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isLoggedIn ? const Color(0xFF2EC4B6) : const Color(0xFF3B82F6)).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_sync_rounded,
                      color: isLoggedIn ? const Color(0xFF2EC4B6) : const Color(0xFF3B82F6),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isLoggedIn ? 'watchAny Cloud Account (Synced)' : 'watchAny Cloud Account & Sync',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isLoggedIn
                              ? 'Connected as ${syncService.userEmail ?? syncService.username ?? 'Cloud User'}'
                              : '1-Click Stremio-style sync across PC, Mobile, and Android TV',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isLoggedIn)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: syncService.status == SyncStatus.error
                            ? Colors.red.withValues(alpha: 0.2)
                            : (isSyncing
                                ? Colors.amber.withValues(alpha: 0.2)
                                : const Color(0xFF2EC4B6).withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: syncService.status == SyncStatus.error
                              ? Colors.redAccent
                              : (isSyncing ? Colors.amber : const Color(0xFF2EC4B6)),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSyncing)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                            )
                          else
                            Icon(
                              syncService.status == SyncStatus.error ? Icons.error_outline : Icons.check_circle_rounded,
                              size: 12,
                              color: syncService.status == SyncStatus.error ? Colors.redAccent : const Color(0xFF2EC4B6),
                            ),
                          const SizedBox(width: 6),
                          Text(
                            isSyncing
                                ? 'Syncing...'
                                : (syncService.status == SyncStatus.error ? 'Sync Error' : 'Synced'),
                            style: TextStyle(
                              color: syncService.status == SyncStatus.error
                                  ? Colors.redAccent
                                  : (isSyncing ? Colors.amber : const Color(0xFF2EC4B6)),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (syncService.lastErrorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          syncService.lastErrorMessage!,
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Outfit'),
                        ),
                      ),
                    ],
                  ),
                ),
              if (isLoggedIn)
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: isSyncing ? null : () => syncService.syncNow(),
                      icon: isSyncing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync_rounded, size: 16),
                      label: const Text('Sync Now', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2EC4B6),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _showAuthDialog(context, initialTab: 2),
                      icon: const Icon(Icons.settings_outlined, size: 16, color: Colors.white70),
                      label: const Text('Server Settings', style: TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Last sync: $syncTimeText',
                      style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => syncService.logout(),
                      child: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'Outfit')),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _showAuthDialog(context, initialTab: 0),
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: const Text('Log In / Create Account', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showAuthDialog(context, initialTab: 2),
                      icon: const Icon(Icons.dns_rounded, size: 16, color: Colors.white70),
                      label: const Text('Server URL', style: TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAuthDialog(BuildContext context, {int initialTab = 0}) {
    final syncService = CloudSyncService();
    final loginUserCtrl = TextEditingController();
    final loginPassCtrl = TextEditingController();

    final regUserCtrl = TextEditingController();
    final regEmailCtrl = TextEditingController();
    final regPassCtrl = TextEditingController();
    final regConfirmCtrl = TextEditingController();

    final serverUrlCtrl = TextEditingController(text: syncService.serverUrl);

    bool isSubmitting = false;
    String? modalError;
    bool showPass = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DefaultTabController(
              length: 3,
              initialIndex: initialTab,
              child: Dialog(
                backgroundColor: const Color(0xFF141416),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Container(
                  width: 460,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_rounded, color: Color(0xFF3B82F6), size: 22),
                          const SizedBox(width: 10),
                          const Text(
                            'watchAny Cloud Account',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const TabBar(
                        indicatorColor: Color(0xFF3B82F6),
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white38,
                        labelStyle: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 13),
                        tabs: [
                          Tab(text: 'Log In'),
                          Tab(text: 'Create Account'),
                          Tab(text: 'Server Settings'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (modalError != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  modalError!,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Outfit'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        height: 280,
                        child: TabBarView(
                          children: [
                            // 1. LOGIN TAB
                            SingleChildScrollView(
                              child: Column(
                                children: [
                                  TextField(
                                    controller: loginUserCtrl,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Email or Username',
                                      labelStyle: const TextStyle(color: Colors.white54, fontFamily: 'Outfit'),
                                      prefixIcon: const Icon(Icons.person_outline, color: Colors.white54, size: 18),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.05),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: loginPassCtrl,
                                    obscureText: !showPass,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      labelStyle: const TextStyle(color: Colors.white54, fontFamily: 'Outfit'),
                                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white54, size: 18),
                                      suffixIcon: IconButton(
                                        icon: Icon(showPass ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 18),
                                        onPressed: () => setModalState(() => showPass = !showPass),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.05),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 44,
                                    child: ElevatedButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              if (loginUserCtrl.text.trim().isEmpty || loginPassCtrl.text.isEmpty) {
                                                setModalState(() => modalError = 'Please enter both username/email and password');
                                                return;
                                              }
                                              setModalState(() {
                                                isSubmitting = true;
                                                modalError = null;
                                              });

                                              final success = await syncService.login(
                                                serverUrl: serverUrlCtrl.text.trim(),
                                                emailOrUsername: loginUserCtrl.text.trim(),
                                                password: loginPassCtrl.text,
                                              );

                                              if (mounted) {
                                                if (success) {
                                                  Navigator.pop(context);
                                                } else {
                                                  setModalState(() {
                                                    isSubmitting = false;
                                                    modalError = syncService.lastErrorMessage ?? 'Login failed';
                                                  });
                                                }
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF3B82F6),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: isSubmitting
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Text('Log In', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 2. REGISTER TAB
                            SingleChildScrollView(
                              child: Column(
                                children: [
                                  TextField(
                                    controller: regUserCtrl,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Username',
                                      labelStyle: const TextStyle(color: Colors.white54, fontFamily: 'Outfit'),
                                      prefixIcon: const Icon(Icons.person_outline, color: Colors.white54, size: 18),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.05),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: regEmailCtrl,
                                    keyboardType: TextInputType.emailAddress,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Email Address',
                                      labelStyle: const TextStyle(color: Colors.white54, fontFamily: 'Outfit'),
                                      prefixIcon: const Icon(Icons.email_outlined, color: Colors.white54, size: 18),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.05),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: regPassCtrl,
                                    obscureText: !showPass,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Password (min 6 chars)',
                                      labelStyle: const TextStyle(color: Colors.white54, fontFamily: 'Outfit'),
                                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white54, size: 18),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.05),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: regConfirmCtrl,
                                    obscureText: !showPass,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Confirm Password',
                                      labelStyle: const TextStyle(color: Colors.white54, fontFamily: 'Outfit'),
                                      prefixIcon: const Icon(Icons.lock_clock_outlined, color: Colors.white54, size: 18),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.05),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 44,
                                    child: ElevatedButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              if (regUserCtrl.text.trim().length < 3) {
                                                setModalState(() => modalError = 'Username must be at least 3 characters');
                                                return;
                                              }
                                              if (!regEmailCtrl.text.contains('@')) {
                                                setModalState(() => modalError = 'Please enter a valid email address');
                                                return;
                                              }
                                              if (regPassCtrl.text.length < 6) {
                                                setModalState(() => modalError = 'Password must be at least 6 characters');
                                                return;
                                              }
                                              if (regPassCtrl.text != regConfirmCtrl.text) {
                                                setModalState(() => modalError = 'Passwords do not match');
                                                return;
                                              }
                                              setModalState(() {
                                                isSubmitting = true;
                                                modalError = null;
                                              });

                                              final success = await syncService.register(
                                                serverUrl: serverUrlCtrl.text.trim(),
                                                username: regUserCtrl.text.trim(),
                                                email: regEmailCtrl.text.trim(),
                                                password: regPassCtrl.text,
                                              );

                                              if (mounted) {
                                                if (success) {
                                                  Navigator.pop(context);
                                                } else {
                                                  setModalState(() {
                                                    isSubmitting = false;
                                                    modalError = syncService.lastErrorMessage ?? 'Registration failed';
                                                  });
                                                }
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF2EC4B6),
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: isSubmitting
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                          : const Text('Create Account', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 3. SERVER SETTINGS TAB
                            SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cloud Sync Server Address:',
                                    style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Outfit'),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: serverUrlCtrl,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Server URL',
                                      hintText: CloudSyncService.defaultServerUrl,
                                      labelStyle: const TextStyle(color: Colors.white54, fontFamily: 'Outfit'),
                                      prefixIcon: const Icon(Icons.dns_outlined, color: Colors.white54, size: 18),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.05),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextButton.icon(
                                    onPressed: () {
                                      serverUrlCtrl.text = CloudSyncService.defaultServerUrl;
                                    },
                                    icon: const Icon(Icons.restore, size: 14, color: Color(0xFF3B82F6)),
                                    label: const Text('Reset to Default Server (fi10.bot-hosting.net)', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12, fontFamily: 'Outfit')),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 44,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        syncService.setServerUrl(serverUrlCtrl.text.trim());
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Server URL updated to ${syncService.serverUrl}'),
                                            backgroundColor: const Color(0xFF2EC4B6),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: const Text('Save Server URL', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                  ),
                                ],
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
          },
        );
      },
    );
  }
  // --- Media Parsing Helpers ---
  DateTime? _parseTimestamp(dynamic ts) {
    if (ts == null) return null;
    if (ts is int) {
      return DateTime.fromMillisecondsSinceEpoch(ts);
    }
    if (ts is String) {
      final asInt = int.tryParse(ts);
      if (asInt != null) {
        return DateTime.fromMillisecondsSinceEpoch(asInt);
      }
      return DateTime.tryParse(ts);
    }
    return null;
  }

  String _parseTitleValue(dynamic rawTitle) {
    if (rawTitle == null) return 'Untitled';
    if (rawTitle is Map) {
      final t = (rawTitle['userPreferred'] ?? rawTitle['english'] ?? rawTitle['romaji'] ?? rawTitle['native'])?.toString().trim();
      if (t != null && t.isNotEmpty) return t;
    } else {
      final t = rawTitle.toString().trim();
      if (t.isNotEmpty && !t.startsWith('{')) return t;
    }
    return 'Untitled';
  }

  String _getMediaTitle(dynamic item) {
    if (item == null) return 'Untitled';
    if (item is Map) {
      final media = item['media'] is Map ? item['media'] as Map : null;
      if (media != null && media['title'] != null) {
        final t = _parseTitleValue(media['title']);
        if (t != 'Untitled' && t.isNotEmpty) return t;
      }
      final rawTitle = item['title'];
      if (rawTitle != null) {
        final t = _parseTitleValue(rawTitle);
        if (t != 'Untitled' && t.isNotEmpty) return t;
      }
      if (item['name'] != null && item['name'].toString().trim().isNotEmpty) {
        return item['name'].toString().trim();
      }

      // Fallback: Lookup in LibraryState caches by ID
      final idRaw = item['id'] ?? item['anilistId'] ?? item['movieId'];
      if (idRaw != null) {
        final idStr = idRaw.toString();
        final idInt = int.tryParse(idStr);

        if (idInt != null && LibraryState().animeCache.containsKey(idInt)) {
          final cached = LibraryState().animeCache[idInt] ?? {};
          final t = _parseTitleValue(cached['title']);
          if (t != 'Untitled' && t.isNotEmpty) return t;
        }

        if (idInt != null && LibraryState().mangaCache.containsKey(idInt)) {
          final cached = LibraryState().mangaCache[idInt] ?? {};
          final t = _parseTitleValue(cached['title']);
          if (t != 'Untitled' && t.isNotEmpty) return t;
        }

        if (LibraryState().movieCache.containsKey(idStr)) {
          final cached = LibraryState().movieCache[idStr] ?? {};
          final t = _parseTitleValue(cached['title']);
          if (t != 'Untitled' && t.isNotEmpty) return t;
        }
      }
    }
    final str = item.toString().trim();
    if (str.isEmpty || str.startsWith('{')) return 'Untitled';
    return str;
  }

  String _parseCoverValue(dynamic rawCover) {
    if (rawCover == null) return '';
    if (rawCover is Map) {
      final c = (rawCover['extraLarge'] ?? rawCover['large'] ?? rawCover['medium'])?.toString().trim();
      if (c != null && c.isNotEmpty) return c;
    } else {
      final c = rawCover.toString().trim();
      if (c.isNotEmpty && !c.startsWith('{')) return c;
    }
    return '';
  }

  String _getMediaCover(dynamic item) {
    if (item == null) return '';
    if (item is Map) {
      final media = item['media'] is Map ? item['media'] as Map : null;
      if (media != null) {
        if (media['coverImage'] != null) {
          final c = _parseCoverValue(media['coverImage']);
          if (c.isNotEmpty) return c;
        }
        if (media['bannerImage'] != null && media['bannerImage'].toString().isNotEmpty) {
          return media['bannerImage'].toString();
        }
      }
      final rawCover = item['cover'] ?? item['coverUrl'] ?? item['coverImage'] ?? item['posterPath'] ?? item['poster'] ?? item['thumbnailUrl'];
      if (rawCover != null) {
        final c = _parseCoverValue(rawCover);
        if (c.isNotEmpty) return c;
      }

      // Fallback: Lookup in LibraryState caches by ID
      final idRaw = item['id'] ?? item['anilistId'] ?? item['movieId'];
      if (idRaw != null) {
        final idStr = idRaw.toString();
        final idInt = int.tryParse(idStr);

        if (idInt != null && LibraryState().animeCache.containsKey(idInt)) {
          final cached = LibraryState().animeCache[idInt] ?? {};
          final c = _parseCoverValue(cached['coverImage'] ?? cached['coverUrl'] ?? cached['cover']);
          if (c.isNotEmpty) return c;
        }

        if (idInt != null && LibraryState().mangaCache.containsKey(idInt)) {
          final cached = LibraryState().mangaCache[idInt] ?? {};
          final c = _parseCoverValue(cached['coverImage'] ?? cached['coverUrl'] ?? cached['cover'] ?? cached['thumbnailUrl']);
          if (c.isNotEmpty) return c;
        }

        if (LibraryState().movieCache.containsKey(idStr)) {
          final cached = LibraryState().movieCache[idStr] ?? {};
          final c = _parseCoverValue(cached['coverImage'] ?? cached['coverUrl'] ?? cached['posterPath'] ?? cached['cover']);
          if (c.isNotEmpty) return c;
        }
      }
    }
    final str = item.toString().trim();
    if (str.isEmpty || str.startsWith('{')) return '';
    return str;
  }

  // --- New Profile Enhancement Widgets ---

  Widget _buildFavoriteShowcaseSection() {
    final userProfile = UserProfileState();
    final favorites = userProfile.favoriteItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.star_rounded, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Text(
              'Hall of Fame / Favorites',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final double width = (constraints.maxWidth - 4 * 12) / 5;
            final double cardWidth = width.clamp(100.0, 220.0);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(5, (index) {
                final Map<String, dynamic> item = index < favorites.length ? favorites[index] : {};
                final String title = _getMediaTitle(item);
                final String cover = _getMediaCover(item);
                final bool hasItem = item.isNotEmpty && (title != 'Untitled' || cover.isNotEmpty);
                final rankColors = [
                  const Color(0xFFFFD700), // #1 Gold
                  const Color(0xFFC0C0C0), // #2 Silver
                  const Color(0xFFCD7F32), // #3 Bronze
                  const Color(0xFFA855F7), // #4 Purple
                  const Color(0xFF2EC4B6), // #5 Teal / Cyan
                ];
                final rankColor = rankColors[index % rankColors.length];

                return InkWell(
                  onTap: () => _showFavoritePickerModal(index),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: cardWidth,
                    height: cardWidth * 1.35,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hasItem ? rankColor.withValues(alpha: 0.5) : Colors.white10,
                        width: hasItem ? 1.5 : 1.0,
                      ),
                      boxShadow: hasItem
                          ? [BoxShadow(color: rankColor.withValues(alpha: 0.15), blurRadius: 10)]
                          : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (hasItem && cover.isNotEmpty)
                          Positioned.fill(
                            child: Image.network(
                              cover,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: Colors.white10),
                            ),
                          ),
                        if (hasItem)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ),
                        if (!hasItem)
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.add_circle_outline, color: Colors.white38, size: 28),
                                const SizedBox(height: 6),
                                Text(
                                  'Add Slot #${index + 1}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit'),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          Positioned(
                            bottom: 8,
                            left: 8,
                            right: 8,
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => userProfile.removeFavoriteItem(index),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white70, size: 12),
                              ),
                            ),
                          ),
                        ],
                        // Rank Badge
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: rankColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#${index + 1}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  void _showFavoritePickerModal(int slotIndex) {
    final libraryState = LibraryState();
    final animeSaved = libraryState.items.where((i) => i.mode == 'anime').toList();
    final mangaSaved = libraryState.items.where((i) => i.mode == 'manga').toList();

    final animeItems = animeSaved.map((item) {
      final cached = libraryState.animeCache[item.id] ?? {};
      return {
        'id': item.id.toString(),
        'title': _getMediaTitle(cached.isNotEmpty ? cached : item),
        'cover': _getMediaCover(cached.isNotEmpty ? cached : item),
        'type': 'anime',
      };
    }).toList();

    final mangaItems = mangaSaved.map((item) {
      final cached = libraryState.mangaCache[item.id] ?? {};
      return {
        'id': item.id.toString(),
        'title': _getMediaTitle(cached.isNotEmpty ? cached : item),
        'cover': _getMediaCover(cached.isNotEmpty ? cached : item),
        'type': 'manga',
      };
    }).toList();

    showDialog(
      context: context,
      builder: (context) {
        return DefaultTabController(
          length: 3,
          child: Dialog(
            backgroundColor: const Color(0xFF141416),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Container(
              width: 500,
              height: 520,
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Select Favorite #${slotIndex + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const TabBar(
                    indicatorColor: Color(0xFF2EC4B6),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white38,
                    labelStyle: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: [
                      Tab(text: 'Anime'),
                      Tab(text: 'Manga'),
                      Tab(text: 'History'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildPickerGrid(animeItems, slotIndex),
                        _buildPickerGrid(mangaItems, slotIndex),
                        _buildPickerGrid(_watchHistory.map((e) => {
                          'id': (e['id'] ?? e['anilistId'] ?? '').toString(),
                          'title': _getMediaTitle(e),
                          'cover': _getMediaCover(e),
                          'type': (e['isManga'] == true ? 'manga' : (e['isMovie'] == true ? 'movie' : 'anime')).toString(),
                        }).toList(), slotIndex),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPickerGrid(List<Map<String, String>> items, int slotIndex) {
    if (items.isEmpty) {
      return const Center(
        child: Text('No items found in this section.', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit', fontSize: 13)),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, idx) {
        final item = items[idx];
        final title = _getMediaTitle(item);
        final cover = _getMediaCover(item);

        return InkWell(
          onTap: () {
            UserProfileState().setFavoriteItem(slotIndex, {
              'id': item['id'] ?? '',
              'title': title,
              'cover': cover,
              'type': item['type'] ?? 'anime',
            });
            Navigator.pop(context);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                if (cover.isNotEmpty)
                  Positioned.fill(
                    child: Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.white10),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  right: 6,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentWatchHistoryCarousel() {
    if (_watchHistory.isEmpty) return const SizedBox.shrink();

    final recentItems = _watchHistory.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history_toggle_off, color: Color(0xFF3B82F6), size: 20),
            const SizedBox(width: 8),
            const Text(
              'Continue Watching / Recent Activity',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                widget.navigationState.setPage(TabPage.history);
              },
              child: const Text('View All', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12, fontFamily: 'Outfit')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: recentItems.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = recentItems[index];
              final title = _getMediaTitle(item);
              final cover = _getMediaCover(item);
              final eps = item['episodes'] is List ? item['episodes'] as List : [];
              final epText = eps.isNotEmpty ? 'Ep ${eps.last}' : '';
              final double pos = (item['position'] ?? 0).toDouble();
              final double dur = (item['duration'] ?? 1).toDouble();
              final double progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;

              return InkWell(
                onTap: () {
                  final isManga = item['isManga'] ?? false;
                  final isAnime = item['isAnime'] ?? true;
                  if (isManga) {
                    widget.navigationState.selectManga(item['id'].toString());
                  } else if (isAnime) {
                    final idInt = int.tryParse(item['id'].toString());
                    if (idInt != null) {
                      widget.navigationState.selectAnime(idInt);
                    }
                  } else {
                    widget.navigationState.selectMovie(item['id'].toString());
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            if (cover.isNotEmpty)
                              Positioned.fill(
                                child: Image.network(
                                  cover,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: Colors.white10),
                                ),
                              )
                            else
                              Container(color: const Color(0xFF1E1E24)),
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                            if (epText.isNotEmpty)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    epText,
                                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Outfit'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (progress > 0)
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                        ),
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

  Widget _buildGenreBreakdownSection() {
    final animeCache = LibraryState().animeCache;
    final mangaCache = LibraryState().mangaCache;

    final Map<String, int> genreCounts = {};
    for (var a in animeCache.values) {
      final genres = a['genres'];
      if (genres is List) {
        for (var g in genres) {
          final str = g.toString().trim();
          if (str.isNotEmpty) {
            genreCounts[str] = (genreCounts[str] ?? 0) + 1;
          }
        }
      }
    }
    for (var m in mangaCache.values) {
      final genres = m['genres'];
      if (genres is List) {
        for (var g in genres) {
          final str = g.toString().trim();
          if (str.isNotEmpty) {
            genreCounts[str] = (genreCounts[str] ?? 0) + 1;
          }
        }
      }
    }

    if (genreCounts.isEmpty) return const SizedBox.shrink();

    final sortedGenres = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = sortedGenres.take(5).toList();
    final int totalGenreHits = topGenres.fold(0, (sum, e) => sum + e.value);

    final colors = [
      const Color(0xFF2EC4B6),
      const Color(0xFFA855F7),
      const Color(0xFFFF9F1C),
      const Color(0xFF3B82F6),
      const Color(0xFFEC4899),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.donut_small_rounded, color: Color(0xFFA855F7), size: 20),
              SizedBox(width: 8),
              Text(
                'Top Genre Preferences',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(topGenres.length, (idx) {
            final entry = topGenres[idx];
            final color = colors[idx % colors.length];
            final double percent = totalGenreHits > 0 ? (entry.value / totalGenreHits) : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(entry.key, style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Outfit')),
                        ],
                      ),
                      Text(
                        '${entry.value} titles (${(percent * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Outfit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection(Map<String, dynamic> stats) {
    final int watchEp = stats['watchedEpisodes'] ?? 0;
    final int movieCount = stats['movieCount'] ?? 0;
    final int readCh = stats['readChapters'] ?? 0;
    final double watchHours = stats['watchHours'] ?? 0.0;
    final double downloadGB = stats['downloadGB'] ?? 0.0;
    final int animeCompleted = stats['animeCompleted'] ?? 0;
    final int moviesCompleted = stats['moviesCompleted'] ?? 0;
    final bool isAnilistAuth = AnilistAuthState().isLoggedIn;

    final achievements = [
      {
        'title': 'First Light',
        'desc': 'Began your watch journey on watchAny',
        'icon': Icons.flare,
        'color': const Color(0xFF2EC4B6),
        'unlocked': (watchEp + movieCount + readCh) > 0,
        'progressStr': '${(watchEp + movieCount + readCh).clamp(0, 1)} / 1',
      },
      {
        'title': 'Marathon Runner',
        'desc': 'Accumulated 10+ hours watch time',
        'icon': Icons.directions_run,
        'color': const Color(0xFFFF9F1C),
        'unlocked': watchHours >= 10.0,
        'progressStr': '${watchHours.toStringAsFixed(1)} / 10.0 hrs',
      },
      {
        'title': 'Otaku Royalty',
        'desc': 'Accumulated 50+ hours watch time',
        'icon': Icons.workspace_premium,
        'color': const Color(0xFFA855F7),
        'unlocked': watchHours >= 50.0,
        'progressStr': '${watchHours.toStringAsFixed(1)} / 50.0 hrs',
      },
      {
        'title': 'Manga Scholar',
        'desc': 'Read 25+ manga chapters',
        'icon': Icons.menu_book,
        'color': const Color(0xFFEC4899),
        'unlocked': readCh >= 25,
        'progressStr': '$readCh / 25 ch',
      },
      {
        'title': 'Data Vault',
        'desc': 'Saved 5+ GB offline downloads',
        'icon': Icons.sd_storage_rounded,
        'color': const Color(0xFF10B981),
        'unlocked': downloadGB >= 5.0,
        'progressStr': '${downloadGB.toStringAsFixed(1)} / 5.0 GB',
      },
      {
        'title': 'Completionist',
        'desc': 'Completed 5+ series or movies',
        'icon': Icons.verified_rounded,
        'color': const Color(0xFF3B82F6),
        'unlocked': (animeCompleted + moviesCompleted) >= 5,
        'progressStr': '${animeCompleted + moviesCompleted} / 5 completed',
      },
      {
        'title': 'History Chronicler',
        'desc': 'Recorded 5+ watch history entries',
        'icon': Icons.history_edu,
        'color': const Color(0xFFF59E0B),
        'unlocked': _watchHistory.length >= 5,
        'progressStr': '${_watchHistory.length} / 5 entries',
      },
      {
        'title': 'Cloud Synced',
        'desc': 'Linked external AniList account',
        'icon': Icons.cloud_done,
        'color': const Color(0xFF00B4D8),
        'unlocked': isAnilistAuth,
        'progressStr': isAnilistAuth ? 'Linked' : 'Not linked',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.emoji_events, color: Color(0xFFFF9F1C), size: 20),
            SizedBox(width: 8),
            Text(
              'Milestones & Achievements',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 110,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: achievements.length,
          itemBuilder: (context, idx) {
            final ach = achievements[idx];
            final bool unlocked = ach['unlocked'] as bool;
            final Color color = ach['color'] as Color;

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: unlocked ? const Color(0xFF141416) : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: unlocked ? color.withValues(alpha: 0.4) : Colors.white10,
                  width: unlocked ? 1.5 : 1.0,
                ),
                boxShadow: unlocked
                    ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 10)]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: unlocked ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      ach['icon'] as IconData,
                      color: unlocked ? color : Colors.white24,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ach['title'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unlocked ? Colors.white : Colors.white38,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ach['desc'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unlocked ? Colors.white70 : Colors.white24,
                            fontSize: 10,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ach['progressStr'] as String,
                          style: TextStyle(
                            color: unlocked ? color : Colors.white24,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
