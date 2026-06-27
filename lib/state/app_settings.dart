import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global app settings singleton, persisted via SharedPreferences.
class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  bool _smoothScrollEnabled = true;
  String _torrServerUrl = 'http://127.0.0.1:8090';
  String _downloadPath = '';

  bool get smoothScrollEnabled => _smoothScrollEnabled;
  String get torrServerUrl => _torrServerUrl;
  String get downloadPath => _downloadPath;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _smoothScrollEnabled = prefs.getBool('smooth_scroll') ?? true;
    _torrServerUrl = prefs.getString('torrserver_url') ?? 'http://127.0.0.1:8090';
    _downloadPath = prefs.getString('download_path') ?? '';
    notifyListeners();
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
}
