import '../lib/services/anilist_service.dart';

void main() async {
  final service = AnilistService();
  final categories = ['trending', 'popular', 'newlyReleased', 'upcoming', 'Action'];
  
  for (final cat in categories) {
    try {
      print("Testing category: $cat...");
      final now = DateTime.now();
      final season = AnilistService.getCurrentSeason(now);
      final year = now.year;
      
      Map<String, dynamic> result;
      if (cat == 'trending') {
        result = await service.search(page: 2, perPage: 12, type: 'ANIME', sort: 'TRENDING_DESC');
      } else if (cat == 'popular') {
        result = await service.search(page: 2, perPage: 12, type: 'ANIME', season: season, year: year, sort: 'POPULARITY_DESC');
      } else if (cat == 'newlyReleased') {
        result = await service.search(page: 2, perPage: 12, type: 'ANIME', status: 'RELEASING', sort: 'TRENDING_DESC');
      } else if (cat == 'upcoming') {
        result = await service.search(page: 2, perPage: 12, type: 'ANIME', status: 'NOT_YET_RELEASED', sort: 'POPULARITY_DESC');
      } else {
        result = await service.search(page: 2, perPage: 12, type: 'ANIME', genres: [cat], sort: 'POPULARITY_DESC');
      }
      
      print("-> SUCCESS: ${result['Page']?['media']?.length} items");
    } catch (e) {
      print("-> FAILED: $e");
    }
  }
}
