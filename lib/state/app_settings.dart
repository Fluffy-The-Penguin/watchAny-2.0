import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'navigation_state.dart';

/// Global app settings singleton, persisted via SharedPreferences.
class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  bool _smoothScrollEnabled = true;
  String _torrServerUrl = 'http://127.0.0.1:8090';
  String _downloadPath = '';
  bool _hardwareAccelerationEnabled = true;
  String _startupModeStr = 'anime';
  String _startupPageStr = 'home';
  bool _autoPlay = true;
  bool _autoNext = true;
  bool _autoSkipIntro = false;

  // Custom Subtitles configuration
  bool _subtitlesCustomStylesEnabled = true;
  bool _subtitlesBgEnabled = false;
  int _subtitlesBgColor = 0xFF000000; // Base solid color (default black)
  double _subtitlesBgOpacity = 0.5;
  String _subtitlesFontFamily = 'Outfit';
  double _subtitlesFontSize = 16.0;
  bool _subtitlesBold = false;
  bool _subtitlesItalic = false;
  double _subtitlesPositionOffset = 24.0;
  double _subtitlesXOffset = 0.0;
  int _subtitlesTextColor = 0xFFFFFFFF; // Default white
  bool _subtitlesShadowEnabled = true;
  int _subtitlesShadowColor = 0xFF000000; // Default black shadow
  double _subtitlesShadowOpacity = 0.8;
  double _subtitlesShadowBlurRadius = 2.0;
  double _subtitlesShadowOffset = 1.5;

  bool get smoothScrollEnabled => _smoothScrollEnabled;
  String get torrServerUrl => _torrServerUrl;
  String get downloadPath => _downloadPath;
  bool get hardwareAccelerationEnabled => _hardwareAccelerationEnabled;
  String get startupModeStr => _startupModeStr;
  String get startupPageStr => _startupPageStr;
  bool get autoPlay => _autoPlay;
  bool get autoNext => _autoNext;
  bool get autoSkipIntro => _autoSkipIntro;

  // Custom Subtitles getters
  bool get subtitlesCustomStylesEnabled => _subtitlesCustomStylesEnabled;
  bool get subtitlesBgEnabled => _subtitlesBgEnabled;
  int get subtitlesBgColor => _subtitlesBgColor;
  double get subtitlesBgOpacity => _subtitlesBgOpacity;
  String get subtitlesFontFamily => _subtitlesFontFamily;
  double get subtitlesFontSize => _subtitlesFontSize;
  bool get subtitlesBold => _subtitlesBold;
  bool get subtitlesItalic => _subtitlesItalic;
  double get subtitlesPositionOffset => _subtitlesPositionOffset;
  double get subtitlesXOffset => _subtitlesXOffset;
  int get subtitlesTextColor => _subtitlesTextColor;
  bool get subtitlesShadowEnabled => _subtitlesShadowEnabled;
  int get subtitlesShadowColor => _subtitlesShadowColor;
  double get subtitlesShadowOpacity => _subtitlesShadowOpacity;
  double get subtitlesShadowBlurRadius => _subtitlesShadowBlurRadius;
  double get subtitlesShadowOffset => _subtitlesShadowOffset;

  AppMode get startupMode {
    switch (_startupModeStr) {
      case 'manga': return AppMode.manga;
      case 'movies': return AppMode.movies;
      default: return AppMode.anime;
    }
  }

  TabPage get startupPage {
    switch (_startupPageStr) {
      case 'search': return TabPage.search;
      case 'library': return TabPage.library;
      case 'schedule': return TabPage.schedule;
      case 'downloads': return TabPage.downloads;
      case 'settings': return TabPage.settings;
      default: return TabPage.home;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _smoothScrollEnabled = prefs.getBool('smooth_scroll') ?? true;
    _torrServerUrl = prefs.getString('torrserver_url') ?? 'http://127.0.0.1:8090';
    _downloadPath = prefs.getString('download_path') ?? '';
    _hardwareAccelerationEnabled = prefs.getBool('hardware_acceleration') ?? true;
    _startupModeStr = prefs.getString('startup_mode') ?? 'anime';
    _startupPageStr = prefs.getString('startup_page') ?? 'home';
    _autoPlay = prefs.getBool('auto_play') ?? true;
    _autoNext = prefs.getBool('auto_next') ?? true;
    _autoSkipIntro = prefs.getBool('auto_skip_intro') ?? false;

    // Subtitles settings initialization
    _subtitlesCustomStylesEnabled = prefs.getBool('subtitles_custom_styles_enabled') ?? true;
    _subtitlesBgEnabled = prefs.getBool('subtitles_bg_enabled') ?? false;
    
    // Handle backwards compatibility for older color formatting
    final int rawBgColor = prefs.getInt('subtitles_bg_color') ?? 0x80000000;
    if (rawBgColor == 0x80000000) {
      _subtitlesBgColor = 0xFF000000;
      _subtitlesBgOpacity = 0.5;
    } else if ((rawBgColor & 0xFF000000) != 0xFF000000 && rawBgColor != 0) {
      // It has alpha, parse it
      final double alpha = ((rawBgColor >> 24) & 0xFF) / 255.0;
      _subtitlesBgColor = (rawBgColor & 0x00FFFFFF) | 0xFF000000;
      _subtitlesBgOpacity = alpha;
    } else {
      _subtitlesBgColor = rawBgColor;
      _subtitlesBgOpacity = prefs.getDouble('subtitles_bg_opacity') ?? 0.5;
    }
    
    _subtitlesFontFamily = prefs.getString('subtitles_font_family') ?? 'Outfit';
    _subtitlesFontSize = prefs.getDouble('subtitles_font_size') ?? 16.0;
    _subtitlesBold = prefs.getBool('subtitles_bold') ?? false;
    _subtitlesItalic = prefs.getBool('subtitles_italic') ?? false;
    _subtitlesPositionOffset = prefs.getDouble('subtitles_position_offset') ?? 24.0;
    _subtitlesXOffset = prefs.getDouble('subtitles_x_offset') ?? 0.0;
    _subtitlesTextColor = prefs.getInt('subtitles_text_color') ?? 0xFFFFFFFF;
    _subtitlesShadowEnabled = prefs.getBool('subtitles_shadow_enabled') ?? true;
    _subtitlesShadowColor = prefs.getInt('subtitles_shadow_color') ?? 0xFF000000;
    _subtitlesShadowOpacity = prefs.getDouble('subtitles_shadow_opacity') ?? 0.8;
    _subtitlesShadowBlurRadius = prefs.getDouble('subtitles_shadow_blur_radius') ?? 2.0;
    _subtitlesShadowOffset = prefs.getDouble('subtitles_shadow_offset') ?? 1.5;
    notifyListeners();
  }

  Future<void> setAutoSkipIntro(bool value) async {
    if (_autoSkipIntro == value) return;
    _autoSkipIntro = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_skip_intro', value);
  }

  Future<void> setAutoPlay(bool value) async {
    if (_autoPlay == value) return;
    _autoPlay = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_play', value);
  }

  Future<void> setAutoNext(bool value) async {
    if (_autoNext == value) return;
    _autoNext = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_next', value);
  }

  Future<void> setSmoothScrollEnabled(bool value) async {
    if (_smoothScrollEnabled == value) return;
    _smoothScrollEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smooth_scroll', value);
  }

  Future<void> setTorrServerUrl(String value) async {
    if (_torrServerUrl == value) return;
    _torrServerUrl = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('torrserver_url', value);
  }

  Future<void> setDownloadPath(String value) async {
    if (_downloadPath == value) return;
    _downloadPath = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('download_path', value);
  }

  Future<void> setHardwareAccelerationEnabled(bool value) async {
    if (_hardwareAccelerationEnabled == value) return;
    _hardwareAccelerationEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hardware_acceleration', value);
  }

  void updateLocalTorrServerPort(int port) {
    if (_torrServerUrl.contains('127.0.0.1') || _torrServerUrl.contains('localhost')) {
      _torrServerUrl = 'http://127.0.0.1:$port';
      notifyListeners();
    }
  }

  Future<void> setStartupModeStr(String value) async {
    if (_startupModeStr == value) return;
    _startupModeStr = value;
    if (_startupModeStr != 'anime' && _startupPageStr == 'schedule') {
      _startupPageStr = 'home';
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('startup_mode', value);
    await prefs.setString('startup_page', _startupPageStr);
  }

  Future<void> setStartupPageStr(String value) async {
    if (_startupPageStr == value) return;
    _startupPageStr = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('startup_page', value);
  }

  Future<void> setSubtitlesBgEnabled(bool value) async {
    if (_subtitlesBgEnabled == value) return;
    _subtitlesBgEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitles_bg_enabled', value);
  }

  Future<void> setSubtitlesBgColor(int value) async {
    if (_subtitlesBgColor == value) return;
    _subtitlesBgColor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('subtitles_bg_color', value);
  }

  Future<void> setSubtitlesBgOpacity(double value) async {
    if (_subtitlesBgOpacity == value) return;
    _subtitlesBgOpacity = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_bg_opacity', value);
  }

  Future<void> setSubtitlesFontFamily(String value) async {
    if (_subtitlesFontFamily == value) return;
    _subtitlesFontFamily = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subtitles_font_family', value);
  }

  Future<void> setSubtitlesFontSize(double value) async {
    if (_subtitlesFontSize == value) return;
    _subtitlesFontSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_font_size', value);
  }

  Future<void> setSubtitlesBold(bool value) async {
    if (_subtitlesBold == value) return;
    _subtitlesBold = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitles_bold', value);
  }

  Future<void> setSubtitlesItalic(bool value) async {
    if (_subtitlesItalic == value) return;
    _subtitlesItalic = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitles_italic', value);
  }

  Future<void> setSubtitlesPositionOffset(double value, {bool save = true}) async {
    if (_subtitlesPositionOffset == value) return;
    _subtitlesPositionOffset = value;
    notifyListeners();
    if (save) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('subtitles_position_offset', value);
    }
  }

  Future<void> setSubtitlesTextColor(int value) async {
    if (_subtitlesTextColor == value) return;
    _subtitlesTextColor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('subtitles_text_color', value);
  }

  Future<void> setSubtitlesShadowEnabled(bool value) async {
    if (_subtitlesShadowEnabled == value) return;
    _subtitlesShadowEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitles_shadow_enabled', value);
  }

  Future<void> setSubtitlesShadowColor(int value) async {
    if (_subtitlesShadowColor == value) return;
    _subtitlesShadowColor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('subtitles_shadow_color', value);
  }

  Future<void> setSubtitlesShadowOpacity(double value) async {
    if (_subtitlesShadowOpacity == value) return;
    _subtitlesShadowOpacity = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_shadow_opacity', value);
  }

  Future<void> setSubtitlesShadowBlurRadius(double value) async {
    if (_subtitlesShadowBlurRadius == value) return;
    _subtitlesShadowBlurRadius = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_shadow_blur_radius', value);
  }

  Future<void> setSubtitlesShadowOffset(double value) async {
    if (_subtitlesShadowOffset == value) return;
    _subtitlesShadowOffset = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_shadow_offset', value);
  }

  Future<void> setSubtitlesXOffset(double value, {bool save = true}) async {
    if (_subtitlesXOffset == value) return;
    _subtitlesXOffset = value;
    notifyListeners();
    if (save) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('subtitles_x_offset', value);
    }
  }

  Future<void> saveSubtitlesPosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_position_offset', _subtitlesPositionOffset);
    await prefs.setDouble('subtitles_x_offset', _subtitlesXOffset);
  }

  Future<void> setSubtitlesCustomStylesEnabled(bool value) async {
    if (_subtitlesCustomStylesEnabled == value) return;
    _subtitlesCustomStylesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitles_custom_styles_enabled', value);
  }

  Future<void> resetSubtitlesToDefault() async {
    _subtitlesCustomStylesEnabled = true;
    _subtitlesBgEnabled = false;
    _subtitlesBgColor = 0xFF000000;
    _subtitlesBgOpacity = 0.5;
    _subtitlesFontFamily = 'Outfit';
    _subtitlesFontSize = 16.0;
    _subtitlesBold = false;
    _subtitlesItalic = false;
    _subtitlesPositionOffset = 24.0;
    _subtitlesXOffset = 0.0;
    _subtitlesTextColor = 0xFFFFFFFF;
    _subtitlesShadowEnabled = true;
    _subtitlesShadowColor = 0xFF000000;
    _subtitlesShadowOpacity = 0.8;
    _subtitlesShadowBlurRadius = 2.0;
    _subtitlesShadowOffset = 1.5;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitles_custom_styles_enabled', true);
    await prefs.setBool('subtitles_bg_enabled', false);
    await prefs.setInt('subtitles_bg_color', 0xFF000000);
    await prefs.setDouble('subtitles_bg_opacity', 0.5);
    await prefs.setString('subtitles_font_family', 'Outfit');
    await prefs.setDouble('subtitles_font_size', 16.0);
    await prefs.setBool('subtitles_bold', false);
    await prefs.setBool('subtitles_italic', false);
    await prefs.setDouble('subtitles_position_offset', 24.0);
    await prefs.setDouble('subtitles_x_offset', 0.0);
    await prefs.setInt('subtitles_text_color', 0xFFFFFFFF);
    await prefs.setBool('subtitles_shadow_enabled', true);
    await prefs.setInt('subtitles_shadow_color', 0xFF000000);
    await prefs.setDouble('subtitles_shadow_opacity', 0.8);
    await prefs.setDouble('subtitles_shadow_blur_radius', 2.0);
    await prefs.setDouble('subtitles_shadow_offset', 1.5);
  }
}
