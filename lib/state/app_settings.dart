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

  bool get smoothScrollEnabled => _smoothScrollEnabled;
  String get torrServerUrl => _torrServerUrl;
  String get downloadPath => _downloadPath;
  bool get hardwareAccelerationEnabled => _hardwareAccelerationEnabled;
  String get startupModeStr => _startupModeStr;
  String get startupPageStr => _startupPageStr;
  bool get autoPlay => _autoPlay;
  bool get autoNext => _autoNext;

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
    notifyListeners();
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
}
