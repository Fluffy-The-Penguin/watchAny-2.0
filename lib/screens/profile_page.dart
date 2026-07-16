import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../state/anilist_auth_state.dart';
import '../state/library_state.dart';
import '../state/navigation_state.dart';

class ProfilePage extends StatefulWidget {
  final NavigationState navigationState;
  const ProfilePage({super.key, required this.navigationState});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _anilistTokenController = TextEditingController();
  bool _isConnectingAnilist = false;
  String? _anilistError;
  bool _isImportingAnilist = false;
  String? _importSuccessMessage;

  @override
  void initState() {
    super.initState();
    _anilistTokenController.addListener(_onTokenChanged);
  }

  void _onTokenChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _anilistTokenController.removeListener(_onTokenChanged);
    _anilistTokenController.dispose();
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
          radius: 11.0,
          backgroundColor: const Color(0xFF3DB4F2),
          child: Text(
            stepNumber,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
            ),
          ),
        ),
        const SizedBox(width: 16.0),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12.0,
                  height: 1.4,
                  fontFamily: 'Outfit',
                ),
              ),
              if (child != null) child,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoggedOutView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          const Row(
            children: [
              Icon(Icons.sync, color: Color(0xFF3DB4F2), size: 24.0),
              SizedBox(width: 12.0),
              Text(
                'Link AniList Account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24.0),
          _buildStepRow(
            stepNumber: '1',
            title: 'Authorize watchAny',
            description: 'Authorize the application on AniList to access your profile and list data.',
            child: Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_browser, color: Colors.white, size: 18.0),
                  label: const Text(
                    'Open AniList Authorization',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  onPressed: _launchAniListUrl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3DB4F2),
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20.0),
          _buildStepRow(
            stepNumber: '2',
            title: 'Copy the PIN/Token',
            description: 'Copy the long access token string displayed in your browser window.',
          ),
          const SizedBox(height: 20.0),
          _buildStepRow(
            stepNumber: '3',
            title: 'Paste and Connect',
            description: 'Paste your token below and click Connect to link your account.',
            child: Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _anilistTokenController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                    decoration: InputDecoration(
                      hintText: 'Paste access token here...',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13.0),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.03),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                      prefixIcon: const Icon(Icons.key, color: Colors.white30, size: 18.0),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste, color: Color(0xFF3DB4F2), size: 18.0),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            _anilistTokenController.text = data!.text!.trim();
                          }
                        },
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.0),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.0),
                        borderSide: const BorderSide(color: Color(0xFF3DB4F2), width: 1.0),
                      ),
                    ),
                  ),
                  if (_anilistError != null) ...[
                    const SizedBox(height: 12.0),
                    Text(
                      _anilistError!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.0, fontWeight: FontWeight.w500),
                    ),
                  ],
                  const SizedBox(height: 16.0),
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
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
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
    ),
  );
}

  Widget _buildLoggedInView(AnilistAuthState authState, bool isLargeScreen) {
    final daysWatched = (authState.minutesWatched / 1440).toStringAsFixed(1);
    
    // Local watchAny items stats
    final localAnimeCount = LibraryState().items.where((e) => e.mode == 'anime').length;
    final localMangaCount = LibraryState().items.where((e) => e.mode == 'manga').length;

    final String syncModeLabel = widget.navigationState.currentMode == AppMode.manga ? 'Manga' : 'Anime';
    final String typeStr = widget.navigationState.currentMode == AppMode.manga ? 'MANGA' : 'ANIME';

    // 1. Profile Card
    final Widget profileCard = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Banner Image
              if (authState.bannerUrl != null)
                Image.network(
                  authState.bannerUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                )
              else
                Container(
                  height: 140,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2E0854), Color(0xFF140534)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              // Gradient Overlay
              Container(
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.7)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Tooltip(
                  message: 'Disconnect Account',
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: const Icon(Icons.logout, size: 16.0, color: Colors.white),
                      onPressed: () async {
                        await authState.logout();
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -28,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.all(3.0),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0C0C0C),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 34.0,
                    backgroundImage: authState.avatarUrl != null ? NetworkImage(authState.avatarUrl!) : null,
                    backgroundColor: Colors.white10,
                    child: authState.avatarUrl == null ? const Icon(Icons.person, color: Colors.white54, size: 30) : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 38.0),
          Padding(
            padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authState.username ?? 'Viewer',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 6.0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20.0),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 12.0),
                      SizedBox(width: 6.0),
                      Text(
                        'Connected to AniList',
                        style: TextStyle(color: Colors.green, fontSize: 11.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // 2. Anime Stats Card
    final Widget animeStatsCard = Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFF3DB4F2).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.video_library, color: Color(0xFF3DB4F2), size: 16),
              SizedBox(width: 8),
              Text(
                'AniList Anime Statistics',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildStatGridItem('Total Anime', '${authState.animeCount}'),
          const SizedBox(height: 12),
          _buildStatGridItem('Episodes Watched', '${authState.episodesWatched}'),
          const SizedBox(height: 12),
          _buildStatGridItem('Days Watched', '$daysWatched d'),
        ],
      ),
    );

    // 3. Manga Stats Card
    final Widget mangaStatsCard = Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.book, color: Color(0xFFA855F7), size: 16),
              SizedBox(width: 8),
              Text(
                'AniList Manga Statistics',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildStatGridItem('Total Manga', '${authState.mangaCount}'),
          const SizedBox(height: 12),
          _buildStatGridItem('Chapters Read', '${authState.chaptersRead}'),
          const SizedBox(height: 12),
          _buildStatGridItem('Volumes Read', '${authState.volumesRead}'),
        ],
      ),
    );

    // 4. Local Stats Card
    final Widget localStatsCard = Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart, color: Color(0xFFF59E0B), size: 18),
              SizedBox(width: 8),
              Text(
                'Local watchAny Statistics',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20.0),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('Local Anime', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit')),
                    const SizedBox(height: 6),
                    Text(
                      '$localAnimeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white10),
              Expanded(
                child: Column(
                  children: [
                    const Text('Local Manga', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit')),
                    const SizedBox(height: 6),
                    Text(
                      '$localMangaCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white10),
              Expanded(
                child: Column(
                  children: [
                    const Text('Total Library', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit')),
                    const SizedBox(height: 6),
                    Text(
                      '${localAnimeCount + localMangaCount}',
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // 5. Auto-sync settings Card
    final Widget syncSettingsCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sync, color: Colors.white70, size: 20.0),
          ),
          const SizedBox(width: 14.0),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Sync Progress',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                SizedBox(height: 4.0),
                Text(
                  'Automatically update AniList when you change progress or status.',
                  style: TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
                ),
              ],
            ),
          ),
          Switch(
            value: authState.isAutoSyncEnabled,
            activeColor: const Color(0xFF3DB4F2),
            activeTrackColor: const Color(0xFF3DB4F2).withValues(alpha: 0.3),
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.white10,
            onChanged: (val) async {
              await authState.setAutoSync(val);
            },
          ),
        ],
      ),
    );

    // 6. Cloud list import Card
    final Widget importCard = Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cloud Sync (Import $syncModeLabel list)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 6.0),
              Text(
                'Fetch your saved $syncModeLabel lists from AniList and merge them into watchAny. Existing items will only be updated if AniList progress is more advanced.',
                style: const TextStyle(color: Colors.white38, fontSize: 11.0, height: 1.4, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 20.0),
              if (_isImportingAnilist) ...[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 16.0,
                      width: 16.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0, valueColor: AlwaysStoppedAnimation(Color(0xFF3DB4F2))),
                    ),
                    SizedBox(width: 12.0),
                    Text(
                      'Importing list entries...',
                      style: TextStyle(color: Color(0xFF3DB4F2), fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                    ),
                  ],
                ),
              ] else ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_download, size: 16.0),
                  label: Text('Sync $syncModeLabel list'),
                  onPressed: () async {
                    setState(() {
                      _isImportingAnilist = true;
                      _importSuccessMessage = null;
                    });
                    final count = await LibraryState().importFromAnilist(typeStr, authState.accessToken!);
                    if (mounted) {
                      setState(() {
                        _isImportingAnilist = false;
                        _importSuccessMessage = count > 0
                            ? 'Sync completed! Added/updated $count items in your library.'
                            : 'Sync completed! Your library is fully synced and up-to-date.';
                      });
                      Future.delayed(const Duration(seconds: 5), () {
                        if (mounted) {
                          setState(() {
                            _importSuccessMessage = null;
                          });
                        }
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3DB4F2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  ),
                ),
              ],
              if (_importSuccessMessage != null) ...[
                const SizedBox(height: 12.0),
                Text(
                  _importSuccessMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
              ],
            ],
          ),
        );

    return isLargeScreen
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column (Profile, Settings, Sync)
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    profileCard,
                    const SizedBox(height: 20.0),
                    syncSettingsCard,
                    const SizedBox(height: 20.0),
                    importCard,
                  ],
                ),
              ),
              const SizedBox(width: 24.0),
              // Right Column (Stats)
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    animeStatsCard,
                    const SizedBox(height: 20.0),
                    mangaStatsCard,
                    const SizedBox(height: 20.0),
                    localStatsCard,
                  ],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              profileCard,
              const SizedBox(height: 20.0),
              animeStatsCard,
              const SizedBox(height: 20.0),
              mangaStatsCard,
              const SizedBox(height: 20.0),
              localStatsCard,
              const SizedBox(height: 20.0),
              syncSettingsCard,
              const SizedBox(height: 20.0),
              importCard,
            ],
          );
  }

  Widget _buildStatGridItem(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Outfit'),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AnilistAuthState(),
      builder: (context, _) {
        final authState = AnilistAuthState();
        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isLargeScreen = screenWidth > 900;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth > 1200 ? 64.0 : 24.0,
                vertical: 32.0,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'User Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    const Text(
                      'Check your AniList stats and manage your cloud backup integration.',
                      style: TextStyle(color: Colors.white54, fontSize: 13.0, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 32.0),
                    if (!authState.isLoggedIn)
                      _buildLoggedOutView()
                    else
                      _buildLoggedInView(authState, isLargeScreen),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
