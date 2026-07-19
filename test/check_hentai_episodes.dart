import '../lib/services/anilist_service.dart';
import '../lib/services/hstream_service.dart';

void main() async {
  final anilist = AnilistService();
  final hstream = HstreamService();

  print('Searching AniList for Futei the Animation...');
  final alResults = await anilist.search(searchQuery: 'Futei the Animation', type: 'ANIME', page: 1, perPage: 5);
  final mediaList = alResults['Page']?['media'] as List<dynamic>? ?? [];
  
  if (mediaList.isEmpty) {
    print('No Natsuzuma found on AniList.');
    return;
  }

  for (final media in mediaList) {
    final mediaId = media['id'] as int;
    print('Fetching full details for media ID: $mediaId...');
    final fullDetails = await anilist.fetchAnimeDetails(mediaId);
    
    final titleObj = fullDetails['title'] as Map<String, dynamic>? ?? {};
    final titles = <String>[];
    if (titleObj['english'] != null) titles.add(titleObj['english']);
    if (titleObj['romaji'] != null) titles.add(titleObj['romaji']);
    if (titleObj['native'] != null) titles.add(titleObj['native']);
    
    final synonyms = fullDetails['synonyms'] as List<dynamic>? ?? [];
    print('AniList Synonyms: $synonyms');
    titles.addAll(synonyms.map((s) => s.toString()));

    print('AniList Titles: $titles');
    
    final searchTerms = hstream.generateSearchTerms(titles);
    print('Generated HStream search terms: $searchTerms');

    for (final term in searchTerms) {
      print('Searching HStream for term: "$term"');
      final results = await hstream.search(term);
      print('HStream results for "$term":');
      for (final r in results) {
        print('  - Title: "${r.title}", URL: "${r.url}", Score: ${r.score}');
      }
    }
  }
}
