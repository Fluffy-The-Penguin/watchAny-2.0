import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/anilist_service.dart';

class AnilistAuthState extends ChangeNotifier {
  static final AnilistAuthState _instance = AnilistAuthState._internal();
  factory AnilistAuthState() => _instance;
  AnilistAuthState._internal();

  String? _accessToken;
  String? _username;
  String? _avatarUrl;
  int? _userId;
  bool _isAutoSyncEnabled = true;

  bool get isLoggedIn => _accessToken != null;
  String? get accessToken => _accessToken;
  String? get username => _username;
  String? get avatarUrl => _avatarUrl;
  int? get userId => _userId;
  bool get isAutoSyncEnabled => _isAutoSyncEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('anilist_access_token');
    _username = prefs.getString('anilist_username');
    _avatarUrl = prefs.getString('anilist_avatar_url');
    _userId = prefs.getInt('anilist_user_id');
    _isAutoSyncEnabled = prefs.getBool('anilist_auto_sync') ?? true;
    notifyListeners();
  }

  Future<bool> login(String token) async {
    try {
      final viewer = await AnilistService().fetchViewerDetails(token);
      if (viewer != null) {
        _accessToken = token;
        _username = viewer['name'];
        _avatarUrl = viewer['avatar']?['large'];
        _userId = viewer['id'];
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('anilist_access_token', token);
        await prefs.setString('anilist_username', _username!);
        if (_avatarUrl != null) {
          await prefs.setString('anilist_avatar_url', _avatarUrl!);
        }
        if (_userId != null) {
          await prefs.setInt('anilist_user_id', _userId!);
        }
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> logout() async {
    _accessToken = null;
    _username = null;
    _avatarUrl = null;
    _userId = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('anilist_access_token');
    await prefs.remove('anilist_username');
    await prefs.remove('anilist_avatar_url');
    await prefs.remove('anilist_user_id');
    notifyListeners();
  }

  Future<void> setAutoSync(bool enabled) async {
    _isAutoSyncEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('anilist_auto_sync', enabled);
    notifyListeners();
  }
}
