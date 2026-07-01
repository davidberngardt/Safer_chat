import '../utils/platform_utils.dart';

enum SearchResultType { chat, contact, channel, group }

class SearchResult {
  final int id;
  final String title;
  final String? subtitle;
  final SearchResultType type;
  final DateTime? lastInteraction;

  SearchResult({
    required this.id,
    required this.title,
    this.subtitle,
    required this.type,
    this.lastInteraction,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json, SearchResultType type) {
    return SearchResult(
      id: json['id'],
      title: json['name'] ?? json['title'] ?? '',
      subtitle: json['description'] ?? json['lastMessage'],
      type: type,
      lastInteraction: json['lastInteraction'] != null 
        ? DateTime.parse(json['lastInteraction']) 
        : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'type': type.toString(),
      'lastInteraction': lastInteraction?.toIso8601String(),
    };
  }
}
