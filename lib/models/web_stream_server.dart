enum AudioType {
  sub,
  dub,
}

class WebStreamServer {
  final String id;
  final String name;
  final String badge;
  final String description;
  final bool supportsDub;
  final String qualityLabel;
  final String Function({
    required int anilistId,
    required int episode,
    required AudioType audioType,
    int? malId,
  }) urlBuilder;

  const WebStreamServer({
    required this.id,
    required this.name,
    required this.badge,
    required this.description,
    required this.supportsDub,
    required this.qualityLabel,
    required this.urlBuilder,
  });
}
