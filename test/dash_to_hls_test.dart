import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final url = 'https://imoto-str.ane-h.xyz/2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01/1080/manifest.mpd';
  
  final response = await http.get(Uri.parse(url));
  final mpdText = response.body;

  // We need to parse <AdaptationSet> and <Representation>
  // A simple way is to split by <AdaptationSet
  final adaptationSets = mpdText.split('<AdaptationSet');
  
  String masterPlaylist = '#EXTM3U\n';
  
  for (int i = 1; i < adaptationSets.length; i++) {
    final setXml = adaptationSets[i];
    final isVideo = setXml.contains('contentType="video"');
    final isAudio = setXml.contains('contentType="audio"');
    
    // Find Representation
    final repMatch = RegExp(r'<Representation id="([^"]+)"[^>]*bandwidth="([^"]+)"').firstMatch(setXml);
    if (repMatch == null) continue;
    
    final repId = repMatch.group(1)!;
    final bandwidth = repMatch.group(2)!;
    
    // Find SegmentTemplate
    final segMatch = RegExp(r'<SegmentTemplate timescale="([^"]+)" initialization="([^"]+)" media="([^"]+)" startNumber="([^"]+)"').firstMatch(setXml);
    if (segMatch == null) continue;
    
    final timescale = double.parse(segMatch.group(1)!);
    final initPath = segMatch.group(2)!.replaceAll(r'\', '/').replaceAll(r'$RepresentationID$', repId);
    final mediaPathFormat = segMatch.group(3)!.replaceAll(r'\', '/').replaceAll(r'$RepresentationID$', repId);
    final startNumber = int.parse(segMatch.group(4)!);
    
    // Find SegmentTimeline S tags
    final sTags = RegExp(r'<S (?:t="([^"]+)" )?d="([^"]+)"(?: r="([^"]+)")? />').allMatches(setXml);
    
    String playlist = '#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:11\n#EXT-X-MEDIA-SEQUENCE:$startNumber\n';
    playlist += '#EXT-X-MAP:URI="$initPath"\n';
    
    int currentNum = startNumber;
    for (final s in sTags) {
      final d = double.parse(s.group(2)!);
      final r = s.group(3) != null ? int.parse(s.group(3)!) : 0;
      
      final duration = d / timescale;
      
      for (int k = 0; k <= r; k++) {
        playlist += '#EXTINF:${duration.toStringAsFixed(3)},\n';
        
        // Format $Number%05d$
        final numberStr = currentNum.toString().padLeft(5, '0');
        final mediaPath = mediaPathFormat.replaceAll(r'$Number%05d$', numberStr);
        playlist += '$mediaPath\n';
        currentNum++;
      }
    }
    playlist += '#EXT-X-ENDLIST\n';
    
    if (isVideo) {
      print('\n--- VIDEO PLAYLIST ($bandwidth bps) ---');
      print(playlist.substring(0, 300) + '...\n');
      masterPlaylist += '#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,AUDIO="audio"\nvideo.m3u8\n';
    } else if (isAudio) {
      print('\n--- AUDIO PLAYLIST ($bandwidth bps) ---');
      print(playlist.substring(0, 300) + '...\n');
      masterPlaylist = '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",URI="audio.m3u8"\n' + masterPlaylist;
    }
  }
  
  print('\n--- MASTER PLAYLIST ---');
  print(masterPlaylist);
}
