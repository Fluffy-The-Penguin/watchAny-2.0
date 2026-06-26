import 'package:flutter/material.dart';
import '../state/navigation_state.dart';
import 'anime_home_page.dart';

class HomePage extends StatelessWidget {
  final AppMode mode;
  final NavigationState navigationState;

  const HomePage({
    super.key,
    required this.mode,
    required this.navigationState,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == AppMode.anime) {
      return AnimeHomePage(navigationState: navigationState);
    }

    String modeString = '';
    switch (mode) {
      case AppMode.manga:
        modeString = 'Manga';
        break;
      case AppMode.movies:
        modeString = 'Movies & Webseries';
        break;
      case AppMode.anime:
        modeString = 'Anime';
        break;
    }

    return Center(
      child: Text(
        '$modeString Home',
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 20.0,
          fontWeight: FontWeight.w400,
          fontFamily: 'Outfit',
        ),
      ),
    );
  }
}
