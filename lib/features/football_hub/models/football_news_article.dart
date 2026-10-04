// lib/features/football_hub/models/football_news_article.dart

/// A single article returned by GNews's /v4/search endpoint.
///
/// Parsing is defensive (every field has a safe default) because this data
/// comes from a third-party upstream API this app does not control -- an
/// unexpected null/missing field must never crash the News tab.
class FootballNewsArticle {
  final String title;
  final String description;
  final String url;
  final String imageUrl;
  final String sourceName;
  final DateTime? publishedAt;

  const FootballNewsArticle({
    required this.title,
    required this.description,
    required this.url,
    required this.imageUrl,
    required this.sourceName,
    required this.publishedAt,
  });

  factory FootballNewsArticle.fromJson(Map<String, dynamic> json) {
    final source = (json['source'] as Map?)?.cast<String, dynamic>() ?? const {};
    final publishedRaw = (json['publishedAt'] as String?)?.trim() ?? '';

    return FootballNewsArticle(
      title: (json['title'] as String?)?.trim() ?? '',
      description: (json['description'] as String?)?.trim() ?? '',
      url: (json['url'] as String?)?.trim() ?? '',
      imageUrl: (json['image'] as String?)?.trim() ?? '',
      sourceName: (source['name'] as String?)?.trim() ?? '',
      publishedAt: publishedRaw.isEmpty ? null : DateTime.tryParse(publishedRaw),
    );
  }
}
