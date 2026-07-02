import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    
    // Auto-start Suwayomi server if not running
    SuwayomiManager.start().then((_) {
      if (mounted) {
        _loadExtensions();
        _loadSources();
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
    await SuwayomiManager.start();
    if (mounted) {
      await _loadExtensions();
      await _loadSources();
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

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Manga: Fetched ${list.length} extensions$extraInfo'),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Manga: Fetched ${list.length} extensions from server'),
              duration: const Duration(seconds: 2),
            ),
          );
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
          if (_selectedSourceId == null && _sources.isNotEmpty) {
            _selectedSourceId = _sources.first['id']?.toString();
            _loadCatalog();
          }
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

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Manga: Fetched ${list.length} catalog sources$extraInfo'),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Manga: Fetched ${list.length} catalog sources from server'),
              duration: const Duration(seconds: 2),
            ),
          );
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
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            ElevatedButton(
              onPressed: _retryConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9F1C),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
              ),
              child: const Text('Retry Startup', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
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
    final bool isMobile = screenWidth < 650;
    final crossAxisCount = (screenWidth / 160).floor().clamp(2, 8);

    return SmoothScrollArea(
      builder: (controller, physics) => SingleChildScrollView(
        controller: controller,
        physics: physics,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sources dropdown & Search Input Row
            Row(
              children: [
                if (_sources.isNotEmpty)
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
                      items: _sources.map<DropdownMenuItem<String>>((source) {
                        return DropdownMenuItem<String>(
                          value: source['id']?.toString(),
                          child: Text('${source['name']} (${source['lang']})'),
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
                  )
                else
                  const Text('No sources installed', style: TextStyle(color: Colors.white30, fontFamily: 'Outfit')),
                
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



            // Catalog Grid Title
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

            // Catalog Grid Content
            if (_catalogError != null)
              Center(
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
              )
            else if (_loadingCatalog)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 64.0),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                  ),
                ),
              )
            else if (_catalogManga.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 64.0),
                  child: Text(
                    'No manga found. Try searching or check extension.',
                    style: TextStyle(color: Colors.white30, fontFamily: 'Outfit'),
                  ),
                ),
              )
            else ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16.0,
                  mainAxisSpacing: 20.0,
                  childAspectRatio: 0.65,
                ),
                itemCount: _catalogManga.length,
                itemBuilder: (context, index) {
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
                    return Opacity(
                      opacity: 0.75,
                      child: cardWidget,
                    );
                  }
                  return cardWidget;
                },
              ),

              // Pagination Controls
              const SizedBox(height: 32.0),
              Row(
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
            ],
          ],
        ),
      ),
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
        trailing: ElevatedButton(
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
      ),
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
