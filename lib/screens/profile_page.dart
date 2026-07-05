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
  void dispose() {
    _anilistTokenController.dispose();
    super.dispose();
  }

  Future<void> _launchAniListUrl() async {
    const url = 'https://anilist.co/api/v2/oauth/authorize?client_id=45095&response_type=token';
    if (Platform.isWindows) {
      try {
        await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
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
          radius: 12.0,
          backgroundColor: const Color(0xFF3DB4F2).withValues(alpha: 0.15),
          child: Text(
            stepNumber,
            style: const TextStyle(
              color: Color(0xFF3DB4F2),
              fontSize: 12.0,
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
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
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
                    onPressed: _isConnectingAnilist
                        ? null
                        : () async {
                            final token = _anilistTokenController.text.trim();
                            if (token.isEmpty) {
                              setState(() {
                                _anilistError = 'Please paste a token first.';
                              });
                              return;
                            }
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
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white10,
                      side: const BorderSide(color: Colors.white10),
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
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
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

  Widget _buildLoggedInView(AnilistAuthState authState) {
    final daysWatched = (authState.minutesWatched / 1440).toStringAsFixed(1);
    
    // Local watchAny items stats
    final localAnimeCount = LibraryState().items.where((e) => e.mode == 'anime').length;
    final localMangaCount = LibraryState().items.where((e) => e.mode == 'manga').length;

    final String syncModeLabel = widget.navigationState.currentMode == AppMode.manga ? 'Manga' : 'Anime';
    final String typeStr = widget.navigationState.currentMode == AppMode.manga ? 'MANGA' : 'ANIME';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner & User Profile Card
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
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
                          colors: [Color(0xFF3B5998), Color(0xFF1DA1F2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  Container(
                    height: 140,
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      radius: 18,
                      child: IconButton(
                        icon: const Icon(Icons.logout, size: 16.0, color: Colors.white70),
                        tooltip: 'Disconnect Account',
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          await authState.logout();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36.0,
                      backgroundImage: authState.avatarUrl != null ? NetworkImage(authState.avatarUrl!) : null,
                      backgroundColor: Colors.white10,
                      child: authState.avatarUrl == null ? const Icon(Icons.person, color: Colors.white54, size: 32) : null,
                    ),
                    const SizedBox(width: 16.0),
                    Expanded(
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
                          const SizedBox(height: 4.0),
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 14.0),
                              SizedBox(width: 6.0),
                              Text(
                                'Connected to AniList',
                                style: TextStyle(color: Colors.green, fontSize: 12.0, fontWeight: FontWeight.w500, fontFamily: 'Outfit'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const Divider(color: Colors.white10, height: 1),
              
              // Statistics Section
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AniList Statistics',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.01),
                              borderRadius: BorderRadius.circular(12.0),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.video_library, color: Color(0xFF3DB4F2), size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      'Anime',
                                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildStatDetailRow('Total Anime', '${authState.animeCount}'),
                                const SizedBox(height: 8),
                                _buildStatDetailRow('Episodes', '${authState.episodesWatched}'),
                                const SizedBox(height: 8),
                                _buildStatDetailRow('Days Watched', '$daysWatched d'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14.0),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.01),
                              borderRadius: BorderRadius.circular(12.0),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.book, color: Colors.purpleAccent, size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      'Manga',
                                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildStatDetailRow('Total Manga', '${authState.mangaCount}'),
                                const SizedBox(height: 8),
                                _buildStatDetailRow('Chapters', '${authState.chaptersRead}'),
                                const SizedBox(height: 8),
                                _buildStatDetailRow('Volumes', '${authState.volumesRead}'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white10, height: 1),

              // Local Library Statistics
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local Library Statistics',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.01),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Local Anime', style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Outfit')),
                                const SizedBox(height: 6),
                                Text('$localAnimeCount', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.white10),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Local Manga', style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Outfit')),
                                const SizedBox(height: 6),
                                Text('$localMangaCount', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.white10),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Total Library', style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Outfit')),
                                const SizedBox(height: 6),
                                Text('${localAnimeCount + localMangaCount}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                              ],
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
        const SizedBox(height: 24.0),

        // Auto-Sync Switch
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
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
                      style: TextStyle(color: Colors.white38, fontSize: 12.0),
                    ),
                  ],
                ),
              ),
              Switch(
                value: authState.isAutoSyncEnabled,
                activeColor: const Color(0xFF3DB4F2),
                onChanged: (val) async {
                  await authState.setAutoSync(val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20.0),

        // List Import Module
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Import $syncModeLabel List',
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
                style: const TextStyle(color: Colors.white38, fontSize: 12.0, height: 1.4),
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
                      'Importing list entries from AniList...',
                      style: TextStyle(color: Color(0xFF3DB4F2), fontSize: 13.0, fontWeight: FontWeight.w500, fontFamily: 'Outfit'),
                    ),
                  ],
                ),
              ] else ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.import_export, size: 18.0),
                  label: Text('Import $syncModeLabel List'),
                  onPressed: () async {
                    setState(() {
                      _isImportingAnilist = true;
                      _importSuccessMessage = null;
                    });
                    final count = await LibraryState().importFromAnilist(typeStr, authState.accessToken!);
                    if (mounted) {
                      setState(() {
                        _isImportingAnilist = false;
                        _importSuccessMessage = 'Import completed! Added/updated $count items in your library.';
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
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white10),
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  ),
                ),
              ],
              if (_importSuccessMessage != null) ...[
                const SizedBox(height: 12.0),
                Text(
                  _importSuccessMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.green, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Outfit'),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
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
        return Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 550),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'User Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    const Text(
                      'Check your AniList stats and manage your cloud backup integration.',
                      style: TextStyle(color: Colors.white54, fontSize: 13.0, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 24.0),
                    if (!authState.isLoggedIn)
                      _buildLoggedOutView()
                    else
                      _buildLoggedInView(authState),
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
