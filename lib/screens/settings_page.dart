import 'package:flutter/material.dart';
import '../services/extension_service.dart';
import '../state/app_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ExtensionService _extensionService = ExtensionService();
  final TextEditingController _repoUrlController = TextEditingController();
  final TextEditingController _repoNameController = TextEditingController();
  
  int _activeCategoryIndex = 0; // 0: Extensions, 1: General
  bool _isLoading = false;
  
  // Track testing status for extensions by ID: 'idle', 'testing', 'success', 'error'
  final Map<String, String> _testStatus = {};
  final Map<String, String> _testErrors = {};
  
  // Track syncing status for repositories by URL
  final Map<String, bool> _repoSyncing = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _extensionService.init();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _repoUrlController.dispose();
    _repoNameController.dispose();
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
      {'title': 'General', 'icon': Icons.settings_applications},
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
      {'title': 'General', 'icon': Icons.settings_applications},
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
            _buildGeneralSection(),
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
