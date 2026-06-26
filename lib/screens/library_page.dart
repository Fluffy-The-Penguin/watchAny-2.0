import 'package:flutter/material.dart';
import '../state/navigation_state.dart';

class LibraryPage extends StatelessWidget {
  final AppMode mode;

  const LibraryPage({
    super.key,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    String modeString = '';
    switch (mode) {
      case AppMode.anime:
        modeString = 'Anime';
        break;
      case AppMode.manga:
        modeString = 'Manga';
        break;
      case AppMode.movies:
        modeString = 'Movies & Webseries';
        break;
    }

    return Center(
      child: Text(
        '$modeString Library',
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
