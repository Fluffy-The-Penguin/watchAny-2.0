import 'package:flutter/material.dart';
import '../services/extension_service.dart';
import '../services/stremio_addon_service.dart';
import '../state/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/suwayomi_manager.dart';
import '../services/suwayomi_service.dart';
import '../services/update_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

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
  
  int _activeCategoryIndex = 0; // 0: Extensions, 1: Addons, 2: General
  bool _isLoading = false;
  bool _isInstallingAddon = false;
  
  // Track testing status for extensions by ID: 'idle', 'testing', 'success', 'error'
  final Map<String, String> _testStatus = {};
  final Map<String, String> _testErrors = {};
  
  // Track syncing status for repositories by URL
  final Map<String, bool> _repoSyncing = {};
  List<String> _mangaRepos = [];

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _addRepo() async {
    final url = _repoUrlController.text.trim();
    final name = _repoNameController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a repository URL.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _extensionService.addRepo(url, name);
      _repoUrlController.clear();
      _repoNameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Repository added and synced successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add repository: $e'), backgroundColor: Colors.redAccent),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Repository synced successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.redAccent),
        );
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
    final categories = [
      {'title': 'Extensions', 'icon': Icons.extension},
      {'title': 'Movies/TV Addons', 'icon': Icons.movie_filter},
      {'title': 'General', 'icon': Icons.settings_applications},
      {'title': 'Manga Settings', 'icon': Icons.book},
      {'title': 'About', 'icon': Icons.info_outline},
    ];

    return Container(
      width: 200,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white10, width: 1.0),
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 8.0),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final isSelected = _activeCategoryIndex == index;
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
                  categories[index]['icon'] as IconData,
                  color: isSelected ? Colors.white : Colors.white54,
                  size: 20,
                ),
                title: Text(
                  categories[index]['title'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontFamily: 'Outfit',
                  ),
                ),
                onTap: () {
                  setState(() {
                    _activeCategoryIndex = index;
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

  Widget _buildDivider() => Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        height: 1.0,
        color: Colors.white10,
      );

  Widget _buildTopCategoryBar() {
    final categories = [
      {'title': 'Extensions', 'icon': Icons.extension},
      {'title': 'Addons', 'icon': Icons.movie_filter},
      {'title': 'General', 'icon': Icons.settings_applications},
      {'title': 'Manga', 'icon': Icons.book},
      {'title': 'About', 'icon': Icons.info_outline},
    ];

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white10, width: 1.0),
        ),
      ),
      child: Row(
        children: List.generate(categories.length, (index) {
          final isSelected = _activeCategoryIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeCategoryIndex = index),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
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
                      categories[index]['icon'] as IconData,
                      color: isSelected ? Colors.white : Colors.white54,
                      size: 18,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      categories[index]['title'] as String,
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
            ),
          );
        }),
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
          if (_activeCategoryIndex == 0) ...[
            _buildRepoSection(isMobile),
            const SizedBox(height: 36.0),
            Container(height: 1.0, color: Colors.white10),
            const SizedBox(height: 24.0),
            _buildExtensionsSection(isMobile),
          ] else if (_activeCategoryIndex == 1) ...[
            _buildStremioAddonsSection(isMobile),
          ] else if (_activeCategoryIndex == 2) ...[
            _buildGeneralSection(),
          ] else if (_activeCategoryIndex == 3) ...[
            _buildMangaSettingsSection(isMobile),
          ] else if (_activeCategoryIndex == 4) ...[
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a manifest URL.')),
      );
      return;
    }

    setState(() {
      _isInstallingAddon = true;
    });

    try {
      await StremioAddonService().installAddon(url);
      _stremioUrlController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stremio Addon installed successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to install addon: ${e.toString().replaceAll('Exception: ', '')}')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a repository URL.')),
      );
      return;
    }
    if (_mangaRepos.contains(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Repository already exists.')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manga repository added and engine restarted successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add repository: $e'), backgroundColor: Colors.redAccent),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manga repository removed and engine restarted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove repository: $e'), backgroundColor: Colors.redAccent),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid port number between 1024 and 65535.')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manga server port updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update port: $e'), backgroundColor: Colors.redAccent),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid IP address or hostname.')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manga server host updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update host: $e'), backgroundColor: Colors.redAccent),
        );
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
            final isDefault = url.contains('keiyoushi');

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
                  if (isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: const Text(
                        'DEFAULT',
                        style: TextStyle(color: Colors.white54, fontSize: 8.0, fontWeight: FontWeight.bold),
                      ),
                    )
                  else
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(hasUpdate
                                          ? 'A new update (v${updateService.latestUpdate!.version}) is available!'
                                          : 'watchAny is up to date!'),
                                    ),
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('You can select a maximum of 5 addons for the homepage.'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
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
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('You can select a maximum of 5 catalogs per addon.'),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
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
