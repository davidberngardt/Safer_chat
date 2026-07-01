import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/search_result.dart';
import '../utils/platform_utils.dart';

class SearchService {
  final String baseUrl;
  final String token;
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 10;

  SearchService({required this.baseUrl, required this.token});

  // Поиск по всем источникам
  Future<List<SearchResult>> searchAll(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final url = '$baseUrl/api/search?q=${Uri.encodeComponent(query)}';
      print('🔍 Search URL: $url');
      print('🔍 Search query: "$query"');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response status: ${response.statusCode}');
      print('📦 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<SearchResult> results = [];

        // Парсим чаты
        if (data['chats'] != null) {
          print('💬 Found ${(data['chats'] as List).length} chats');
          for (var chat in data['chats']) {
            print('  Chat: ${chat['title'] ?? chat['name']}');
            results.add(SearchResult.fromJson(chat, SearchResultType.chat));
          }
        }

        // Парсим контакты
        if (data['contacts'] != null) {
          print('👤 Found ${(data['contacts'] as List).length} contacts');
          for (var contact in data['contacts']) {
            print('  Contact: ${contact['title'] ?? contact['name']}');
            results.add(SearchResult.fromJson(contact, SearchResultType.contact));
          }
        }

        // Парсим каналы
        if (data['channels'] != null) {
          print('📺 Found ${(data['channels'] as List).length} channels');
          for (var channel in data['channels']) {
            print('  Channel data: $channel');
            print('  Channel name: ${channel['name']}');
            results.add(SearchResult.fromJson(channel, SearchResultType.channel));
          }
        }

        print('✅ Total results: ${results.length}');
        return results;
      } else {
        print('❌ Server error: ${response.statusCode}');
        print('❌ Error body: ${response.body}');
      }
    } catch (e, stackTrace) {
      print('❌ Search error: $e');
      print('❌ Stack trace: $stackTrace');
    }
    return [];
  }

  // Сохранить недавний поиск
  Future<void> saveRecentSearch(SearchResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recent = await getRecentSearches();

      // Удаляем дубликаты
      recent.removeWhere((r) => r.id == result.id && r.type == result.type);

      // Добавляем в начало
      recent.insert(0, result);

      // Ограничиваем количество
      if (recent.length > _maxRecentSearches) {
        recent.removeRange(_maxRecentSearches, recent.length);
      }

      // Сохраняем
      final jsonList = recent.map((r) => jsonEncode(r.toJson())).toList();
      await prefs.setStringList(_recentSearchesKey, jsonList);
      print('💾 Saved recent search: ${result.title}');
    } catch (e) {
      print('❌ Error saving recent search: $e');
    }
  }

  // Получить недавние поиски
  Future<List<SearchResult>> getRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_recentSearchesKey) ?? [];

      final results = jsonList.map((json) {
        final map = jsonDecode(json);
        final typeStr = map['type'].toString().split('.').last;
        final type = SearchResultType.values.firstWhere(
          (t) => t.toString().split('.').last == typeStr,
          orElse: () => SearchResultType.chat,
        );
        return SearchResult.fromJson(map, type);
      }).toList();

      print('📋 Loaded ${results.length} recent searches');
      return results;
    } catch (e) {
      print('❌ Error loading recent searches: $e');
      return [];
    }
  }

  // Очистить недавние поиски
  Future<void> clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSearchesKey);
      print('🗑️ Recent searches cleared');
    } catch (e) {
      print('❌ Error clearing recent searches: $e');
    }
  }
}
