import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfileState extends ChangeNotifier {
  static final UserProfileState _instance = UserProfileState._internal();
  factory UserProfileState() => _instance;
  UserProfileState._internal() {
    loadProfile();
  }

  String _displayName = 'watchAny Explorer';
  String _userTitle = 'Otaku & Cinephile';
  String _bio = 'Passionate Anime & Film Collector';
  String _favoriteQuote = 'People\'s dreams... never end!';
  int _avatarIndex = 0;
  int _bannerIndex = 0;
  String _customAvatarUrl = '';
  String _customBannerUrl = '';
  List<Map<String, String>> _favoriteItems = [];

  String get displayName => _displayName;
  String get userTitle => _userTitle;
  String get bio => _bio;
  String get favoriteQuote => _favoriteQuote;
  int get avatarIndex => _avatarIndex;
  int get bannerIndex => _bannerIndex;
  String get customAvatarUrl => _customAvatarUrl;
  String get customBannerUrl => _customBannerUrl;
  List<Map<String, String>> get favoriteItems => List.unmodifiable(_favoriteItems);

  Future<void> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString('user_profile_name') ?? 'watchAny Explorer';
    _userTitle = prefs.getString('user_profile_title') ?? 'Otaku & Cinephile';
    _bio = prefs.getString('user_profile_bio') ?? 'Passionate Anime & Film Collector';
    _favoriteQuote = prefs.getString('user_profile_quote') ?? 'People\'s dreams... never end!';
    _avatarIndex = prefs.getInt('user_profile_avatar') ?? 0;
    _bannerIndex = prefs.getInt('user_profile_banner') ?? 0;
    _customAvatarUrl = prefs.getString('user_profile_custom_avatar') ?? '';
    _customBannerUrl = prefs.getString('user_profile_custom_banner') ?? '';
    
    final favJson = prefs.getString('user_profile_favorite_items');
    if (favJson != null && favJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(favJson);
        _favoriteItems = decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      } catch (_) {
        _favoriteItems = [];
      }
    } else {
      _favoriteItems = [];
    }

    notifyListeners();
  }

  Future<void> saveProfile({
    required String name,
    required String userTitle,
    required String bio,
    required String quote,
    required int avatarIdx,
    required int bannerIdx,
    required String customAvatar,
    required String customBanner,
  }) async {
    _displayName = name;
    _userTitle = userTitle;
    _bio = bio;
    _favoriteQuote = quote;
    _avatarIndex = avatarIdx;
    _bannerIndex = bannerIdx;
    _customAvatarUrl = customAvatar;
    _customBannerUrl = customBanner;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile_name', _displayName);
    await prefs.setString('user_profile_title', _userTitle);
    await prefs.setString('user_profile_bio', _bio);
    await prefs.setString('user_profile_quote', _favoriteQuote);
    await prefs.setInt('user_profile_avatar', _avatarIndex);
    await prefs.setInt('user_profile_banner', _bannerIndex);
    await prefs.setString('user_profile_custom_avatar', _customAvatarUrl);
    await prefs.setString('user_profile_custom_banner', _customBannerUrl);

    notifyListeners();
  }

  Future<void> setFavoriteItem(int index, Map<String, String> itemData) async {
    while (_favoriteItems.length <= index) {
      _favoriteItems.add({});
    }
    _favoriteItems[index] = itemData;
    _saveFavoriteItems();
  }

  Future<void> removeFavoriteItem(int index) async {
    if (index >= 0 && index < _favoriteItems.length) {
      _favoriteItems.removeAt(index);
      _saveFavoriteItems();
    }
  }

  Future<void> _saveFavoriteItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile_favorite_items', jsonEncode(_favoriteItems));
    notifyListeners();
  }

  ImageProvider? getAvatarImageProvider() {
    if (_customAvatarUrl.isNotEmpty) {
      if (_customAvatarUrl.startsWith('http://') || _customAvatarUrl.startsWith('https://')) {
        return NetworkImage(_customAvatarUrl);
      }
      final file = File(_customAvatarUrl);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return null;
  }
}
