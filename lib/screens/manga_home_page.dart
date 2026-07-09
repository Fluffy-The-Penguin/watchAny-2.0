import '../services/notification_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/suwayomi_manager.dart';
import '../services/suwayomi_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';
import '../widgets/smooth_scroll_area.dart';

class MangaHomePage extends StatefulWidget {
  final NavigationState navigationState;

  const MangaHomePage({
    super.key,
    required this.navigationState,
  });

  @override
  State<MangaHomePage> createState() => _MangaHomePageState();
}

class _MangaHomePageState extends State<MangaHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SuwayomiService _suwayomiService = SuwayomiService();
  bool _showDebugLogs = false;

  bool get _isActive =>
      widget.navigationState.currentMode == AppMode.manga &&
      widget.navigationState.currentPage == TabPage.search;
  
  // Extension tab state
  List<dynamic> _extensions = [];
  bool _loadingExtensions = false;
  String _extensionsSearchQuery = "";
  String? _extensionsError;
  
  // Catalog tab state
  List<dynamic> _sources = [];
  String? _selectedSourceId;
  List<dynamic> _catalogManga = [];
  bool _loadingCatalog = false;
  int _currentPage = 1;
  String _catalogSearchQuery = "";
  String? _catalogError;
  final TextEditingController _searchController = TextEditingController();
  bool _engineStarted = false;
  Map<String, List<dynamic>> _globalSearchResults = {};

  SharedPreferences? _prefs;
  String? _selectedExtensionName;

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {});
  }

  String _getCleanName(String name) {
    return name
        .replaceFirst('Tachiyomi: ', '')
        .replaceFirst('Keiyoushi: ', '')
        .trim();
  }

  bool _isLanguageEnabled(String extName, String lang) {
    if (_prefs == null) return true;
    final key = 'manga_ext_lang_${_getCleanName(extName)}_${lang.toLowerCase()}';
    return _prefs!.getBool(key) ?? true;
  }

  Future<void> _setLanguageEnabled(String extName, String lang, bool enabled) async {
    if (_prefs == null) return;
    final key = 'manga_ext_lang_${_getCleanName(extName)}_${lang.toLowerCase()}';
    await _prefs!.setBool(key, enabled);
    if (mounted) setState(() {});
  }

  List<dynamic> _getLanguagesForExtension(String extName) {
    final cleanExt = _getCleanName(extName).toLowerCase();
    final matches = _sources.where((s) {
      final cleanSrc = _getCleanName(s['name']?.toString() ?? '').toLowerCase();
      return cleanSrc == cleanExt;
    }).toList();
    matches.sort((a, b) => (a['lang']?.toString() ?? '').compareTo(b['lang']?.toString() ?? ''));
    return matches;
  }

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    
    widget.navigationState.addListener(_checkAndStartEngine);
    _checkAndStartEngine();
  }

  @override
  void dispose() {
    widget.navigationState.removeListener(_checkAndStartEngine);
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _checkAndStartEngine() {
    if (widget.navigationState.currentMode == AppMode.manga && !_engineStarted) {
      _engineStarted = true;
      SuwayomiManager.start().then((_) {
        if (mounted) {
          _loadExtensions();
          _loadSources();
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            SuwayomiManager.statusNotifier.value = "Error: Failed to start Manga engine: $e";
          });
        }
      });
    }
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 0) {
      _loadSources();
    } else {
      _loadExtensions();
    }
  }

  Future<void> _retryConnection() async {
    if (mounted) {
      setState(() {
        SuwayomiManager.statusNotifier.value = "Checking connection...";
      });
    }
    try {
      await SuwayomiManager.start();
      if (mounted) {
        await _loadExtensions();
        await _loadSources();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          SuwayomiManager.statusNotifier.value = "Error: Failed to start Manga engine: $e";
        });
      }
    }
  }

  // Load Extensions from Suwayomi
  Future<void> _loadExtensions() async {
    if (!await SuwayomiManager.isSuwayomiRunning(SuwayomiService.port)) {
      SuwayomiManager.statusNotifier.value = "Error: Could not connect to Suwayomi server at http://${SuwayomiService.host}:${SuwayomiService.port}";
      return;
    }
    SuwayomiManager.statusNotifier.value = "Manga engine running";
    if (mounted) {
      setState(() {
        _loadingExtensions = true;
        _extensionsError = null;
      });
    }
    try {
      await _suwayomiService.seedExternalRepositories();
      final list = await _suwayomiService.getExtensions();
      if (mounted) {
        setState(() {
          _extensions = list;
          _loadingExtensions = false;
        });

        if (list.isEmpty) {
          Future.microtask(() async {
            if (!mounted) return;
            String extraInfo = '';
            try {
              final reposUrl = Uri.parse('http://${SuwayomiService.host}:${SuwayomiService.port}/api/repos');
              final reposResp = await http.get(reposUrl).timeout(const Duration(seconds: 5));
              if (reposResp.statusCode == 200) {
                final data = jsonDecode(reposResp.body);
                final reposList = data['data'] as List?;
                if (reposList != null && reposList.isNotEmpty) {
                  final firstRepo = reposList.first;
                  final lastError = firstRepo['lastError'];
                  if (lastError != null) {
                    extraInfo = ' | Repo Error: $lastError';
                  } else {
                    extraInfo = ' | Repo Exts: ${firstRepo['extensionCount']}';
                  }
                } else {
                  extraInfo = ' | No repos registered on server';
                }
              }
            } catch (e) {
              extraInfo = ' | Failed to fetch repos: $e';
            }

            if (mounted && _isActive) {
              NotificationService().show(context, 'Manga: Fetched ${list.length} extensions$extraInfo');
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extensionsError = e.toString().replaceFirst('Exception: ', '');
          _loadingExtensions = false;
        });
      }
    }
  }

  // Load Sources from Suwayomi
  Future<void> _loadSources() async {
    if (!await SuwayomiManager.isSuwayomiRunning(SuwayomiService.port)) {
      SuwayomiManager.statusNotifier.value = "Error: Could not connect to Suwayomi server at http://${SuwayomiService.host}:${SuwayomiService.port}";
      return;
    }
    SuwayomiManager.statusNotifier.value = "Manga engine running";
    if (mounted) {
      setState(() {
        _catalogError = null;
      });
    }
    try {
      await _suwayomiService.seedExternalRepositories();
      final list = await _suwayomiService.getSources();
      if (mounted) {
        setState(() {
          _sources = list;
          
          final List<String> distinctExtensionNames = _sources
              .map((s) => _getCleanName(s['name']?.toString() ?? ''))
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList();
          distinctExtensionNames.sort();

          if (_selectedExtensionName == null) {
            _selectedExtensionName = "Global";
          }

          if (_selectedExtensionName != "Global" && _selectedExtensionName != null) {
            final extSources = _sources.where((s) => _getCleanName(s['name']?.toString() ?? '') == _selectedExtensionName).toList();
            final enabled = extSources.where((s) => _isLanguageEnabled(_selectedExtensionName!, s['lang']?.toString() ?? 'en')).toList();
            final target = enabled.isNotEmpty ? enabled : extSources;
            if (target.isNotEmpty) {
              _selectedSourceId = target.first['id']?.toString();
            }
          }

          if (_selectedSourceId == null && _sources.isNotEmpty) {
            _selectedSourceId = _sources.first['id']?.toString();
          }

          _loadCatalog();
        });

        if (list.isEmpty) {
          Future.microtask(() async {
            if (!mounted) return;
            String extraInfo = '';
            try {
              final installedUrl = Uri.parse('http://${SuwayomiService.host}:${SuwayomiService.port}/api/installed');
              final installedResp = await http.get(installedUrl).timeout(const Duration(seconds: 5));
              if (installedResp.statusCode == 200) {
                final data = jsonDecode(installedResp.body);
                final installedList = data['data'] as List?;
                if (installedList != null && installedList.isNotEmpty) {
                  final firstInst = installedList.first;
                  final errors = firstInst['sourceLoadErrors'] as List?;
                  if (errors != null && errors.isNotEmpty) {
                    final firstError = errors.first;
                    extraInfo = ' | Ext Load Error: ${firstError['className']}: ${firstError['errorType']} - ${firstError['message']}';
                  } else {
                    extraInfo = ' | Installed Ext: ${firstInst['name']} (no errors, sources count: ${firstInst['sources']?.length})';
                  }
                } else {
                  extraInfo = ' | No extensions installed on server';
                }
              }
            } catch (e) {
              extraInfo = ' | Failed to fetch installed: $e';
            }

            if (mounted && _isActive) {
              NotificationService().show(context, 'Manga: Fetched ${list.length} catalog sources$extraInfo');
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _catalogError = 'Failed to load catalog sources: ${e.toString().replaceFirst('Exception: ', '')}';
        });
      }
    }
  }

  // Load Catalog items for selected source
  Future<void> _loadCatalog({bool resetPage = false}) async {
    if (_selectedExtensionName == "Global") {
      await _performGlobalSearch();
      return;
    }

    if (_selectedSourceId == null) return;
    if (mounted) {
      setState(() {
        _loadingCatalog = true;
        _catalogError = null;
        if (resetPage) {
          _currentPage = 1;
        }
      });
    }

    try {
      final manga = await _suwayomiService.fetchSourceManga(
        sourceId: _selectedSourceId!,
        page: _currentPage,
        query: _catalogSearchQuery,
      );
      if (mounted) {
        setState(() {
          _catalogManga = manga;
          _loadingCatalog = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _catalogError = e.toString().replaceFirst('Exception: ', '');
          _loadingCatalog = false;
        });
      }
    }
  }

  Future<void> _performGlobalSearch() async {
    final query = _catalogSearchQuery;
    if (query.isEmpty) {
      setState(() {
        _globalSearchResults = {};
        _loadingCatalog = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loadingCatalog = true;
        _catalogError = null;
        _globalSearchResults = {};
      });
    }

    final preferredSources = _getPreferredSourceIds();
    int activeSearches = preferredSources.length;

    if (activeSearches == 0) {
      setState(() {
        _loadingCatalog = false;
      });
      return;
    }

    for (final entry in preferredSources.entries) {
      final extName = entry.key;
      final sourceId = entry.value;

      _suwayomiService.fetchSourceManga(
        sourceId: sourceId,
        page: 1,
        query: query,
      ).then((list) {
        if (!mounted || _catalogSearchQuery != query) return;
        setState(() {
          _globalSearchResults[extName] = list;
        });
      }).catchError((e) {
        if (!mounted || _catalogSearchQuery != query) return;
        setState(() {
          _globalSearchResults[extName] = [];
        });
      }).whenComplete(() {
        if (!mounted || _catalogSearchQuery != query) return;
        activeSearches--;
        if (activeSearches == 0) {
          setState(() {
            _loadingCatalog = false;
          });
        }
      });
    }
  }

  Map<String, String> _getPreferredSourceIds() {
    final Map<String, String> preferred = {};
    for (final source in _sources) {
      final name = _getCleanName(source['name']?.toString() ?? '');
      if (name.isEmpty) continue;
      final id = source['id']?.toString();
      if (id == null) continue;
      final lang = source['lang']?.toString() ?? 'en';
      
      // If we haven't stored a source for this extension, or if this one is EN/en, prefer it
      if (!preferred.containsKey(name) || lang.toLowerCase() == 'en') {
        preferred[name] = id;
      }
    }
    return preferred;
  }

  Future<void> _toggleExtensionInstall(Map<String, dynamic> ext) async {
    final String pkgName = ext['pkgName'];
    final bool isInstalled = ext['isInstalled'] ?? false;
    
    if (mounted) setState(() => _loadingExtensions = true);
    
    try {
      if (isInstalled) {
        await _suwayomiService.uninstallExtension(pkgName);
      } else {
        await _suwayomiService.installExtension(pkgName);
      }
      await _loadExtensions();
      await _loadSources();
    } catch (_) {
      if (mounted) setState(() => _loadingExtensions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<String>(
        valueListenable: SuwayomiManager.statusNotifier,
        builder: (context, status, child) {
          if (status.contains("Downloading") || status.contains("Starting") || status.contains("Checking")) {
            return _buildLoadingScreen(status);
          } else if (status.contains("failed") || status.contains("Error")) {
            return _buildErrorScreen(status);
          }
          
          return _buildMainContent();
        },
      ),
    );
  }

  Widget _buildLoadingScreen(String status) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_book, color: Color(0xFFFF9F1C), size: 64.0),
            const SizedBox(height: 32.0),
            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 16.0),
            if (SuwayomiManager.isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: LinearProgressIndicator(
                  value: SuwayomiManager.downloadProgress,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                  minHeight: 6.0,
                ),
              ),
              const SizedBox(height: 8.0),
              Text(
                '${(SuwayomiManager.downloadProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white30, fontSize: 12.0, fontFamily: 'Outfit'),
              ),
            ] else
              const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String error) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48.0),
              const SizedBox(height: 16.0),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14.0,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 24.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _retryConnection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9F1C),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                    ),
                    child: const Text('Retry Startup', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16.0),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showDebugLogs = !_showDebugLogs;
                      });
                    },
                    icon: Icon(
                      _showDebugLogs ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white60,
                    ),
                    label: Text(
                      _showDebugLogs ? 'Hide Logs' : 'Show Logs',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
                ],
              ),
              if (_showDebugLogs) ...[
                const SizedBox(height: 24.0),
                Container(
                  constraints: const BoxConstraints(maxHeight: 250, maxWidth: 600),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    border: Border.all(color: Colors.white10),
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  padding: const EdgeInsets.all(12.0),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: SuwayomiManager.processLogs.length,
                    itemBuilder: (context, index) {
                      final logLine = SuwayomiManager.processLogs[index];
                      Color logColor = Colors.white70;
                      if (logLine.contains('[ERROR]') || logLine.contains('[STDERR]')) {
                        logColor = Colors.redAccent;
                      } else if (logLine.contains('[STDOUT]')) {
                        logColor = Colors.greenAccent;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(
                          logLine,
                          style: TextStyle(
                            color: logColor,
                            fontSize: 11.0,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return Column(
      children: [
        // Tab Bar / Top Navigation
        Container(
          padding: EdgeInsets.only(
            left: isMobile ? 16.0 : 70.0,
            right: 16.0,
            top: isMobile ? 8.0 : 40.0,
            bottom: 4.0,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10, width: 1.0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  indicatorColor: const Color(0xFFFF9F1C),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 15.0),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.normal, fontSize: 15.0),
                  tabs: const [
                    Tab(text: 'Catalog'),
                    Tab(text: 'Extensions'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCatalogTab(),
              _buildExtensionsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogTab() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = (screenWidth / 160).floor().clamp(2, 8);

    final List<String> distinctExtensionNames = _sources
        .map((s) => _getCleanName(s['name']?.toString() ?? ''))
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    distinctExtensionNames.sort();
    distinctExtensionNames.insert(0, "Global");

    if (_selectedExtensionName == null && _selectedSourceId != null && _sources.isNotEmpty) {
      final selectedSrc = _sources.firstWhere(
        (s) => s['id']?.toString() == _selectedSourceId,
        orElse: () => null,
      );
      if (selectedSrc != null) {
        _selectedExtensionName = _getCleanName(selectedSrc['name']?.toString() ?? '');
      }
    }
    if (_selectedExtensionName == null) {
      _selectedExtensionName = "Global";
    }
    if (_selectedExtensionName != null && !distinctExtensionNames.contains(_selectedExtensionName)) {
      _selectedExtensionName = "Global";
    }

    final currentExtSources = _sources.where((s) {
      return _getCleanName(s['name']?.toString() ?? '') == _selectedExtensionName;
    }).toList();

    final enabledSources = currentExtSources.where((s) {
      final lang = s['lang']?.toString() ?? 'en';
      return _isLanguageEnabled(_selectedExtensionName ?? '', lang);
    }).toList();

    final displayedSources = enabledSources.isNotEmpty ? enabledSources : currentExtSources;

    // Ensure selection is valid
    final hasSelectedId = displayedSources.any((s) => s['id']?.toString() == _selectedSourceId);
    if (!hasSelectedId && displayedSources.isNotEmpty) {
      _selectedSourceId = displayedSources.first['id']?.toString();
    }

    return CustomScrollView(
      slivers: [
        // â”€â”€ Header: dropdowns + search â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sources dropdown & Search Input Row
                Row(
                  children: [
                    if (_sources.isNotEmpty) ...[
                      // 1. Extension Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F11),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedExtensionName,
                          dropdownColor: const Color(0xFF0F0F11),
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                          items: distinctExtensionNames.map<DropdownMenuItem<String>>((extName) {
                            return DropdownMenuItem<String>(
                              value: extName,
                              child: Text(extName),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedExtensionName = value;
                                if (value == "Global") {
                                  _selectedSourceId = null;
                                  _currentPage = 1;
                                  _catalogManga = [];
                                  _globalSearchResults = {};
                                } else {
                                  final extSources = _sources.where((s) => _getCleanName(s['name']?.toString() ?? '') == value).toList();
                                  final enabled = extSources.where((s) => _isLanguageEnabled(value, s['lang']?.toString() ?? 'en')).toList();
                                  final target = enabled.isNotEmpty ? enabled : extSources;
                                  if (target.isNotEmpty) {
                                    _selectedSourceId = target.first['id']?.toString();
                                  }
                                  _currentPage = 1;
                                  _catalogManga = [];
                                }
                              });
                              _loadCatalog();
                            }
                          },
                        ),
                      ),

                      if (_selectedExtensionName != "Global") ...[
                        const SizedBox(width: 8.0),

                        // 2. Language Dropdown
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F0F11),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: DropdownButton<String>(
                            value: _selectedSourceId,
                            dropdownColor: const Color(0xFF0F0F11),
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                            items: displayedSources.map<DropdownMenuItem<String>>((source) {
                              return DropdownMenuItem<String>(
                                value: source['id']?.toString(),
                                child: Text((source['lang']?.toString() ?? 'en').toUpperCase()),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedSourceId = value;
                                  _currentPage = 1;
                                  _catalogManga = [];
                                });
                                _loadCatalog();
                              }
                            },
                          ),
                        ),
                      ],
                    ] else
                      const Text('No sources installed', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit')),

                    const SizedBox(width: 12.0),

                    Expanded(
                      child: Container(
                        height: 42.0,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F11),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14.0),
                          decoration: const InputDecoration(
                            hintText: 'Search manga...',
                            hintStyle: TextStyle(color: Colors.white30),
                            prefixIcon: Icon(Icons.search, color: Colors.white30, size: 18),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10.0),
                          ),
                          onSubmitted: (value) {
                            setState(() {
                              _catalogSearchQuery = value.trim();
                              _currentPage = 1;
                            });
                            _loadCatalog();
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24.0),

                const Text(
                  'Browse Catalog',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 16.0),
              ],
            ),
          ),
        ),

        // â”€â”€ Catalog content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if (_catalogError != null)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 36.0),
                    const SizedBox(height: 12.0),
                    const Text(
                      'Failed to load catalog',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.0, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      _catalogError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 12.0, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 16.0),
                    ElevatedButton(
                      onPressed: () {
                        if (_selectedSourceId == null) {
                          _loadSources();
                        } else {
                          _loadCatalog();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9F1C),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                      ),
                      child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_selectedExtensionName == "Global" && _catalogSearchQuery.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 64.0),
                child: Text(
                  'Search manga across all installed extensions.',
                  style: TextStyle(color: Colors.white30, fontFamily: 'Outfit'),
                ),
              ),
            ),
          )
        else if (_loadingCatalog && _globalSearchResults.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 64.0),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                ),
              ),
            ),
          )
        else if (!_loadingCatalog && _selectedExtensionName == "Global" && _globalSearchResults.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 64.0),
                child: Text(
                  'No manga found. Try searching or check extensions.',
                  style: TextStyle(color: Colors.white30, fontFamily: 'Outfit'),
                ),
              ),
            ),
          )
        else if (_selectedExtensionName == "Global" && _globalSearchResults.isNotEmpty) ...[
          if (_loadingCatalog)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14.0,
                      height: 14.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                      ),
                    ),
                    SizedBox(width: 12.0),
                    Text(
                      'Searching remaining extensions...',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12.0,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ...() {
            final List<String> sortedExtNames = _globalSearchResults.keys.toList();
            sortedExtNames.sort((a, b) {
              final listA = _globalSearchResults[a] ?? [];
              final listB = _globalSearchResults[b] ?? [];
              if (listA.isNotEmpty && listB.isEmpty) return -1;
              if (listA.isEmpty && listB.isNotEmpty) return 1;
              return a.compareTo(b);
            });

            return sortedExtNames.map((extName) {
              final list = _globalSearchResults[extName] ?? [];
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 28.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            extName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          if (list.isNotEmpty)
                            Text(
                              '${list.length} results',
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 12.0,
                                fontFamily: 'Outfit',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12.0),
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Text(
                            'No results found',
                            style: TextStyle(
                              color: Colors.white24,
                              fontStyle: FontStyle.italic,
                              fontSize: 13.0,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 200.0,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final manga = list[index];
                              final String title = manga['title']?.toString() ?? 'Unknown Title';
                              final String? coverUrl = manga['thumbnailUrl']?.toString();
                              final int mangaId = int.tryParse(manga['id']?.toString() ?? '') ?? 0;
                              final bool inLibrary = LibraryState().getItem(mangaId, 'manga') != null;

                              final cardWidget = Container(
                                width: 110.0,
                                margin: const EdgeInsets.only(right: 14.0),
                                child: GestureDetector(
                                  onTap: () {
                                    if (mangaId != 0) {
                                      widget.navigationState.selectManga(mangaId.toString());
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(6.0),
                                          child: coverUrl != null && coverUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: coverUrl,
                                                  fit: BoxFit.cover,
                                                  width: double.infinity,
                                                  memCacheWidth: 200,
                                                  placeholder: (_, __) => Container(color: const Color(0xFF0F0F11)),
                                                  errorWidget: (_, __, ___) => Container(
                                                    color: const Color(0xFF0F0F11),
                                                    child: const Center(
                                                      child: Icon(Icons.book, color: Colors.white12, size: 24.0),
                                                    ),
                                                  ),
                                                )
                                              : Container(
                                                  color: const Color(0xFF0F0F11),
                                                  child: const Center(
                                                    child: Icon(Icons.book, color: Colors.white12, size: 24.0),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 6.0),
                                      Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              if (inLibrary) {
                                return Opacity(opacity: 0.75, child: cardWidget);
                              }
                              return cardWidget;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList();
          }()
        ]
        else if (_selectedExtensionName != "Global" && _catalogManga.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 64.0),
                child: Text(
                  'No manga found. Try searching or check extension.',
                  style: TextStyle(color: Colors.white30, fontFamily: 'Outfit'),
                ),
              ),
            ),
          )
        else if (_selectedExtensionName != "Global") ...[
          // ── Manga grid — only visible items rendered ──────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16.0,
                mainAxisSpacing: 20.0,
                childAspectRatio: 0.65,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final manga = _catalogManga[index];
                  final String title = manga['title']?.toString() ?? 'Unknown Title';
                  final String? coverUrl = manga['thumbnailUrl']?.toString();
                  final int mangaId = int.tryParse(manga['id']?.toString() ?? '') ?? 0;
                  final bool inLibrary = LibraryState().getItem(mangaId, 'manga') != null;

                  final cardWidget = RepaintBoundary(
                    child: GestureDetector(
                      onTap: () {
                        if (mangaId != 0) {
                          widget.navigationState.selectManga(mangaId.toString());
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: coverUrl != null && coverUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      memCacheWidth: 300,
                                      fadeInDuration: const Duration(milliseconds: 150),
                                      placeholder: (_, __) => Container(color: const Color(0xFF0F0F11)),
                                      errorWidget: (_, __, ___) => Container(
                                        color: const Color(0xFF0F0F11),
                                        child: const Center(
                                          child: Icon(Icons.book, color: Colors.white12, size: 40.0),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFF0F0F11),
                                      child: const Center(
                                        child: Icon(Icons.book, color: Colors.white12, size: 40.0),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (inLibrary) {
                    return Opacity(opacity: 0.75, child: cardWidget);
                  }
                  return cardWidget;
                },
                childCount: _catalogManga.length,
              ),
            ),
          ),

          // ── Pagination controls ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 32.0, 24.0, 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _currentPage > 1
                        ? () {
                            setState(() => _currentPage--);
                            _loadCatalog();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                    ),
                    child: const Text('Previous'),
                  ),
                  const SizedBox(width: 16.0),
                  Text(
                    'Page $_currentPage',
                    style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16.0),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentPage++);
                      _loadCatalog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                    ),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }





  Widget _buildExtensionTile(Map<String, dynamic> ext) {
    final String name = ext['name']?.toString().replaceFirst('Tachiyomi: ', '') ?? 'Unknown Source';
    final String lang = ext['lang']?.toString().toUpperCase() ?? 'ALL';
    final bool isInstalled = ext['isInstalled'] ?? false;
    final bool isNsfw = (ext['nsfw'] ?? 0) == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F11),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: Container(
            width: 40.0,
            height: 40.0,
            color: Colors.white.withValues(alpha: 0.05),
            child: CachedNetworkImage(
              imageUrl: 'http://${SuwayomiService.host}:${SuwayomiService.port}/api/installed/icon?pkgName=${ext['pkgName']}',
              width: 40.0,
              height: 40.0,
              fit: BoxFit.cover,
              placeholder: (context, url) => const Center(
                child: Icon(Icons.extension_outlined, color: Colors.white24, size: 20.0),
              ),
              errorWidget: (context, url, error) => const Center(
                child: Icon(Icons.extension_outlined, color: Colors.white24, size: 20.0),
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
            ),
            const SizedBox(width: 8.0),
            if (isNsfw)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: const Text(
                  '18+',
                  style: TextStyle(color: Colors.redAccent, fontSize: 8.0, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'Language: $lang',
          style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isInstalled) ...[
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Color(0xFFFF9F1C)),
                tooltip: 'Configure languages',
                onPressed: () => _showConfigureLanguagesDialog(ext),
              ),
              const SizedBox(width: 8.0),
            ],
            ElevatedButton(
              onPressed: () => _toggleExtensionInstall(ext),
              style: ElevatedButton.styleFrom(
                backgroundColor: isInstalled ? Colors.redAccent : const Color(0xFFFF9F1C),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
              ),
              child: Text(
                isInstalled ? 'Uninstall' : 'Install',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfigureLanguagesDialog(Map<String, dynamic> ext) {
    final extName = ext['name']?.toString() ?? '';
    final cleanName = _getCleanName(extName);
    final matches = _getLanguagesForExtension(extName);
    
    final displaySources = matches.isNotEmpty 
        ? matches 
        : [{
            'id': ext['pkgName'],
            'name': extName,
            'lang': ext['lang'] ?? 'en',
          }];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF121214),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
                side: const BorderSide(color: Colors.white10),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cleanName,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 6.0),
                  const Text(
                    'Enable or disable languages for this extension.',
                    style: TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: displaySources.length,
                  itemBuilder: (context, index) {
                    final src = displaySources[index];
                    final String lang = src['lang']?.toString() ?? 'en';
                    final bool isEnabled = _isLanguageEnabled(extName, lang);

                    String getLanguageName(String code) {
                      switch (code.toLowerCase()) {
                        case 'all': return 'All Languages';
                        case 'en': return 'English';
                        case 'ja': return 'Japanese';
                        case 'ko': return 'Korean';
                        case 'zh': return 'Chinese';
                        case 'es': return 'Spanish';
                        case 'fr': return 'French';
                        case 'de': return 'German';
                        case 'ru': return 'Russian';
                        case 'pt': return 'Portuguese';
                        case 'it': return 'Italian';
                        case 'tr': return 'Turkish';
                        case 'vi': return 'Vietnamese';
                        case 'id': return 'Indonesian';
                        case 'th': return 'Thai';
                        default: return code.toUpperCase();
                      }
                    }

                    final label = getLanguageName(lang);
                    final isLastEnabled = isEnabled && displaySources.where((s) {
                      final l = s['lang']?.toString() ?? 'en';
                      return _isLanguageEnabled(extName, l);
                    }).length <= 1;

                    return GestureDetector(
                      onTap: isLastEnabled ? null : () async {
                        await _setLanguageEnabled(extName, lang, !isEnabled);
                        setDialogState(() {});
                        setState(() {});
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 8.0),
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isEnabled 
                                ? const Color(0xFFFF9F1C).withValues(alpha: 0.5) 
                                : Colors.white.withValues(alpha: 0.06),
                          ),
                          color: isEnabled 
                              ? const Color(0xFFFF9F1C).withValues(alpha: 0.08) 
                              : Colors.white.withValues(alpha: 0.02),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.language, 
                              color: isEnabled ? const Color(0xFFFF9F1C) : Colors.white38, 
                              size: 18
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: isEnabled ? Colors.white : Colors.white54,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: isEnabled,
                                activeColor: Colors.white,
                                activeTrackColor: const Color(0xFFFF9F1C).withValues(alpha: 0.5),
                                inactiveThumbColor: Colors.white30,
                                inactiveTrackColor: Colors.black26,
                                onChanged: isLastEnabled ? null : (val) async {
                                  await _setLanguageEnabled(extName, lang, val);
                                  setDialogState(() {});
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Done',
                    style: TextStyle(color: Color(0xFFFF9F1C), fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildExtensionsTab() {
    final filtered = _extensions.where((ext) {
      if (_extensionsSearchQuery.isEmpty) return true;
      final name = ext['name']?.toString().toLowerCase() ?? '';
      return name.contains(_extensionsSearchQuery.toLowerCase());
    }).toList();

    final installed = filtered.where((ext) => ext['isInstalled'] == true).toList();
    final available = filtered.where((ext) => ext['isInstalled'] != true).toList();

    return Column(
      children: [
        // Extensions Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Container(
            height: 42.0,
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F11),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14.0),
              decoration: const InputDecoration(
                hintText: 'Search extensions...',
                hintStyle: TextStyle(color: Colors.white30),
                prefixIcon: Icon(Icons.search, color: Colors.white30, size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10.0),
              ),
              onChanged: (value) {
                setState(() => _extensionsSearchQuery = value.trim());
              },
            ),
          ),
        ),

        // Extensions List (Installed + Available sections)
        Expanded(
          child: _extensionsError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 40.0),
                        const SizedBox(height: 16.0),
                        const Text(
                          'Failed to load extensions',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.0, fontFamily: 'Outfit'),
                        ),
                        const SizedBox(height: 8.0),
                        Text(
                          _extensionsError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 12.0, fontFamily: 'Outfit'),
                        ),
                        const SizedBox(height: 24.0),
                        ElevatedButton(
                          onPressed: _loadExtensions,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9F1C),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          ),
                          child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                )
              : _loadingExtensions
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                      ),
                    )
                  : SmoothScrollArea(
                  builder: (controller, physics) => ListView(
                    controller: controller,
                    physics: physics,
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    children: [
                      // Installed Section
                      if (installed.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFFFF9F1C), size: 16.0),
                            const SizedBox(width: 8.0),
                            Text(
                              'Installed (${installed.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.0,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0),
                        ...installed.map((ext) => _buildExtensionTile(ext)),
                        const SizedBox(height: 16.0),
                        // Divider between sections
                        Container(
                          height: 1.0,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        const SizedBox(height: 16.0),
                      ],

                      // Available Section
                      if (available.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.download_outlined, color: Colors.white38, size: 16.0),
                            const SizedBox(width: 8.0),
                            Text(
                              'Available (${available.length})',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 14.0,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0),
                        ...available.map((ext) => _buildExtensionTile(ext)),
                      ],

                      // Empty state
                      if (installed.isEmpty && available.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 64.0),
                          child: Center(
                            child: Text(
                              'No extensions found.',
                              style: TextStyle(color: Colors.white30, fontFamily: 'Outfit'),
                            ),
                          ),
                        ),

                      const SizedBox(height: 24.0),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
