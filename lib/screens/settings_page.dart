import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/extension_service.dart';
import '../services/stremio_addon_service.dart';
import '../state/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/suwayomi_manager.dart';
import '../services/suwayomi_service.dart';
import '../services/update_service.dart';
import '../state/navigation_state.dart';
import '../services/notification_service.dart';
import '../services/cache_service.dart';
import '../services/download_service.dart';
import 'package:file_picker/file_picker.dart';

enum SettingsCategory {
  general,
  player,
  subtitles,
  downloads,
  extensions,
  addons,
  manga,
  about,
}

class SettingsPage extends StatefulWidget {
  final AppMode mode;
  final SettingsCategory? initialCategory;
  const SettingsPage({super.key, required this.mode, this.initialCategory});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ExtensionService _extensionService = ExtensionService();
  final TextEditingController _repoUrlController = TextEditingController();
  final TextEditingController _repoNameController = TextEditingController();
  final TextEditingController _stremioUrlController = TextEditingController();
  final TextEditingController _mangaRepoUrlController = TextEditingController();
  final TextEditingController _mangaPortController = TextEditingController();
  final TextEditingController _mangaHostController = TextEditingController();
  final TextEditingController _torrServerUrlController = TextEditingController();
  
  late SettingsCategory _activeCategory;
  bool _isLoading = false;
  bool _isInstallingAddon = false;
  
  // Track testing status for extensions by ID: 'idle', 'testing', 'success', 'error'
  final Map<String, String> _testStatus = {};
  final Map<String, String> _testErrors = {};
  
  // Track syncing status for repositories by URL
  final Map<String, bool> _repoSyncing = {};
  List<String> _mangaRepos = [];

  int _downloadsFolderSize = 0;
  int _cacheFolderSize = 0;
  bool _isScanningSize = false;

  Future<void> _updateStorageSizes() async {
    if (mounted) {
      setState(() {
        _isScanningSize = true;
      });
    }
    final dSize = await DownloadService().getDownloadsDirectorySize();
    final cSize = await CacheService().getCacheSize();
    if (mounted) {
      setState(() {
        _downloadsFolderSize = dSize;
        _cacheFolderSize = cSize;
        _isScanningSize = false;
      });
    }
  }

  List<SettingsCategory> _getAvailableCategories() {
    switch (widget.mode) {
      case AppMode.anime:
        return [
          SettingsCategory.general,
          SettingsCategory.player,
          SettingsCategory.subtitles,
          SettingsCategory.downloads,
          SettingsCategory.extensions,
          SettingsCategory.about,
        ];
      case AppMode.movies:
        return [
          SettingsCategory.general,
          SettingsCategory.player,
          SettingsCategory.subtitles,
          SettingsCategory.downloads,
          SettingsCategory.addons,
          SettingsCategory.about,
        ];
      case AppMode.manga:
        return [
          SettingsCategory.general,
          SettingsCategory.downloads,
          SettingsCategory.manga,
          SettingsCategory.about,
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory ?? SettingsCategory.general;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _extensionService.init();
    await StremioAddonService().init();

    // Load Manga Settings
    final prefs = await SharedPreferences.getInstance();
    _mangaRepos = prefs.getStringList('manga_repos') ?? <String>[];
    _mangaPortController.text = (prefs.getInt('manga_server_port') ?? 4567).toString();
    _mangaHostController.text = prefs.getString('manga_server_host') ?? '127.0.0.1';
    _torrServerUrlController.text = AppSettings().torrServerUrl;
    await _updateStorageSizes();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _repoUrlController.dispose();
    _repoNameController.dispose();
    _stremioUrlController.dispose();
    _mangaRepoUrlController.dispose();
    _mangaPortController.dispose();
    _mangaHostController.dispose();
    _torrServerUrlController.dispose();
    super.dispose();
  }

  Future<void> _addRepo() async {
    final url = _repoUrlController.text.trim();
    final name = _repoNameController.text.trim();
    if (url.isEmpty) {
      NotificationService().show(context, 'Please enter a repository URL.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _extensionService.addRepo(url, name);
      _repoUrlController.clear();
      _repoNameController.clear();
      if (mounted) {
        NotificationService().show(context, 'Repository added and synced successfully.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Failed to add repository: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncRepo(String url) async {
    setState(() => _repoSyncing[url] = true);
    try {
      await _extensionService.syncRepo(url);
      if (mounted) {
        NotificationService().show(context, 'Repository synced successfully.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Sync failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _repoSyncing[url] = false);
      }
    }
  }

  Future<void> _testExtension(Extension ext) async {
    setState(() {
      _testStatus[ext.id] = 'testing';
      _testErrors.remove(ext.id);
    });

    try {
      final success = await _extensionService.testExtension(ext);
      if (mounted) {
        setState(() {
          _testStatus[ext.id] = success ? 'success' : 'error';
          if (!success) {
            _testErrors[ext.id] = 'Extension test returned failure.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testStatus[ext.id] = 'error';
          _testErrors[ext.id] = e.toString();
        });
      }
    }
  }

  Widget _buildSidebar() {
    final available = _getAvailableCategories();
    final categoryData = {
      SettingsCategory.extensions: {'title': 'Extensions', 'icon': Icons.extension},
      SettingsCategory.addons: {'title': 'Movies/TV Addons', 'icon': Icons.movie_filter},
      SettingsCategory.general: {'title': 'General', 'icon': Icons.settings_applications},
      SettingsCategory.player: {'title': 'Player', 'icon': Icons.play_circle_outline},
      SettingsCategory.subtitles: {'title': 'Subtitles', 'icon': Icons.subtitles},
      SettingsCategory.downloads: {'title': 'Downloads & Storage', 'icon': Icons.storage},
      SettingsCategory.manga: {'title': 'Manga Settings', 'icon': Icons.book},
      SettingsCategory.about: {'title': 'About', 'icon': Icons.info_outline},
    };

    return Container(
      width: 200,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white10, width: 1.0),
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 8.0),
        itemCount: available.length,
        itemBuilder: (context, index) {
          final cat = available[index];
          final isSelected = _activeCategory == cat;
          final data = categoryData[cat]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                selected: isSelected,
                selectedTileColor: Colors.white.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                leading: Icon(
                  data['icon'] as IconData,
                  color: isSelected ? Colors.white : Colors.white54,
                  size: 20,
                ),
                title: Text(
                  data['title'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontFamily: 'Outfit',
                  ),
                ),
                onTap: () {
                  setState(() {
                    _activeCategory = cat;
                  });
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRepoSection(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Extension Repositories',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        const SizedBox(height: 8.0),
        const Text(
          'Add custom repositories containing scraping extensions. By default, standard repositories are pre-loaded.',
          style: TextStyle(color: Colors.white54, fontSize: 13.0),
        ),
        const SizedBox(height: 16.0),
        
        // Add Repo Fields
        isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _repoNameController,
                    style: const TextStyle(color: Colors.white, fontSize: 14.0),
                    decoration: InputDecoration(
                      labelText: 'Repo Name (Optional)',
                      labelStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.03),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.white38),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  TextField(
                    controller: _repoUrlController,
                    style: const TextStyle(color: Colors.white, fontSize: 14.0),
                    decoration: InputDecoration(
                      labelText: 'Repository JSON URL',
                      labelStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.03),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.white38),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, color: Colors.black, size: 18),
                    label: const Text('Add Repo', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    onPressed: _isLoading ? null : _addRepo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _repoNameController,
                      style: const TextStyle(color: Colors.white, fontSize: 14.0),
                      decoration: InputDecoration(
                        labelText: 'Repo Name (Optional)',
                        labelStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: const BorderSide(color: Colors.white38),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _repoUrlController,
                      style: const TextStyle(color: Colors.white, fontSize: 14.0),
                      decoration: InputDecoration(
                        labelText: 'Repository JSON URL',
                        labelStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: const BorderSide(color: Colors.white38),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, color: Colors.black, size: 18),
                    label: const Text('Add Repo', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    onPressed: _isLoading ? null : _addRepo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                  ),
                ],
              ),
        
        const SizedBox(height: 20.0),
        
        // Repositories List
        ListenableBuilder(
          listenable: _extensionService,
          builder: (context, _) {
            final repos = _extensionService.repos;
            if (repos.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No repositories added.', style: TextStyle(color: Colors.white38)),
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: repos.length,
              itemBuilder: (context, index) {
                final repo = repos[index];
                final isSyncing = _repoSyncing[repo.url] ?? false;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 8.0),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.source, color: Colors.white38, size: 22.0),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              repo.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.0),
                            ),
                            const SizedBox(height: 2.0),
                            Text(
                              repo.url,
                              style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      
                      // Sync Button
                      IconButton(
                        icon: isSyncing 
                            ? const SizedBox(width: 18.0, height: 18.0, child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white70))
                            : const Icon(Icons.sync, color: Colors.white54, size: 18.0),
                        onPressed: isSyncing ? null : () => _syncRepo(repo.url),
                        tooltip: 'Sync Repository',
                      ),
                      
                      // Delete Button (Disable default repos deletion optionally, but let's allow it)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18.0),
                        onPressed: () => _extensionService.removeRepo(repo.url),
                        tooltip: 'Remove Repository',
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionButtons(Extension ext, String status, String? error, {bool isMobile = false}) {
    final testWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == 'testing')
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white54),
          )
        else if (status == 'success')
          const Icon(Icons.check_circle, color: Colors.green, size: 18)
        else if (status == 'error')
          Tooltip(
            message: error ?? 'Test failed',
            child: const Icon(Icons.error, color: Colors.redAccent, size: 18),
          ),
        const SizedBox(width: 8.0),
        OutlinedButton.icon(
          icon: const Icon(Icons.play_circle_outline, size: 13.0),
          label: const Text('Test', style: TextStyle(fontSize: 11.0)),
          onPressed: ext.isEnabled && status != 'testing' ? () => _testExtension(ext) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );

    final toggleWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isMobile) ...[
          Text(
            ext.isEnabled ? 'Enabled' : 'Disabled',
            style: TextStyle(
              color: ext.isEnabled ? Colors.white70 : Colors.white30,
              fontSize: 12.0,
            ),
          ),
          const SizedBox(width: 8.0),
        ],
        Transform.scale(
          scale: isMobile ? 0.8 : 0.9,
          child: Switch(
            value: ext.isEnabled,
            activeColor: Colors.white,
            activeTrackColor: Colors.white24,
            inactiveThumbColor: Colors.white30,
            inactiveTrackColor: Colors.black26,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (value) {
              _extensionService.toggleExtension(ext.id, value);
              setState(() {
                _testStatus.remove(ext.id);
                _testErrors.remove(ext.id);
              });
            },
          ),
        ),
      ],
    );

    if (isMobile) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          testWidget,
          const SizedBox(width: 8.0),
          toggleWidget,
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          testWidget,
          const SizedBox(height: 10.0),
          toggleWidget,
        ],
      );
    }
  }

  Widget _buildExtensionsSection(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Installed Extensions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        const SizedBox(height: 16.0),
        
        ListenableBuilder(
          listenable: _extensionService,
          builder: (context, _) {
            final extensions = _extensionService.extensions;
            if (extensions.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32.0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.01),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Center(
                  child: Text(
                    'No extensions loaded. Try syncing your repositories.',
                    style: TextStyle(color: Colors.white38, fontFamily: 'Outfit'),
                  ),
                ),
              );
            }
            
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: extensions.length,
              itemBuilder: (context, index) {
                final ext = extensions[index];
                final status = _testStatus[ext.id] ?? 'idle';
                final error = _testErrors[ext.id];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: ext.isEnabled ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.01),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: ext.isEnabled ? Colors.white10 : Colors.white.withValues(alpha: 0.05),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Extension Icon / Logo
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6.0),
                            child: ext.icon.isNotEmpty
                                ? Image.network(
                                    ext.icon,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    cacheWidth: 88,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      width: 44,
                                      height: 44,
                                      child: const Icon(Icons.extension, color: Colors.white38),
                                    ),
                                  )
                                : Container(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    width: 44,
                                    height: 44,
                                    child: const Icon(Icons.extension, color: Colors.white38),
                                  ),
                          ),
                          const SizedBox(width: 16.0),
                          
                          // Metadata Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ext.name,
                                        style: TextStyle(
                                          color: ext.isEnabled ? Colors.white : Colors.white38,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15.0,
                                          fontFamily: 'Outfit',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8.0),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(4.0),
                                      ),
                                      child: Text(
                                        'v${ext.version}',
                                        style: const TextStyle(color: Colors.white60, fontSize: 10.0),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  'ID: ${ext.id} • Type: ${ext.type.toUpperCase()}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (!isMobile) ...[
                            const SizedBox(width: 16.0),
                            // Action buttons side-by-side for desktop
                            _buildActionButtons(ext, status, error),
                          ],
                        ],
                      ),
                      
                      const SizedBox(height: 12.0),
                      
                      // Badges & Mobile Actions Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Badges (Expanded so they wrap if needed)
                          Expanded(
                            child: Wrap(
                              spacing: 6.0,
                              runSpacing: 6.0,
                              children: [
                                // Accuracy badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                  decoration: BoxDecoration(
                                    color: ext.accuracy == 'high' 
                                        ? Colors.green.withValues(alpha: 0.15) 
                                        : Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4.0),
                                  ),
                                  child: Text(
                                    'ACCURACY: ${ext.accuracy.toUpperCase()}',
                                    style: TextStyle(
                                      color: ext.accuracy == 'high' ? Colors.green[400] : Colors.amber[400],
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                
                                // Language Badge
                                ...ext.languages.map((lang) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4.0),
                                  ),
                                  child: Text(
                                    lang.toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.blue[400],
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )),
                              ],
                            ),
                          ),
                          
                          if (isMobile) ...[
                            const SizedBox(width: 8.0),
                            // Compact actions for mobile
                            _buildActionButtons(ext, status, error, isMobile: true),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildGeneralSection() {
    return ListenableBuilder(
      listenable: AppSettings(),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'General',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 6.0),
            const Text(
              'App-wide behavior and interface preferences.',
              style: TextStyle(color: Colors.white38, fontSize: 13.0),
            ),
            const SizedBox(height: 24.0),

            // ── Smooth Scroll ──
            _SettingsTile(
              icon: Icons.touch_app_outlined,
              title: 'Smooth Scrolling',
              subtitle: 'Animate mouse-wheel scroll with easing instead of instant jumps.',
              trailing: Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: AppSettings().smoothScrollEnabled,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white24,
                  inactiveThumbColor: Colors.white30,
                  inactiveTrackColor: Colors.black26,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => AppSettings().setSmoothScrollEnabled(v),
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // ── Hardware Acceleration ──
            _SettingsTile(
              icon: Icons.speed,
              title: 'Hardware Acceleration',
              subtitle: 'Use GPU for video decoding and rendering to improve performance and reduce CPU usage.',
              trailing: Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: AppSettings().hardwareAccelerationEnabled,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white24,
                  inactiveThumbColor: Colors.white30,
                  inactiveTrackColor: Colors.black26,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => AppSettings().setHardwareAccelerationEnabled(v),
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // ── TorrServer Address ──
            _SettingsTile(
              icon: Icons.dns_outlined,
              title: 'TorrServer Address',
              subtitle: 'IP address and port of the TorrServer instance (default http://127.0.0.1:8090).',
              trailing: SizedBox(
                width: 220,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _torrServerUrlController,
                        style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    IconButton(
                      icon: const Icon(Icons.save, color: Color(0xFFFF9F1C), size: 20),
                      onPressed: _saveTorrServerUrl,
                      tooltip: 'Save address',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // ── Startup Section ──
            _SettingsTile(
              icon: Icons.start,
              title: 'Default Startup Section',
              subtitle: 'Select which section of the app opens automatically when launching.',
              trailing: DropdownButton<String>(
                value: AppSettings().startupModeStr,
                dropdownColor: const Color(0xFF16161a),
                style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14.0),
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(8.0),
                items: const [
                  DropdownMenuItem(value: 'anime', child: Text('Anime')),
                  DropdownMenuItem(value: 'manga', child: Text('Manga')),
                  DropdownMenuItem(value: 'movies', child: Text('Movies & Webseries')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    AppSettings().setStartupModeStr(val);
                  }
                },
              ),
            ),
            const SizedBox(height: 16.0),

            // ── Startup Page ──
            _SettingsTile(
              icon: Icons.web_asset_outlined,
              title: 'Default Startup Page',
              subtitle: 'Select which page of the section loads first on launch.',
              trailing: DropdownButton<String>(
                value: AppSettings().startupPageStr,
                dropdownColor: const Color(0xFF16161a),
                style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14.0),
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(8.0),
                items: [
                  const DropdownMenuItem(value: 'home', child: Text('Home')),
                  const DropdownMenuItem(value: 'search', child: Text('Search')),
                  const DropdownMenuItem(value: 'library', child: Text('Library')),
                  if (AppSettings().startupModeStr == 'anime')
                    const DropdownMenuItem(value: 'schedule', child: Text('Schedule')),
                  const DropdownMenuItem(value: 'downloads', child: Text('Downloads')),
                  const DropdownMenuItem(value: 'settings', child: Text('Settings')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    AppSettings().setStartupPageStr(val);
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayerSection() {
    return ListenableBuilder(
      listenable: AppSettings(),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Player',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 6.0),
            const Text(
              'Configure video playback engine and hardware settings.',
              style: TextStyle(color: Colors.white38, fontSize: 13.0),
            ),
            const SizedBox(height: 24.0),

            // ── Video Quality Enhancement ──
            _SettingsTile(
              icon: Icons.auto_awesome,
              title: 'Hardware-Accelerated Video Enhancement',
              subtitle: 'Uses native GPU shader pipelines to apply real-time debanding, sharpening, high-quality scaling, and color enhancement.',
              trailing: Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: AppSettings().videoEnhancementEnabled,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white24,
                  inactiveThumbColor: Colors.white30,
                  inactiveTrackColor: Colors.black26,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => AppSettings().setVideoEnhancementEnabled(v),
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // ── Custom Enhancement Settings Toggle ──
            _SettingsTile(
              icon: Icons.tune,
              title: 'Custom Enhancement Settings',
              subtitle: 'Fine-tune debanding parameters manually. Only applies if Video Enhancement is active.',
              trailing: Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: AppSettings().customEnhancementEnabled,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white24,
                  inactiveThumbColor: Colors.white30,
                  inactiveTrackColor: Colors.black26,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => AppSettings().setCustomEnhancementEnabled(v),
                ),
              ),
            ),

            if (AppSettings().customEnhancementEnabled) ...[
              const SizedBox(height: 24.0),
              
              // Deband Iterations Slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Deband Iterations', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Higher values improve quality but use more GPU resources.', style: TextStyle(color: Colors.white38, fontSize: 11.5, fontFamily: 'Outfit')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Text('${AppSettings().debandIterations}', style: const TextStyle(color: Color(0xFFFF9F1C), fontSize: 14.0, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: AppSettings().debandIterations.toDouble(),
                      min: 1.0,
                      max: 16.0,
                      divisions: 15,
                      activeColor: const Color(0xFFFF9F1C),
                      inactiveColor: Colors.white10,
                      onChanged: (val) => AppSettings().setDebandIterations(val.toInt()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20.0),

              // Deband Threshold Slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Deband Threshold', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Sensitivity of banding detection. Higher values remove more banding but may blur details.', style: TextStyle(color: Colors.white38, fontSize: 11.5, fontFamily: 'Outfit')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Text('${AppSettings().debandThreshold}', style: const TextStyle(color: Color(0xFFFF9F1C), fontSize: 14.0, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: AppSettings().debandThreshold.toDouble(),
                      min: 0.0,
                      max: 256.0,
                      divisions: 64,
                      activeColor: const Color(0xFFFF9F1C),
                      inactiveColor: Colors.white10,
                      onChanged: (val) => AppSettings().setDebandThreshold(val.toInt()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20.0),

              // Deband Range Slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Deband Range', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Search distance of debanding. Larger values cover wider gradients but increase GPU overhead.', style: TextStyle(color: Colors.white38, fontSize: 11.5, fontFamily: 'Outfit')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Text('${AppSettings().debandRange}', style: const TextStyle(color: Color(0xFFFF9F1C), fontSize: 14.0, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: AppSettings().debandRange.toDouble(),
                      min: 1.0,
                      max: 64.0,
                      divisions: 63,
                      activeColor: const Color(0xFFFF9F1C),
                      inactiveColor: Colors.white10,
                      onChanged: (val) => AppSettings().setDebandRange(val.toInt()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16.0),

              // Brightness Slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Video Brightness', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Adjust video stream brightness level.', style: TextStyle(color: Colors.white38, fontSize: 11.5, fontFamily: 'Outfit')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Text('${AppSettings().colorBrightness}', style: const TextStyle(color: Color(0xFFFF9F1C), fontSize: 14.0, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: AppSettings().colorBrightness.toDouble(),
                      min: -100.0,
                      max: 100.0,
                      divisions: 200,
                      activeColor: const Color(0xFFFF9F1C),
                      inactiveColor: Colors.white10,
                      onChanged: (val) => AppSettings().setColorBrightness(val.toInt()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16.0),

              // Contrast Slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Video Contrast', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Adjust video stream contrast level.', style: TextStyle(color: Colors.white38, fontSize: 11.5, fontFamily: 'Outfit')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Text('${AppSettings().colorContrast}', style: const TextStyle(color: Color(0xFFFF9F1C), fontSize: 14.0, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: AppSettings().colorContrast.toDouble(),
                      min: -100.0,
                      max: 100.0,
                      divisions: 200,
                      activeColor: const Color(0xFFFF9F1C),
                      inactiveColor: Colors.white10,
                      onChanged: (val) => AppSettings().setColorContrast(val.toInt()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16.0),

              // Saturation Slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Video Saturation', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Adjust video stream color saturation level.', style: TextStyle(color: Colors.white38, fontSize: 11.5, fontFamily: 'Outfit')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Text('${AppSettings().colorSaturation}', style: const TextStyle(color: Color(0xFFFF9F1C), fontSize: 14.0, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: AppSettings().colorSaturation.toDouble(),
                      min: -100.0,
                      max: 100.0,
                      divisions: 200,
                      activeColor: const Color(0xFFFF9F1C),
                      inactiveColor: Colors.white10,
                      onChanged: (val) => AppSettings().setColorSaturation(val.toInt()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24.0),

              // Reset to defaults button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6.0),
                        side: const BorderSide(color: Colors.white10),
                      ),
                    ),
                    icon: const Icon(Icons.refresh, size: 16.0),
                    label: const Text('Reset custom settings', style: TextStyle(fontFamily: 'Outfit', fontSize: 13.0)),
                    onPressed: () async {
                      await AppSettings().resetCustomEnhancementToDefault();
                    },
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDownloadsSection(bool isMobile) {
    return ListenableBuilder(
      listenable: AppSettings(),
      builder: (context, _) {
        final settings = AppSettings();
        
        final double downloadsLimitBytes = settings.downloadsLimitGB * 1024 * 1024 * 1024;
        final double downloadsPercent = (_downloadsFolderSize / downloadsLimitBytes).clamp(0.0, 1.0);
        final String downloadsSizeLabel = "${(_downloadsFolderSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB used of ${settings.downloadsLimitGB.toStringAsFixed(0)} GB";

        final double cacheLimitBytes = settings.cacheLimitGB * 1024 * 1024 * 1024;
        final double cachePercent = (_cacheFolderSize / cacheLimitBytes).clamp(0.0, 1.0);
        final String cacheSizeLabel = "${(_cacheFolderSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB used of ${settings.cacheLimitGB.toStringAsFixed(0)} GB";

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Downloads & Storage',
              style: TextStyle(color: Colors.white, fontSize: 20.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
            ),
            const SizedBox(height: 6.0),
            const Text(
              'Configure directories, storage caps, and automatic resource cleanups.',
              style: TextStyle(color: Colors.white38, fontSize: 13.0),
            ),
            const SizedBox(height: 24.0),

            // ── Auto-Manage Storage ──
            _SettingsTile(
              icon: Icons.auto_delete_outlined,
              title: 'Auto-Manage Storage',
              subtitle: 'Automatically delete oldest completed downloads and prune cache when limits are reached.',
              trailing: Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: settings.autoManageStorage,
                  activeColor: const Color(0xFFFF9F1C),
                  activeTrackColor: const Color(0xFFFF9F1C).withValues(alpha: 0.2),
                  inactiveThumbColor: Colors.white30,
                  inactiveTrackColor: Colors.black26,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => settings.setAutoManageStorage(v),
                ),
              ),
            ),
            const SizedBox(height: 24.0),
            const Divider(color: Colors.white10, height: 1.0),
            const SizedBox(height: 24.0),

            // ── Downloads Storage Header ──
            const Row(
              children: [
                Icon(Icons.download_for_offline, color: Color(0xFFFF9F1C), size: 20),
                SizedBox(width: 8.0),
                Text(
                  'Downloads Storage',
                  style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
              ],
            ),
            const SizedBox(height: 16.0),

            // Downloads Path
            FutureBuilder<String>(
              future: Future.value(settings.downloadPath.isNotEmpty ? settings.downloadPath : "Default Downloads Folder"),
              builder: (context, snapshot) {
                return _SettingsTile(
                  icon: Icons.folder_open_outlined,
                  title: 'Downloads Folder',
                  subtitle: snapshot.data ?? 'Resolving path...',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (settings.downloadPath.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            await settings.setDownloadPath("");
                            await _updateStorageSizes();
                          },
                          child: const Text('Reset', style: TextStyle(color: Colors.redAccent, fontSize: 13.0)),
                        ),
                      const SizedBox(width: 8.0),
                      IconButton(
                        icon: const Icon(Icons.drive_file_move_outlined, color: Colors.white70),
                        onPressed: () async {
                          final path = await FilePicker.getDirectoryPath();
                          if (path != null) {
                            await settings.setDownloadPath(path);
                            await _updateStorageSizes();
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16.0),

            // Downloads Limit GB
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Downloads Storage Limit', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit')),
                    Text('${settings.downloadsLimitGB.toStringAsFixed(0)} GB', style: const TextStyle(color: Color(0xFFFF9F1C), fontSize: 14.0, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: settings.downloadsLimitGB,
                  min: 1.0,
                  max: 100.0,
                  divisions: 99,
                  activeColor: const Color(0xFFFF9F1C),
                  inactiveColor: Colors.white10,
                  onChanged: (val) => settings.setDownloadsLimitGB(val),
                ),
              ],
            ),
            const SizedBox(height: 16.0),

            // Downloads Size Bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Storage Usage', style: TextStyle(color: Colors.white38, fontSize: 12.0)),
                    if (_isScanningSize)
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(Colors.white54)))
                    else
                      Text(downloadsSizeLabel, style: const TextStyle(color: Colors.white54, fontSize: 12.0)),
                  ],
                ),
                const SizedBox(height: 8.0),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: Container(
                    height: 8.0,
                    width: double.infinity,
                    color: Colors.white10,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: downloadsPercent,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF9F1C), Color(0xFFFFBF00)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24.0),
            const Divider(color: Colors.white10, height: 1.0),
            const SizedBox(height: 24.0),

            // ── Cache Storage Header ──
            const Row(
              children: [
                Icon(Icons.cached, color: Color(0xFFFF9F1C), size: 20),
                SizedBox(width: 8.0),
                Text(
                  'Temporary Cache Storage',
                  style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
              ],
            ),
            const SizedBox(height: 16.0),

            // Cache Path
            FutureBuilder<String>(
              future: CacheService().getEffectiveCachePath(),
              builder: (context, snapshot) {
                return _SettingsTile(
                  icon: Icons.folder_zip_outlined,
                  title: 'Cache Folder',
                  subtitle: snapshot.data ?? 'Resolving path...',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (settings.cachePath.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            await settings.setCachePath("");
                            await _updateStorageSizes();
                          },
                          child: const Text('Reset', style: TextStyle(color: Colors.redAccent, fontSize: 13.0)),
                        ),
                      const SizedBox(width: 8.0),
                      IconButton(
                        icon: const Icon(Icons.drive_file_move_outlined, color: Colors.white70),
                        onPressed: () async {
                          final path = await FilePicker.getDirectoryPath();
                          if (path != null) {
                            await settings.setCachePath(path);
                            await _updateStorageSizes();
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16.0),

            // Cache Limit GB
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cache Storage Limit', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit')),
                    Text('${settings.cacheLimitGB.toStringAsFixed(0)} GB', style: const TextStyle(color: Color(0xFFFF9F1C), fontSize: 14.0, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: settings.cacheLimitGB,
                  min: 1.0,
                  max: 50.0,
                  divisions: 49,
                  activeColor: const Color(0xFFFF9F1C),
                  inactiveColor: Colors.white10,
                  onChanged: (val) => settings.setCacheLimitGB(val),
                ),
              ],
            ),
            const SizedBox(height: 16.0),

            // Cache Size Bar & Clear Button
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cache Usage', style: TextStyle(color: Colors.white38, fontSize: 12.0)),
                    Text(cacheSizeLabel, style: const TextStyle(color: Colors.white54, fontSize: 12.0)),
                  ],
                ),
                const SizedBox(height: 8.0),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: Container(
                    height: 8.0,
                    width: double.infinity,
                    color: Colors.white10,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: cachePercent,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFE91E63), Color(0xFFFF4081)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16.0),
                Align(
                  alignment: Alignment.centerRight,
                  child: ListenableBuilder(
                    listenable: CacheService(),
                    builder: (context, _) {
                      final isClearing = CacheService().isCleaning;
                      return ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        ),
                        onPressed: isClearing
                            ? null
                            : () async {
                                await CacheService().clearCache();
                                await _updateStorageSizes();
                              },
                        icon: isClearing
                            ? const SizedBox(
                                width: 14.0,
                                height: 14.0,
                                child: CircularProgressIndicator(strokeWidth: 2.0, valueColor: AlwaysStoppedAnimation(Colors.white)),
                              )
                            : const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: Text(
                          isClearing ? 'Clearing...' : 'Clear Cache Folder',
                          style: const TextStyle(fontFamily: 'Outfit', fontSize: 12.0, fontWeight: FontWeight.w600),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildResponsiveRow({
    required bool isMobile,
    required Widget child1,
    required Widget child2,
    double spacing = 16.0,
  }) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child1,
          SizedBox(height: spacing),
          child2,
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child1),
          SizedBox(width: spacing),
          Expanded(child: child2),
        ],
      );
    }
  }

  void _applySubtitlePreset(String name) {
    final settings = AppSettings();
    if (name == 'Default') {
      settings.setSubtitlesTextColor(0xFFFFFFFF);
      settings.setSubtitlesBgEnabled(false);
      settings.setSubtitlesShadowEnabled(true);
      settings.setSubtitlesShadowColor(0xFF000000);
      settings.setSubtitlesShadowOpacity(0.8);
      settings.setSubtitlesShadowBlurRadius(2.0);
      settings.setSubtitlesShadowOffset(1.5);
    } else if (name == 'Netflix') {
      settings.setSubtitlesTextColor(0xFFFFFFFF);
      settings.setSubtitlesBgEnabled(true);
      settings.setSubtitlesBgColor(0xFF000000);
      settings.setSubtitlesBgOpacity(0.6);
      settings.setSubtitlesShadowEnabled(false);
    } else if (name == 'YouTube') {
      settings.setSubtitlesTextColor(0xFFFFFF00); // Yellow
      settings.setSubtitlesBgEnabled(true);
      settings.setSubtitlesBgColor(0xFF000000);
      settings.setSubtitlesBgOpacity(0.75);
      settings.setSubtitlesShadowEnabled(false);
    } else if (name == 'Anime Outlined') {
      settings.setSubtitlesTextColor(0xFFFFFF00); // Yellow
      settings.setSubtitlesBgEnabled(false);
      settings.setSubtitlesShadowEnabled(true);
      settings.setSubtitlesShadowColor(0xFF000000);
      settings.setSubtitlesShadowOpacity(0.95);
      settings.setSubtitlesShadowBlurRadius(3.0);
      settings.setSubtitlesShadowOffset(2.0);
    } else if (name == 'Captions') {
      settings.setSubtitlesTextColor(0xFF000000); // Black
      settings.setSubtitlesBgEnabled(true);
      settings.setSubtitlesBgColor(0xFFFFFFFF);
      settings.setSubtitlesBgOpacity(0.8);
      settings.setSubtitlesShadowEnabled(false);
    } else {
      settings.applyCustomSubtitlePreset(name);
    }
  }

  void _showSavePresetDialog(BuildContext context, AppSettings settings) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0F11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          title: const Text(
            'Save Custom Preset',
            style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
            decoration: InputDecoration(
              hintText: 'Enter preset name...',
              hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Outfit'),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: const BorderSide(color: Colors.amber),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontFamily: 'Outfit')),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  settings.saveCustomSubtitlePreset(name);
                }
                Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              child: const Text('Save', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubtitlesSection(bool isMobile) {
    final settings = AppSettings();

    // Font list options
    final List<String> fontFamilies = [
      'Outfit',
      'Roboto',
      'Inter',
      'Open Sans',
      'Lato',
      'Poppins',
      'Montserrat',
      'Arial',
      'Courier New',
      'Times New Roman',
      'Playfair Display',
      'System',
    ];

    // Colors list
    final List<Map<String, dynamic>> presetColors = [
      {'name': 'White', 'value': 0xFFFFFFFF},
      {'name': 'Yellow', 'value': 0xFFFFFF00},
      {'name': 'Cyan', 'value': 0xFF00FFFF},
      {'name': 'Light Green', 'value': 0xFF00FF00},
      {'name': 'Orange', 'value': 0xFFFF9800},
      {'name': 'Red', 'value': 0xFFE91E63},
      {'name': 'Black', 'value': 0xFF000000},
    ];

    // Dark bg colors
    final List<Map<String, dynamic>> bgColors = [
      {'name': 'Black', 'value': 0xFF000000},
      {'name': 'Dark Blue', 'value': 0xFF0B1D3A},
      {'name': 'Deep Purple', 'value': 0xFF1A0933},
      {'name': 'Dark Red', 'value': 0xFF3D0814},
      {'name': 'White', 'value': 0xFFFFFFFF},
    ];

    final presets = ['Default', 'Netflix', 'YouTube', 'Anime Outlined', 'Captions'];

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final bool bgEnabled = settings.subtitlesBgEnabled;
        final int bgColor = settings.subtitlesBgColor;
        final double bgOpacity = settings.subtitlesBgOpacity;
        final String fontFamily = settings.subtitlesFontFamily;
        final double fontSize = settings.subtitlesFontSize;
        final bool isBold = settings.subtitlesBold;
        final bool isItalic = settings.subtitlesItalic;
        final double offset = settings.subtitlesPositionOffset;
        final double xOffset = settings.subtitlesXOffset;
        final int textColor = settings.subtitlesTextColor;
        final bool shadowEnabled = settings.subtitlesShadowEnabled;
        final int shadowColor = settings.subtitlesShadowColor;
        final double shadowOpacity = settings.subtitlesShadowOpacity;
        final double shadowBlurRadius = settings.subtitlesShadowBlurRadius;
        final double shadowOffset = settings.subtitlesShadowOffset;

        final subtitlePreviewStyle = TextStyle(
          height: 1.4,
          fontSize: (fontSize * 0.95).clamp(10.0, 36.0),
          color: Color(textColor),
          backgroundColor: bgEnabled ? Color(bgColor).withValues(alpha: bgOpacity) : null,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          fontFamily: fontFamily,
          shadows: shadowEnabled
              ? [
                  Shadow(
                    offset: Offset(-shadowOffset, -shadowOffset),
                    color: Color(shadowColor).withValues(alpha: shadowOpacity),
                    blurRadius: shadowBlurRadius,
                  ),
                  Shadow(
                    offset: Offset(shadowOffset, -shadowOffset),
                    color: Color(shadowColor).withValues(alpha: shadowOpacity),
                    blurRadius: shadowBlurRadius,
                  ),
                  Shadow(
                    offset: Offset(shadowOffset, shadowOffset),
                    color: Color(shadowColor).withValues(alpha: shadowOpacity),
                    blurRadius: shadowBlurRadius,
                  ),
                  Shadow(
                    offset: Offset(-shadowOffset, shadowOffset),
                    color: Color(shadowColor).withValues(alpha: shadowOpacity),
                    blurRadius: shadowBlurRadius,
                  ),
                ]
              : null,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subtitles',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => settings.resetSubtitlesToDefault(),
                  icon: const Icon(Icons.refresh, size: 16.0, color: Colors.blueAccent),
                  label: const Text(
                    "Reset to Defaults",
                    style: TextStyle(color: Colors.blueAccent, fontSize: 13.0, fontFamily: 'Outfit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6.0),
            const Text(
              'Detailed customization for player subtitles styling, positioning, and shadows.',
              style: TextStyle(color: Colors.white38, fontSize: 13.0),
            ),
            const SizedBox(height: 16.0),

            // Master Styling Override Switch
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Apply Custom Subtitles Styling',
                        style: TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                      SizedBox(height: 4.0),
                      Text(
                        'Disable to fallback to the video player\'s native subtitle renderer.',
                        style: TextStyle(color: Colors.white38, fontSize: 12.0),
                      ),
                    ],
                  ),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: settings.subtitlesCustomStylesEnabled,
                      activeColor: Colors.white,
                      activeTrackColor: Colors.blueAccent,
                      onChanged: (val) => settings.setSubtitlesCustomStylesEnabled(val),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24.0),

            IgnorePointer(
              ignoring: !settings.subtitlesCustomStylesEnabled,
              child: AnimatedOpacity(
                opacity: settings.subtitlesCustomStylesEnabled ? 1.0 : 0.25,
                duration: const Duration(milliseconds: 250),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Interactive Screen POSITION PANEL ──
                    const Text(
                      'Screen Position & Live Preview',
                      style: TextStyle(color: Colors.white70, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 6.0),
                    const Text(
                      'Drag the subtitles text in any direction (up/down/left/right) inside the panel below to position it.',
                      style: TextStyle(color: Colors.white38, fontSize: 12.0),
                    ),
                    const SizedBox(height: 12.0),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480.0),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final boxWidth = constraints.maxWidth;
                              final boxHeight = constraints.maxHeight;

                              const minY = 10.0;
                              final maxY = boxHeight - 50.0;
                              const minOffset = 10.0;
                              const maxOffset = 500.0;

                              const minOffsetX = -400.0;
                              const maxOffsetX = 400.0;
                              final maxX = boxWidth / 2.0 - 80.0;

                              final double currentBottom = minY + ((offset - minOffset) / (maxOffset - minOffset)) * (maxY - minY);
                              final double currentX = (xOffset / maxOffsetX) * maxX;

                              return GestureDetector(
                                onPanUpdate: (details) {
                                  final double dy = details.delta.dy;
                                  final double dx = details.delta.dx;

                                  final double newOffset = (settings.subtitlesPositionOffset - (dy * (maxOffset - minOffset) / (maxY - minY)))
                                      .clamp(minOffset, maxOffset);
                                  final double newXOffset = (settings.subtitlesXOffset + (dx * maxOffsetX / maxX))
                                      .clamp(minOffsetX, maxOffsetX);

                                  settings.setSubtitlesXOffset(newXOffset, save: false);
                                  settings.setSubtitlesPositionOffset(newOffset, save: false);
                                },
                                onPanEnd: (_) => settings.saveSubtitlesPosition(),
                                onPanCancel: () => settings.saveSubtitlesPosition(),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12.0),
                                      border: Border.all(color: Colors.white10),
                                      gradient: const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Color(0xFF16161A), Color(0xFF0C0C0E)],
                                      ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.bottomCenter,
                                      children: [
                                        // Video mockup guidelines
                                        Center(
                                          child: Icon(
                                            Icons.movie_outlined,
                                            color: Colors.white.withValues(alpha: 0.02),
                                            size: 100,
                                          ),
                                        ),
                                        Positioned(
                                          top: 24.0,
                                          left: 24.0,
                                          child: Container(
                                            width: 100.0,
                                            height: 8.0,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(4.0),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 38.0,
                                          left: 24.0,
                                          child: Container(
                                            width: 60.0,
                                            height: 8.0,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(4.0),
                                            ),
                                          ),
                                        ),

                                        // Center divider lines
                                        Positioned.fill(
                                          child: Align(
                                            alignment: Alignment.center,
                                            child: Container(
                                              height: 0.5,
                                              color: Colors.white.withValues(alpha: 0.04),
                                            ),
                                          ),
                                        ),

                                        // Draggable Subtitle Box
                                        Positioned(
                                          bottom: currentBottom,
                                          left: 24.0 + currentX,
                                          right: 24.0 - currentX,
                                          child: Center(
                                            child: Text(
                                              "Subtitles look like this",
                                              style: subtitlePreviewStyle,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24.0),

                    // ── Presets Profile Selector ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Preset Style Profiles',
                          style: TextStyle(color: Colors.white70, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _showSavePresetDialog(context, settings);
                          },
                          icon: const Icon(Icons.add, size: 16.0, color: Colors.amber),
                          label: const Text(
                            'Save Current',
                            style: TextStyle(color: Colors.amber, fontSize: 12.0, fontFamily: 'Outfit', fontWeight: FontWeight.w600),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                            backgroundColor: Colors.amber.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12.0),
                    Wrap(
                      spacing: 12.0,
                      runSpacing: 12.0,
                      children: presets.map((name) {
                        return OutlinedButton(
                          onPressed: () => _applySubtitlePreset(name),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white10),
                            backgroundColor: Colors.white.withValues(alpha: 0.03),
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                          ),
                        );
                      }).toList(),
                    ),
                    
                    Builder(
                      builder: (context) {
                        final List<String> customPresetNames = settings.customSubtitlePresets.map((p) {
                          try {
                            return jsonDecode(p)['name'] as String;
                          } catch (_) {
                            return '';
                          }
                        }).where((name) => name.isNotEmpty).toList();

                        if (customPresetNames.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20.0),
                            const Text(
                              'Your Custom Presets',
                              style: TextStyle(color: Colors.white54, fontSize: 12.0, fontFamily: 'Outfit', fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10.0),
                            Wrap(
                              spacing: 10.0,
                              runSpacing: 10.0,
                              children: customPresetNames.map((name) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8.0),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.15)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () => _applySubtitlePreset(name),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(8.0),
                                          bottomLeft: Radius.circular(8.0),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(left: 12.0, right: 8.0, top: 8.0, bottom: 8.0),
                                          child: Text(
                                            name,
                                            style: const TextStyle(color: Colors.amber, fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 1.0,
                                        height: 20.0,
                                        color: Colors.amber.withValues(alpha: 0.15),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 14.0, color: Colors.redAccent),
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          settings.deleteCustomSubtitlePreset(name);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24.0),

                    // ── Detailed Customization Controls ──
                    const Divider(color: Colors.white10, height: 1.0),
                    const SizedBox(height: 24.0),

                    // Font options (Responsive row)
                    _buildResponsiveRow(
                      isMobile: isMobile,
                      child1: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Font Family',
                            style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                          ),
                          const SizedBox(height: 8.0),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: fontFamily,
                                dropdownColor: const Color(0xFF0F0F11),
                                isExpanded: true,
                                style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                                items: fontFamilies
                                    .map((font) => DropdownMenuItem(value: font, child: Text(font)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) settings.setSubtitlesFontFamily(val);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      child2: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Font Size',
                                style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                              ),
                              Text(
                                '${fontSize.toInt()} px',
                                style: const TextStyle(color: Colors.blueAccent, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4.0),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.0,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                            ),
                            child: Slider(
                              value: fontSize,
                              min: 10.0,
                              max: 40.0,
                              activeColor: Colors.blueAccent,
                              inactiveColor: Colors.white10,
                              onChanged: (val) => settings.setSubtitlesFontSize(val),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20.0),

                    // Style Toggles and Text Color (Responsive row)
                    _buildResponsiveRow(
                      isMobile: isMobile,
                      child1: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Text Color',
                            style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                          ),
                          const SizedBox(height: 8.0),
                          Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: presetColors.map((colorItem) {
                              final val = colorItem['value'];
                              final isSelected = textColor == val;
                              return InkWell(
                                onTap: () => settings.setSubtitlesTextColor(val),
                                borderRadius: BorderRadius.circular(20.0),
                                child: Container(
                                  width: 28.0,
                                  height: 28.0,
                                  decoration: BoxDecoration(
                                    color: Color(val),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.blueAccent : Colors.white24,
                                      width: isSelected ? 2.0 : 1.0,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Center(
                                          child: Icon(
                                            Icons.check,
                                            color: val == 0xFFFFFFFF ? Colors.black : Colors.white,
                                            size: 14.0,
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      child2: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Weight & Formatting',
                            style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                          ),
                          const SizedBox(height: 8.0),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => settings.setSubtitlesBold(!isBold),
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    decoration: BoxDecoration(
                                      color: isBold ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(8.0),
                                      border: Border.all(color: isBold ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.white10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Bold',
                                        style: TextStyle(
                                          color: isBold ? Colors.white : Colors.white70,
                                          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 12.0,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10.0),
                              Expanded(
                                child: InkWell(
                                  onTap: () => settings.setSubtitlesItalic(!isItalic),
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    decoration: BoxDecoration(
                                      color: isItalic ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(8.0),
                                      border: Border.all(color: isItalic ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.white10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Italic',
                                        style: TextStyle(
                                          color: isItalic ? Colors.white : Colors.white70,
                                          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                                          fontSize: 12.0,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24.0),

                    // ── Background Box Settings ──
                    const Divider(color: Colors.white10, height: 1.0),
                    const SizedBox(height: 20.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enable Subtitles Background',
                              style: TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                            SizedBox(height: 4.0),
                            Text(
                              'Draws a translucent solid container behind the subtitles.',
                              style: TextStyle(color: Colors.white38, fontSize: 12.0),
                            ),
                          ],
                        ),
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: bgEnabled,
                            activeColor: Colors.white,
                            activeTrackColor: Colors.blueAccent,
                            onChanged: (val) => settings.setSubtitlesBgEnabled(val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16.0),
                    AnimatedOpacity(
                      opacity: bgEnabled ? 1.0 : 0.2,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !bgEnabled,
                        child: _buildResponsiveRow(
                          isMobile: isMobile,
                          child1: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Background Color',
                                style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                              ),
                              const SizedBox(height: 8.0),
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 8.0,
                                children: bgColors.map((colorItem) {
                                  final val = colorItem['value'];
                                  final isSelected = bgColor == val;
                                  return InkWell(
                                    onTap: () => settings.setSubtitlesBgColor(val),
                                    borderRadius: BorderRadius.circular(20.0),
                                    child: Container(
                                      width: 28.0,
                                      height: 28.0,
                                      decoration: BoxDecoration(
                                        color: Color(val),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected ? Colors.blueAccent : Colors.white24,
                                          width: isSelected ? 2.0 : 1.0,
                                        ),
                                      ),
                                      child: isSelected
                                          ? Center(
                                              child: Icon(
                                                Icons.check,
                                                color: val == 0xFFFFFFFF ? Colors.black : Colors.white,
                                                size: 14.0,
                                              ),
                                            )
                                          : null,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                          child2: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Background Opacity',
                                    style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                  ),
                                  Text(
                                    '${(bgOpacity * 100).toInt()}%',
                                    style: const TextStyle(color: Colors.blueAccent, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4.0),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.0,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                ),
                                child: Slider(
                                  value: bgOpacity,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: Colors.blueAccent,
                                  inactiveColor: Colors.white10,
                                  onChanged: (val) => settings.setSubtitlesBgOpacity(val),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24.0),

                    // ── Outline / Shadow Settings ──
                    const Divider(color: Colors.white10, height: 1.0),
                    const SizedBox(height: 20.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enable Subtitles Outline (Text Shadow)',
                              style: TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                            SizedBox(height: 4.0),
                            Text(
                              'Renders high-contrast outlines/shadows to ensure readability.',
                              style: TextStyle(color: Colors.white38, fontSize: 12.0),
                            ),
                          ],
                        ),
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: shadowEnabled,
                            activeColor: Colors.white,
                            activeTrackColor: Colors.blueAccent,
                            onChanged: (val) => settings.setSubtitlesShadowEnabled(val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16.0),
                    AnimatedOpacity(
                      opacity: shadowEnabled ? 1.0 : 0.2,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !shadowEnabled,
                        child: Column(
                          children: [
                            // Shadow color & opacity (Responsive row)
                            _buildResponsiveRow(
                              isMobile: isMobile,
                              child1: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Shadow Color',
                                    style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                  ),
                                  const SizedBox(height: 8.0),
                                  Wrap(
                                    spacing: 8.0,
                                    runSpacing: 8.0,
                                    children: bgColors.map((colorItem) {
                                      final val = colorItem['value'];
                                      final isSelected = shadowColor == val;
                                      return InkWell(
                                        onTap: () => settings.setSubtitlesShadowColor(val),
                                        borderRadius: BorderRadius.circular(20.0),
                                        child: Container(
                                          width: 28.0,
                                          height: 28.0,
                                          decoration: BoxDecoration(
                                            color: Color(val),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected ? Colors.blueAccent : Colors.white24,
                                              width: isSelected ? 2.0 : 1.0,
                                            ),
                                          ),
                                          child: isSelected
                                              ? Center(
                                                  child: Icon(
                                                    Icons.check,
                                                    color: val == 0xFFFFFFFF ? Colors.black : Colors.white,
                                                    size: 14.0,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                              child2: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Shadow Opacity',
                                        style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                      ),
                                      Text(
                                        '${(shadowOpacity * 100).toInt()}%',
                                        style: const TextStyle(color: Colors.blueAccent, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4.0),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.0,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                    ),
                                    child: Slider(
                                      value: shadowOpacity,
                                      min: 0.0,
                                      max: 1.0,
                                      activeColor: Colors.blueAccent,
                                      inactiveColor: Colors.white10,
                                      onChanged: (val) => settings.setSubtitlesShadowOpacity(val),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20.0),
                            // Thickness & Blur (Responsive row)
                            _buildResponsiveRow(
                              isMobile: isMobile,
                              child1: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Outline Thickness (Offset)',
                                        style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                      ),
                                      Text(
                                        '${shadowOffset.toStringAsFixed(1)} px',
                                        style: const TextStyle(color: Colors.blueAccent, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4.0),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.0,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                    ),
                                    child: Slider(
                                      value: shadowOffset,
                                      min: 0.5,
                                      max: 5.0,
                                      activeColor: Colors.blueAccent,
                                      inactiveColor: Colors.white10,
                                      onChanged: (val) => settings.setSubtitlesShadowOffset(val),
                                    ),
                                  ),
                                ],
                              ),
                              child2: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Outline Blur Radius',
                                        style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                      ),
                                      Text(
                                        '${shadowBlurRadius.toStringAsFixed(1)} px',
                                        style: const TextStyle(color: Colors.blueAccent, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4.0),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.0,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                    ),
                                    child: Slider(
                                      value: shadowBlurRadius,
                                      min: 0.0,
                                      max: 8.0,
                                      activeColor: Colors.blueAccent,
                                      inactiveColor: Colors.white10,
                                      onChanged: (val) => settings.setSubtitlesShadowBlurRadius(val),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 36.0),
          ],
        );
      },
    );
  }

  Widget _buildDivider() => Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        height: 1.0,
        color: Colors.white10,
      );

  Widget _buildTopCategoryBar() {
    final available = _getAvailableCategories();
    final categoryData = {
      SettingsCategory.extensions: {'title': 'Extensions', 'icon': Icons.extension},
      SettingsCategory.addons: {'title': 'Addons', 'icon': Icons.movie_filter},
      SettingsCategory.general: {'title': 'General', 'icon': Icons.settings_applications},
      SettingsCategory.player: {'title': 'Player', 'icon': Icons.play_circle_outline},
      SettingsCategory.subtitles: {'title': 'Subtitles', 'icon': Icons.subtitles},
      SettingsCategory.downloads: {'title': 'Storage', 'icon': Icons.storage},
      SettingsCategory.manga: {'title': 'Manga', 'icon': Icons.book},
      SettingsCategory.about: {'title': 'About', 'icon': Icons.info_outline},
    };

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white10, width: 1.0),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: List.generate(available.length, (index) {
            final cat = available[index];
            final isSelected = _activeCategory == cat;
            final data = categoryData[cat]!;
            return InkWell(
              onTap: () => setState(() => _activeCategory = cat),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2.0,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      data['icon'] as IconData,
                      color: isSelected ? Colors.white : Colors.white54,
                      size: 18,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      data['title'] as String,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
        ),
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    final Widget contentPane = SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Header
          const Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
            ),
          ),
          const SizedBox(height: 4.0),
          const Text(
            'Configure scrapers, local servers, and global application options.',
            style: TextStyle(color: Colors.white38, fontSize: 14.0),
          ),
          const SizedBox(height: 24.0),
          
          Container(height: 1.0, color: Colors.white10),
          const SizedBox(height: 24.0),
          
          // Display Active category content
          if (_activeCategory == SettingsCategory.extensions) ...[
            _buildRepoSection(isMobile),
            const SizedBox(height: 36.0),
            Container(height: 1.0, color: Colors.white10),
            const SizedBox(height: 24.0),
            _buildExtensionsSection(isMobile),
          ] else if (_activeCategory == SettingsCategory.addons) ...[
            _buildStremioAddonsSection(isMobile),
          ] else if (_activeCategory == SettingsCategory.general) ...[
            _buildGeneralSection(),
          ] else if (_activeCategory == SettingsCategory.player) ...[
            _buildPlayerSection(),
          ] else if (_activeCategory == SettingsCategory.subtitles) ...[
            _buildSubtitlesSection(isMobile),
          ] else if (_activeCategory == SettingsCategory.downloads) ...[
            _buildDownloadsSection(isMobile),
          ] else if (_activeCategory == SettingsCategory.manga) ...[
            _buildMangaSettingsSection(isMobile),
          ] else if (_activeCategory == SettingsCategory.about) ...[
            _buildAboutSection(),
          ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: EdgeInsets.only(top: isMobile ? 0.0 : 50.0), // Room for floating drag handle / custom title bar on desktop
        child: isMobile
            ? Column(
                children: [
                  _buildTopCategoryBar(),
                  Expanded(child: contentPane),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Settings Sidebar
                  _buildSidebar(),
                  
                  // Right Settings Details Pane
                  Expanded(
                    child: contentPane,
                  ),
                ],
              ),
      ),
    );
  }
  Future<void> _installStremioAddon() async {
    final url = _stremioUrlController.text.trim();
    if (url.isEmpty) {
      NotificationService().show(context, 'Please enter a manifest URL.');
      return;
    }

    setState(() {
      _isInstallingAddon = true;
    });

    try {
      await StremioAddonService().installAddon(url);
      _stremioUrlController.clear();
      if (mounted) {
        NotificationService().show(context, 'Stremio Addon installed successfully.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Failed to install addon: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInstallingAddon = false;
        });
      }
    }
  }

  Widget _buildStremioAddonsSection(bool isMobile) {
    return ListenableBuilder(
      listenable: StremioAddonService(),
      builder: (context, _) {
        final addonService = StremioAddonService();
        final addons = addonService.addons;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stremio Addons',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 8.0),
            const Text(
              'Install custom Stremio manifest URLs (e.g. from stremio-addons.net) to stream movies & TV shows.',
              style: TextStyle(color: Colors.white54, fontSize: 13.0),
            ),
            const SizedBox(height: 16.0),

            // URL input and Install button
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _stremioUrlController,
                        style: const TextStyle(color: Colors.white, fontSize: 14.0),
                        decoration: InputDecoration(
                          labelText: 'Stremio Addon Manifest URL',
                          labelStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.03),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: Colors.white10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: Colors.white10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: Colors.white38),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                        ),
                      ),
                      const SizedBox(height: 12.0),
                      ElevatedButton.icon(
                        icon: _isInstallingAddon
                            ? const SizedBox(
                                width: 16.0,
                                height: 16.0,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.0),
                              )
                            : const Icon(Icons.add, color: Colors.black, size: 18),
                        label: const Text('Install Addon', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        onPressed: _isInstallingAddon ? null : _installStremioAddon,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _stremioUrlController,
                          style: const TextStyle(color: Colors.white, fontSize: 14.0),
                          decoration: InputDecoration(
                            labelText: 'Stremio Addon Manifest URL',
                            labelStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.03),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.white10),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.white10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.white38),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      ElevatedButton.icon(
                        icon: _isInstallingAddon
                            ? const SizedBox(
                                width: 16.0,
                                height: 16.0,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.0),
                              )
                            : const Icon(Icons.add, color: Colors.black, size: 18),
                        label: const Text('Install Addon', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        onPressed: _isInstallingAddon ? null : _installStremioAddon,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 24.0),
            Container(height: 1.0, color: Colors.white10),
            const SizedBox(height: 24.0),

            // Installed Addons List
            if (addons.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48.0),
                  child: Text(
                    'No Stremio Addons installed yet.',
                    style: TextStyle(color: Colors.white38, fontSize: 14.0),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: addons.length,
                itemBuilder: (context, index) {
                  final addon = addons[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Addon Icon / Logo
                        Container(
                          width: 48.0,
                          height: 48.0,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6.0),
                            child: addon.icon.isNotEmpty
                                ? Image.network(
                                    addon.icon,
                                    fit: BoxFit.cover,
                                    cacheWidth: 96,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.movie, color: Colors.white38),
                                  )
                                : const Icon(Icons.movie, color: Colors.white38),
                          ),
                        ),
                        const SizedBox(width: 16.0),

                        // Addon Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    addon.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.0,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                  const SizedBox(width: 8.0),
                                  Text(
                                    'v${addon.version}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11.0),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4.0),
                              Text(
                                addon.description.isNotEmpty ? addon.description : 'No description provided.',
                                style: const TextStyle(color: Colors.white70, fontSize: 13.0),
                              ),
                              const SizedBox(height: 8.0),
                              // Chips for resources & types
                              Wrap(
                                spacing: 6.0,
                                runSpacing: 6.0,
                                children: [
                                  for (final type in addon.types)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4.0),
                                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        type,
                                        style: const TextStyle(color: Colors.amber, fontSize: 10.0, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  for (final res in addon.resources)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(4.0),
                                        border: Border.all(color: Colors.white10),
                                      ),
                                      child: Text(
                                        res,
                                        style: const TextStyle(color: Colors.white70, fontSize: 10.0),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16.0),

                        // Switch and Delete
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: addon.isEnabled,
                                activeColor: Colors.white,
                                activeTrackColor: Colors.white24,
                                inactiveThumbColor: Colors.white30,
                                inactiveTrackColor: Colors.black26,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (val) {
                                  addonService.toggleAddon(addon.id, val);
                                },
                              ),
                            ),
                            const SizedBox(height: 8.0),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20.0),
                              onPressed: () {
                                addonService.removeAddon(addon.id);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            const StremioHomepageConfigPanel(),
          ],
        );
      },
    );
  }

  Future<void> _addMangaRepo() async {
    final url = _mangaRepoUrlController.text.trim();
    if (url.isEmpty) {
      NotificationService().show(context, 'Please enter a repository URL.');
      return;
    }
    if (_mangaRepos.contains(url)) {
      NotificationService().show(context, 'Repository already exists.');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _mangaRepos.add(url);
      await prefs.setStringList('manga_repos', _mangaRepos);
      _mangaRepoUrlController.clear();
      
      // Dynamic engine reload
      SuwayomiManager.stop();
      await SuwayomiManager.start();
      
      if (mounted) {
        NotificationService().show(context, 'Manga repository added and engine restarted successfully.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Failed to add repository: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeMangaRepo(String url) async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _mangaRepos.remove(url);
      await prefs.setStringList('manga_repos', _mangaRepos);
      
      // Dynamic engine reload
      SuwayomiManager.stop();
      await SuwayomiManager.start();
      
      if (mounted) {
        NotificationService().show(context, 'Manga repository removed and engine restarted.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Failed to remove repository: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveMangaPort() async {
    final portStr = _mangaPortController.text.trim();
    final port = int.tryParse(portStr);
    if (port == null || port < 1024 || port > 65535) {
      NotificationService().show(context, 'Please enter a valid port number between 1024 and 65535.');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('manga_server_port', port);
      
      // Update dynamic runtime reference
      SuwayomiService.port = port;
      
      // Dynamic engine reload
      SuwayomiManager.stop();
      await SuwayomiManager.start();
      
      if (mounted) {
        NotificationService().show(context, 'Manga server port updated.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Failed to update port: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveMangaHost() async {
    final host = _mangaHostController.text.trim();
    if (host.isEmpty) {
      NotificationService().show(context, 'Please enter a valid IP address or hostname.');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('manga_server_host', host);
      
      // Update dynamic runtime reference
      SuwayomiService.host = host;
      
      // Dynamic engine reload
      SuwayomiManager.stop();
      await SuwayomiManager.start();
      
      if (mounted) {
        NotificationService().show(context, 'Manga server host updated.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Failed to update host: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveTorrServerUrl() async {
    final url = _torrServerUrlController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      NotificationService().show(context, 'Please enter a valid URL starting with http:// or https://.');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      await AppSettings().setTorrServerUrl(url);
      if (mounted) {
        NotificationService().show(context, 'TorrServer URL updated successfully.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Failed to update URL: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildMangaSettingsSection(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Manga Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        const SizedBox(height: 8.0),
        const Text(
          'Configure your Keiyoushi Manga Engine port, custom extension repositories, and lifecycle status.',
          style: TextStyle(color: Colors.white38, fontSize: 13.5, fontFamily: 'Outfit'),
        ),
        const SizedBox(height: 24.0),

        // Host/IP Configuration
        _SettingsTile(
          icon: Icons.computer_outlined,
          title: 'Server IP / Host',
          subtitle: 'IP address of the Keiyoushi Manga Engine instance (default 127.0.0.1).',
          trailing: SizedBox(
            width: 180,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mangaHostController,
                    style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  icon: const Icon(Icons.save, color: Color(0xFFFF9F1C), size: 20),
                  onPressed: _saveMangaHost,
                  tooltip: 'Save host',
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16.0),

        // Port Configuration
        _SettingsTile(
          icon: Icons.lan_outlined,
          title: 'Server Port',
          subtitle: 'Port of the background Keiyoushi Manga Engine instance (default 4567).',
          trailing: SizedBox(
            width: 140,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mangaPortController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  icon: const Icon(Icons.save, color: Color(0xFFFF9F1C), size: 20),
                  onPressed: _saveMangaPort,
                  tooltip: 'Save and restart server',
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24.0),

        // Engine Status control card
        ValueListenableBuilder<String>(
          valueListenable: SuwayomiManager.statusNotifier,
          builder: (context, status, _) {
            final isRunning = status.contains('running');
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Icon(
                    isRunning ? Icons.play_circle : Icons.stop_circle,
                    color: isRunning ? Colors.green : Colors.white38,
                    size: 32,
                  ),
                  const SizedBox(width: 16.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manga Engine Server',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.0, fontFamily: 'Outfit'),
                        ),
                        Text(
                          'Status: $status',
                          style: const TextStyle(color: Colors.white54, fontSize: 12.0, fontFamily: 'Outfit'),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (isRunning) {
                        SuwayomiManager.stop();
                      } else {
                        await SuwayomiManager.start();
                      }
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRunning ? Colors.redAccent : const Color(0xFFFF9F1C),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                    ),
                    child: Text(
                      isRunning ? 'Stop Server' : 'Start Server',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 32.0),
        Container(height: 1.0, color: Colors.white10),
        const SizedBox(height: 24.0),

        // Manga Extension Repositories
        const Text(
          'Manga Extension Repositories',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        const SizedBox(height: 8.0),
        const Text(
          'Configure repositories index URLs (Tachiyomi extensions). Adding a URL will sync new extensions.',
          style: TextStyle(color: Colors.white38, fontSize: 12.5),
        ),
        const SizedBox(height: 16.0),

        // Add repository fields
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _mangaRepoUrlController,
                style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                decoration: InputDecoration(
                  hintText: 'https://example.com/index.min.json',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.03),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: Colors.white10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: Colors.white10)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: Colors.white38)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                ),
              ),
            ),
            const SizedBox(width: 12.0),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, color: Colors.black, size: 16),
              label: const Text('Add', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              onPressed: _isLoading ? null : _addMangaRepo,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9F1C),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16.0),

        // Repos list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _mangaRepos.length,
          itemBuilder: (context, index) {
            final url = _mangaRepos[index];

            return Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.source, color: Colors.white38, size: 18.0),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Text(
                      url,
                      style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18.0),
                    onPressed: () => _removeMangaRepo(url),
                    tooltip: 'Remove Repository',
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    final updateService = UpdateService();
    return ListenableBuilder(
      listenable: updateService,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'About watchAny',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 8.0),
              const Text(
                'Fully self-contained media center bundling streaming extensions, Stremio addon APIs, manga reader engines, and Torrent servers locally.',
                style: TextStyle(color: Colors.white54, fontSize: 13.0),
              ),
              const SizedBox(height: 24.0),
              
              // App Info Card
              Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    // App Logo Mock
                    Container(
                      width: 64.0,
                      height: 64.0,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14.0),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_filled,
                          color: Colors.amber,
                          size: 36.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'watchAny 2.0',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          const SizedBox(height: 4.0),
                          const Text(
                            'Version ${UpdateService.currentVersion}',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12.0,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          const Text(
                            'Bundled TorrServer: Local Binary (v1.3.0)',
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 11.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),

              // Updates Section
              const Text(
                'Application Updates',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 12.0),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!updateService.hasChecked) ...[
                      const Text(
                        'Check for updates to ensure you have the latest features and security updates.',
                        style: TextStyle(color: Colors.white70, fontSize: 13.0),
                      ),
                      const SizedBox(height: 16.0),
                      ElevatedButton.icon(
                        icon: updateService.isChecking
                            ? const SizedBox(
                                width: 14.0,
                                height: 14.0,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.0),
                              )
                            : const Icon(Icons.update, color: Colors.black, size: 16.0),
                        label: const Text('Check for Updates', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        onPressed: updateService.isChecking
                            ? null
                            : () async {
                                final hasUpdate = await updateService.checkForUpdates();
                                if (context.mounted) {
                                  NotificationService().show(
                                    context,
                                    hasUpdate
                                        ? 'A new update (v${updateService.latestUpdate!.version}) is available!'
                                        : 'watchAny is up to date!',
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                        ),
                      ),
                    ] else if (updateService.isChecking) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                        ),
                      ),
                    ] else if (updateService.hasUpdate) ...[
                      Row(
                        children: [
                          const Icon(Icons.info, color: Colors.amber, size: 18.0),
                          const SizedBox(width: 8.0),
                          Text(
                            'Update Available: ${updateService.latestUpdate!.version.startsWith('v') ? '' : 'v'}${updateService.latestUpdate!.version}',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 14.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12.0),
                      const Text(
                        'Changelog:',
                        style: TextStyle(color: Colors.white54, fontSize: 12.0, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6.0),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(6.0),
                        ),
                        child: Text(
                          updateService.latestUpdate!.changelog,
                          style: const TextStyle(color: Colors.white70, fontSize: 12.0, height: 1.5, fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      if (updateService.isDownloading) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Downloading update installer...',
                              style: TextStyle(color: Colors.white70, fontSize: 12.0, fontFamily: 'Outfit'),
                            ),
                            const SizedBox(height: 8.0),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2.0),
                              child: LinearProgressIndicator(
                                value: updateService.downloadProgress,
                                backgroundColor: Colors.white10,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                                minHeight: 6.0,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              '${(updateService.downloadProgress * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
                            ),
                          ],
                        ),
                      ] else ...[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.download, color: Colors.black, size: 16.0),
                          label: const Text('Update Now', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            updateService.startUpdate();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          ),
                        ),
                      ],
                    ] else ...[
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 18.0),
                          const SizedBox(width: 8.0),
                          Text(
                            'Your application is up to date!',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 14.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16.0),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, color: Colors.black, size: 16.0),
                        label: const Text('Check Again', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          await updateService.checkForUpdates();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                        ),
                      ),
                    ],
                    if (updateService.error != null) ...[
                      const SizedBox(height: 12.0),
                      Text(
                        updateService.error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12.0),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StremioHomepageConfigPanel extends StatefulWidget {
  const StremioHomepageConfigPanel({super.key});

  @override
  State<StremioHomepageConfigPanel> createState() => _StremioHomepageConfigPanelState();
}

class _StremioHomepageConfigPanelState extends State<StremioHomepageConfigPanel> {
  List<String> _selectedAddons = [];
  Map<String, List<String>> _selectedCatalogs = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final addons = prefs.getStringList('stremio_homepage_selected_addons') ?? [];
    
    final Map<String, List<String>> catalogs = {};
    for (final addonId in addons) {
      catalogs[addonId] = prefs.getStringList('stremio_homepage_selected_catalogs_$addonId') ?? [];
    }

    setState(() {
      _selectedAddons = addons;
      _selectedCatalogs = catalogs;
      _loading = false;
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('stremio_homepage_selected_addons', _selectedAddons);
    for (final addonId in _selectedCatalogs.keys) {
      await prefs.setStringList(
        'stremio_homepage_selected_catalogs_$addonId',
        _selectedCatalogs[addonId] ?? [],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24.0),
        child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0)),
      );
    }

    final addonService = StremioAddonService();
    final catalogAddons = addonService.addons
        .where((a) => a.isEnabled && a.resources.contains('catalog'))
        .toList();

    if (catalogAddons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32.0),
        const Row(
          children: [
            Icon(Icons.layers_outlined, color: Colors.white70, size: 20.0),
            SizedBox(width: 8.0),
            Text(
              'Homepage Catalogs Setup',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        const Text(
          'Choose up to 5 addons and 5 catalogs per addon to show on your Movies/TV homepage (max 25 railways). If none selected, first 5 enabled addons are shown by default.',
          style: TextStyle(color: Colors.white38, fontSize: 12.0),
        ),
        const SizedBox(height: 16.0),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: catalogAddons.length,
          itemBuilder: (context, index) {
            final addon = catalogAddons[index];
            final bool isSelected = _selectedAddons.contains(addon.id);
            final addonCatalogs = addon.catalogs;

            return Container(
              margin: const EdgeInsets.only(bottom: 12.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.01),
                border: Border.all(color: isSelected ? Colors.amber.withValues(alpha: 0.3) : Colors.white10),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    title: Text(
                      addon.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.0),
                    ),
                    subtitle: Text(
                      '${addonCatalogs.length} catalogs available',
                      style: const TextStyle(color: Colors.white38, fontSize: 11.0),
                    ),
                    activeColor: Colors.amber,
                    checkColor: Colors.black,
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          if (_selectedAddons.length >= 5) {
                            NotificationService().show(context, 'You can select a maximum of 5 addons for the homepage.');
                            return;
                          }
                          _selectedAddons.add(addon.id);
                          _selectedCatalogs[addon.id] = [];
                        } else {
                          _selectedAddons.remove(addon.id);
                          _selectedCatalogs.remove(addon.id);
                        }
                        _saveConfig();
                      });
                    },
                  ),
                  if (isSelected) ...[
                    const Divider(color: Colors.white10, height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Catalogs (max 5):',
                            style: TextStyle(color: Colors.white54, fontSize: 11.0, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8.0),
                          Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: [
                              for (final cat in addonCatalogs) () {
                                final String catId = cat['id'] ?? '';
                                final String catName = cat['name'] ?? catId;
                                final List<String> currentSelected = _selectedCatalogs[addon.id] ?? [];
                                final bool isCatSelected = currentSelected.contains(catId);

                                return FilterChip(
                                  label: Text(
                                    catName,
                                    style: TextStyle(
                                      color: isCatSelected ? Colors.black : Colors.white70,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  selected: isCatSelected,
                                  selectedColor: Colors.amber,
                                  checkmarkColor: Colors.black,
                                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        if (currentSelected.length >= 5) {
                                          NotificationService().show(context, 'You can select a maximum of 5 catalogs per addon.');
                                          return;
                                        }
                                        currentSelected.add(catId);
                                      } else {
                                        currentSelected.remove(catId);
                                      }
                                      _selectedCatalogs[addon.id] = currentSelected;
                                      _saveConfig();
                                    });
                                  },
                                );
                              }(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A standard settings row with an icon, title, subtitle and a trailing widget.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 22.0),
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
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12.0),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16.0),
          trailing,
        ],
      ),
    );
  }
}
