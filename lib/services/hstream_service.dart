import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String _kHstreamBase = 'https://hstream.moe';
const String _kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36 watchAny/1.0';

// ─────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────

class HstreamResult {
  final String id;
  final String title;
  final String url;
  final String image;
  final double score;

  const HstreamResult({
    required this.id,
    required this.title,
    required this.url,
    required this.image,
    required this.score,
  });
}

class HstreamSource {
  final String name;
  final String quality;
  final String url;
  final String type; // 'video/mp4' or 'application/dash+xml'

  const HstreamSource({
    required this.name,
    required this.quality,
    required this.url,
    required this.type,
  });
}

class HstreamStreams {
  final String title;
  final String poster;
  final List<HstreamSource> sources;
  final List<Map<String, String>> tracks; // subtitle tracks

  const HstreamStreams({
    required this.title,
    required this.poster,
    required this.sources,
    required this.tracks,
  });
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class HstreamService {
  static final HstreamService _instance = HstreamService._internal();
  factory HstreamService() => _instance;
  HstreamService._internal();

  final http.Client _client = http.Client();

  Map<String, String> get _baseHeaders => {
        'User-Agent': _kUserAgent,
        'Accept-Language': 'en-US,en;q=0.9',
      };

  // ── Search ──────────────────────────────────

  /// Search hstream.moe for [query]. Returns ranked results.
  Future<List<HstreamResult>> search(String query) async {
    if (query.trim().isEmpty) return [];

    // 1) Try direct search URL first (faster, no Livewire needed)
    try {
      final uri = Uri.parse(
          '$_kHstreamBase/search?search=${Uri.encodeComponent(query)}');
      final response = await _client.get(uri, headers: {
        ..._baseHeaders,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final results = _parseSearchCards(response.body, query);
        if (results.isNotEmpty) return results;
      }
    } catch (_) {}

    // 2) Fallback: Livewire live-search
    return _searchLivewire(query);
  }

  /// Livewire-based search for when direct search returns nothing.
  Future<List<HstreamResult>> _searchLivewire(String query) async {
    try {
      // Step 1: GET /search to grab session cookie + CSRF token + Livewire snapshot
      final initialResponse = await _client.get(
        Uri.parse('$_kHstreamBase/search'),
        headers: {
          ..._baseHeaders,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 15));

      if (initialResponse.statusCode != 200) return [];

      final html = initialResponse.body;
      final cookie = _cookiesFromResponse(initialResponse);
      final token = _firstMatch(html, RegExp(r'data-csrf="([^"]+)"', caseSensitive: false));
      final snapshot = _hstreamLivewireSnapshot(html);

      if (token == null || snapshot == null) return [];

      // Step 2: POST /livewire/update with the search query
      final livewireResponse = await _client.post(
        Uri.parse('$_kHstreamBase/livewire/update'),
        headers: {
          ..._baseHeaders,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Livewire': 'true',
          'Referer': '$_kHstreamBase/search',
          'Origin': _kHstreamBase,
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
        body: jsonEncode({
          '_token': token,
          'components': [
            {
              'snapshot': snapshot,
              'updates': {'search': query},
              'calls': [],
            }
          ],
        }),
      ).timeout(const Duration(seconds: 15));

      if (livewireResponse.statusCode != 200) return [];

      final data = jsonDecode(livewireResponse.body) as Map<String, dynamic>;
      final components = data['components'] as List<dynamic>? ?? [];
      final responseHtml = components
          .map((c) => (c as Map<String, dynamic>)['effects']?['html'] as String? ?? '')
          .firstWhere((h) => h.isNotEmpty, orElse: () => '');

      return _parseSearchCards(responseHtml, query);
    } catch (e) {
      return [];
    }
  }

  // ── Streams ──────────────────────────────────

  /// Given a hstream.moe hentai page URL, returns playable sources.
  Future<HstreamStreams?> getStreams(String pageUrl) async {
    if (!pageUrl.startsWith('$_kHstreamBase/hentai/')) return null;

    try {
      // Use dart:io HttpClient because package:http on Windows merges all Set-Cookie
      // headers into one string, which breaks cookie parsing and causes CSRF 419 errors.
      final ioClient = HttpClient();

      // Step 1: GET the episode page — grab e_id, _token, session cookies
      final pageReq = await ioClient.getUrl(Uri.parse(pageUrl));
      pageReq.headers.set('User-Agent', _kUserAgent);
      pageReq.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      pageReq.headers.set('Accept-Language', 'en-US,en;q=0.9');
      final pageRes = await pageReq.close();

      if (pageRes.statusCode != 200) {
        ioClient.close();
        return null;
      }

      // dart:io correctly provides individual parsed cookies
      final cookieHeader = pageRes.cookies.map((c) => '${c.name}=${c.value}').join('; ');

      final htmlBytes = <int>[];
      await for (final chunk in pageRes) htmlBytes.addAll(chunk);
      final html = String.fromCharCodes(htmlBytes);

      final episodeId =
          _firstMatch(html, RegExp(r'id="e_id"\s+type="hidden"\s+value="([^"]+)"', caseSensitive: false)) ??
          _firstMatch(html, RegExp(r'value="([^"]+)"\s+[^>]*id="e_id"', caseSensitive: false));
      final token =
          _firstMatch(html, RegExp(r'name="_token"\s+value="([^"]+)"', caseSensitive: false)) ??
          _firstMatch(html, RegExp(r'name="csrf-token"\s+content="([^"]+)"', caseSensitive: false));

      if (episodeId == null || token == null) {
        ioClient.close();
        return null;
      }

      // Step 2: POST /player/api using dart:io to preserve cookies
      final body = jsonEncode({'episode_id': episodeId});
      final bodyBytes = body.codeUnits;
      final apiReq = await ioClient.postUrl(Uri.parse('$_kHstreamBase/player/api'));
      apiReq.headers.set('User-Agent', _kUserAgent);
      apiReq.headers.set('Accept', 'application/json');
      apiReq.headers.set('Content-Type', 'application/json');
      apiReq.headers.set('X-CSRF-TOKEN', token);
      apiReq.headers.set('X-Requested-With', 'XMLHttpRequest');
      apiReq.headers.set('Referer', pageUrl);
      apiReq.headers.set('Origin', _kHstreamBase);
      if (cookieHeader.isNotEmpty) apiReq.headers.set('Cookie', cookieHeader);
      apiReq.contentLength = bodyBytes.length;
      apiReq.add(bodyBytes);

      final apiRes = await apiReq.close();
      final apiBytes = <int>[];
      await for (final chunk in apiRes) apiBytes.addAll(chunk);
      ioClient.close();

      if (apiRes.statusCode != 200) return null;

      final data = jsonDecode(String.fromCharCodes(apiBytes)) as Map<String, dynamic>;
      final globalDomains = (data['stream_domains'] as List<dynamic>? ?? [])
          .map((d) => d.toString())
          .where((d) => d.isNotEmpty)
          .toList();
      final asiaDomains = (data['asia_stream_domains'] as List<dynamic>? ?? [])
          .map((d) => d.toString())
          .where((d) => d.isNotEmpty)
          .toList();

      final streamPath = _hstreamStreamPath(data['stream_url']?.toString() ?? '');
      final sources = <HstreamSource>[];
      final tracks = <Map<String, String>>[];

      final baseDomain = globalDomains.isNotEmpty
          ? globalDomains.first
          : (asiaDomains.isNotEmpty ? asiaDomains.first : '');

      if (baseDomain.isNotEmpty && streamPath.isNotEmpty) {
        tracks.add({
          'kind': 'subtitles',
          'label': 'English',
          'srclang': 'en',
          'url': '$baseDomain/$streamPath/eng.vtt',
        });

        // Build candidates — interpolated flags from API tell us if 48fps exists
        final candidates = <HstreamSource>[
          HstreamSource(name: 'HStream 360p', quality: '360p', url: '$baseDomain/$streamPath/360/manifest.mpd', type: 'application/dash+xml'),
          HstreamSource(name: 'HStream 480p', quality: '480p', url: '$baseDomain/$streamPath/480/manifest.mpd', type: 'application/dash+xml'),
          HstreamSource(name: 'HStream 720p', quality: '720p', url: '$baseDomain/$streamPath/720/manifest.mpd', type: 'application/dash+xml'),
          HstreamSource(name: 'HStream 1080p', quality: '1080p', url: '$baseDomain/$streamPath/1080/manifest.mpd', type: 'application/dash+xml'),
          HstreamSource(name: 'HStream 2160p', quality: '2160p', url: '$baseDomain/$streamPath/2160/manifest.mpd', type: 'application/dash+xml'),
          HstreamSource(name: 'HStream 360p MP4', quality: '360p MP4', url: '$baseDomain/$streamPath/x264.360p.mp4', type: 'video/mp4'),
          HstreamSource(name: 'HStream 480p MP4', quality: '480p MP4', url: '$baseDomain/$streamPath/x264.480p.mp4', type: 'video/mp4'),
          HstreamSource(name: 'HStream 720p MP4', quality: '720p MP4', url: '$baseDomain/$streamPath/x264.720p.mp4', type: 'video/mp4'),
          HstreamSource(name: 'HStream 1080p MP4', quality: '1080p MP4', url: '$baseDomain/$streamPath/x264.1080p.mp4', type: 'video/mp4'),
        ];

        if (data['interpolated']?.toString() == '1') {
          candidates.add(HstreamSource(name: 'HStream 1080p48', quality: '1080p48', url: '$baseDomain/$streamPath/1080i/manifest.mpd', type: 'application/dash+xml'));
        }
        if (data['interpolated_uhd']?.toString() == '1') {
          candidates.add(HstreamSource(name: 'HStream 2160p48', quality: '2160p48', url: '$baseDomain/$streamPath/2160i/manifest.mpd', type: 'application/dash+xml'));
        }

        // Probe candidates concurrently with HEAD requests — only include assets that exist on CDN
        final checkedSources = await Future.wait(candidates.map((source) async {
          try {
            final request = http.Request('HEAD', Uri.parse(source.url));
            request.headers['User-Agent'] = _kUserAgent;
            request.headers['Referer'] = '$_kHstreamBase/';
            final response = await _client.send(request).timeout(const Duration(seconds: 5));
            await response.stream.listen((_) {}).cancel();
            return response.statusCode == 200 ? source : null;
          } catch (_) {
            return null;
          }
        }));

        sources.addAll(checkedSources.whereType<HstreamSource>());
      }

      return HstreamStreams(
        title: _cleanHtml(data['title']?.toString() ?? ''),
        poster: _absolutizeUrl(data['poster']?.toString() ?? ''),
        sources: sources,
        tracks: tracks,
      );
    } catch (e) {
      return null;
    }
  }


  // ── Helpers ──────────────────────────────────

  List<HstreamResult> _parseSearchCards(String html, String query) {
    final results = <HstreamResult>[];
    final seen = <String>{};

    // Match anchor tags linking to /hentai/ pages
    final cardRegex = RegExp(
      r'<a\b[^>]*href="([^"]*\/hentai\/[^"]+)"[^>]*>[\s\S]*?<\/a>',
      caseSensitive: false,
    );

    for (final match in cardRegex.allMatches(html)) {
      final block = match.group(0) ?? '';
      final rawUrl = match.group(1) ?? '';
      if (rawUrl.isEmpty) continue;

      final url = _absolutizeUrl(rawUrl);
      if (seen.contains(url)) continue;
      seen.add(url);

      // Extract title from h3 or img alt
      final title = _cleanHtml(
        _firstMatch(block, RegExp(r'<h3\b[^>]*>([\s\S]*?)<\/h3>', caseSensitive: false)) ??
        _firstMatch(block, RegExp(r'<img\b[^>]*alt="([^"]*)"', caseSensitive: false)) ??
        _titleFromUrl(url),
      );

      if (title.isEmpty) continue;

      final score = _titleScore(query, title);
      if (score < 0.1) continue;

      final image = _absolutizeUrl(
        _firstMatch(block, RegExp(r'<img\b[^>]*(?:data-src|src)="([^"]+)"', caseSensitive: false)) ?? '',
      );

      // Build a stable id from the URL path
      final path = Uri.tryParse(url)?.path ?? url;
      results.add(HstreamResult(
        id: 'hstream:$path',
        title: title,
        url: url,
        image: image,
        score: score,
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  String? _hstreamLivewireSnapshot(String html) {
    final snapRegex = RegExp(r'wire:snapshot="([^"]+)"', caseSensitive: false);
    for (final match in snapRegex.allMatches(html)) {
      final snapshot = _decodeXml(match.group(1) ?? '');
      try {
        final data = jsonDecode(snapshot) as Map<String, dynamic>;
        if (data['memo']?['name'] == 'live-search') return snapshot;
      } catch (_) {}
    }
    return null;
  }

  /// Extracts the stream path segment from the full stream_url field.
  String _hstreamStreamPath(String streamUrl) {
    if (streamUrl.isEmpty) return '';
    
    // If it starts with a protocol, parse the URL and extract the path
    if (streamUrl.startsWith('http://') || streamUrl.startsWith('https://')) {
      try {
        final uri = Uri.parse(streamUrl);
        return uri.path.replaceAll(RegExp(r'^\/+'), '');
      } catch (_) {}
    }
    
    // Otherwise it is already a relative path segment (e.g. "2023/Name/E01")
    // Keep it intact and just strip any leading slashes
    return streamUrl.replaceAll(RegExp(r'^\/+'), '');
  }

  String _cookiesFromResponse(http.Response response) {
    final rawCookies = response.headers['set-cookie'] ?? '';
    if (rawCookies.isEmpty) return '';
    // Each cookie is "name=value; path=...; ..." — keep only "name=value" parts
    return rawCookies
        .split(RegExp(r',(?=[^ ])'))
        .map((c) => c.split(';').first.trim())
        .where((c) => c.isNotEmpty)
        .join('; ');
  }

  String? _firstMatch(String text, RegExp pattern) {
    final m = pattern.firstMatch(text);
    return m != null && m.groupCount >= 1 ? m.group(1) : null;
  }

  String _cleanHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'&#039;'), "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _decodeXml(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'");

  String _absolutizeUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$_kHstreamBase$url';
    return '$_kHstreamBase/$url';
  }

  String _titleFromUrl(String url) {
    try {
      final path = Uri.parse(url).pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
      return path.replaceAll('-', ' ').replaceAll('_', ' ');
    } catch (_) {
      return '';
    }
  }

  // ── Robust title matching ─────────────────────────────────────────

  /// Normalizes a title for comparison:
  /// - lowercase
  /// - expand common romanization ligatures (ō→ou, ū→uu, â→a, etc.)
  /// - strip all non-alphanumeric chars
  /// - collapse whitespace
  String _normalize(String s) {
    var r = s.toLowerCase();
    // Romanization / diacritic substitutions
    const subs = {
      'ō': 'ou', 'ô': 'ou', 'oo': 'ou',
      'ū': 'uu', 'û': 'uu',
      'ā': 'aa', 'â': 'aa',
      'ē': 'ei', 'ê': 'ei',
      'ī': 'ii', 'î': 'ii',
      'æ': 'ae', 'œ': 'oe',
      'ñ': 'n', 'ç': 'c',
      'à': 'a', 'á': 'a', 'ä': 'a', 'å': 'a',
      'è': 'e', 'é': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ö': 'o', 'ø': 'o',
      'ù': 'u', 'ú': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y',
    };
    subs.forEach((k, v) => r = r.replaceAll(k, v));
    // Remove all non-alphanumeric
    r = r.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    // Collapse spaces
    r = r.replaceAll(RegExp(r'\s+'), ' ').trim();
    return r;
  }

  /// Returns a string with ALL spaces removed — used for space-insensitive compare.
  String _compact(String normalized) => normalized.replaceAll(' ', '');

  /// Jaccard similarity on word token sets.
  double _jaccardTokens(List<String> aTokens, List<String> bTokens) {
    if (aTokens.isEmpty && bTokens.isEmpty) return 1.0;
    if (aTokens.isEmpty || bTokens.isEmpty) return 0.0;
    final setA = aTokens.toSet();
    final setB = bTokens.toSet();
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return intersection / union;
  }

  /// Levenshtein edit distance.
  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    // Limit to first 80 chars to avoid O(n²) on long titles
    if (a.length > 80) a = a.substring(0, 80);
    if (b.length > 80) b = b.substring(0, 80);
    final rows = a.length + 1;
    final cols = b.length + 1;
    final d = List<List<int>>.generate(rows, (i) => List<int>.filled(cols, 0));
    for (var i = 0; i < rows; i++) { d[i][0] = i; }
    for (var j = 0; j < cols; j++) { d[0][j] = j; }
    for (var i = 1; i < rows; i++) {
      for (var j = 1; j < cols; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
    }
    return d[rows - 1][cols - 1];
  }

  /// Levenshtein similarity ratio 0.0–1.0.
  double _levenshteinSimilarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - _levenshtein(a, b) / maxLen;
  }

  /// Main scoring function — returns best score 0.0–1.0 across all strategies.
  double _titleScore(String query, String title) {
    // Normalize both
    final qn = _normalize(query);
    final tn = _normalize(title);

    // 1. Exact normalized match
    if (qn == tn) return 1.0;

    // 2. Space-stripped (handles "natsu zuma" == "natsuzuma")
    final qc = _compact(qn);
    final tc = _compact(tn);
    if (qc == tc) return 0.98;
    if (qc.isNotEmpty && tc.contains(qc)) return 0.93;
    if (qc.isNotEmpty && qc.contains(tc)) return 0.9;

    // 3. Normalized substring containment
    if (qn.isNotEmpty && tn.contains(qn)) return 0.88;
    if (qn.isNotEmpty && qn.contains(tn)) return 0.85;

    // 4. Token-level Jaccard
    final qWords = qn.split(' ').where((w) => w.length > 1).toList();
    final tWords = tn.split(' ').where((w) => w.length > 1).toList();
    double score = 0.0;

    final jaccard = _jaccardTokens(qWords, tWords);
    score = score > jaccard ? score : jaccard;

    // 5. Token-overlap ratio: how many query words appear in title (partial substring)
    if (qWords.isNotEmpty) {
      final matched = qWords.where((w) => tn.contains(w)).length;
      final overlap = matched / qWords.length * 0.82;
      score = score > overlap ? score : overlap;
    }

    // 6. Space-stripped Levenshtein (catches single char typos across fused words)
    if (qc.length >= 3 && tc.length >= 3) {
      final lev = _levenshteinSimilarity(qc, tc) * 0.88;
      score = score > lev ? score : lev;
    }

    // 7. Per-token Levenshtein: best token pair match
    if (qWords.isNotEmpty && tWords.isNotEmpty) {
      double bestToken = 0.0;
      for (final qw in qWords) {
        for (final tw in tWords) {
          final s = _levenshteinSimilarity(qw, tw);
          if (s > bestToken) bestToken = s;
        }
      }
      // Weight by how many tokens we have
      final tokenScore = bestToken * (qWords.length.clamp(1, 3) / 3) * 0.75;
      score = score > tokenScore ? score : tokenScore;
    }

    // Filter out clearly unrelated results
    return score < 0.2 ? 0.0 : score;
  }
}
