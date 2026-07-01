import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_message.dart';

class AIChat {
  final String id;
  final String title;
  final String? displayTitle; // ИСПРАВЛЕНО: добавлено поле
  final String? lastMessage;
  final DateTime lastMessageTime;
  final bool isPinned;
  final DateTime createdAt;
  final bool isAIChat;
  final int userId;

  AIChat({
    required this.id,
    required this.title,
    this.displayTitle, // ИСПРАВЛЕНО: добавлено поле
    this.lastMessage,
    required this.lastMessageTime,
    this.isPinned = false,
    required this.createdAt,
    this.isAIChat = true,
    required this.userId,
  });

  AIChat copyWith({
    String? id,
    String? title,
    String? displayTitle,
    String? lastMessage,
    DateTime? lastMessageTime,
    bool? isPinned,
    DateTime? createdAt,
    bool? isAIChat,
    int? userId,
  }) {
    return AIChat(
      id: id ?? this.id,
      title: title ?? this.title,
      displayTitle: displayTitle ?? this.displayTitle,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      isAIChat: isAIChat ?? this.isAIChat,
      userId: userId ?? this.userId,
    );
  }

  factory AIChat.fromPostgres(Map<String, dynamic> data) {
    return AIChat(
      id: data['chat_id'],
      title: data['title'],
      displayTitle: data['display_title'], // ИСПРАВЛЕНО: используем поле с сервера
      lastMessage: data['last_message'],
      lastMessageTime: DateTime.parse(data['last_message_time']).toLocal(),
      isPinned: data['is_pinned'] ?? false,
      createdAt: DateTime.parse(data['created_at']).toLocal(),
      isAIChat: data['is_ai_chat'] ?? true,
      userId: data['user_id'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'displayTitle': displayTitle,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'isPinned': isPinned,
      'createdAt': createdAt.toIso8601String(),
      'isAIChat': isAIChat,
      'userId': userId,
    };
  }
}

class AIChatsProvider with ChangeNotifier {
  List<AIChat> _chats = [];
  bool _isLoading = false;
  final String _baseUrl;
  final String _token;
  final int _userId;

  AIChatsProvider({
    required String baseUrl,
    required String token,
    required int userId,
  }) : _baseUrl = baseUrl, _token = token, _userId = userId;

  List<AIChat> get chats => _chats;
  bool get isLoading => _isLoading;

  Map<String, String> get _headers {
    return {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };
  }

  Future<void> loadChats() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/ai/chats?user_id=$_userId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final chatsData = data['chats'] as List;
          
          _chats = chatsData.map((chatData) {
            return AIChat.fromPostgres(chatData);
          }).toList();

          print('📥 Загружено ${_chats.length} AI чатов из PostgreSQL');
        } else {
          throw Exception('Ошибка загрузки чатов: ${data['message']}');
        }
      } else {
        throw Exception('Ошибка HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Ошибка загрузки AI чатов из PostgreSQL: $e');
      await _loadChatsFromSharedPreferencesFallback();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadChatsFromSharedPreferencesFallback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatsJson = prefs.getString('ai_chats_$_userId') ?? '[]';
      final List<dynamic> chatsList = jsonDecode(chatsJson);
      
      _chats = chatsList.map((chatData) {
        return AIChat(
          id: chatData['id'],
          title: chatData['title'],
          displayTitle: chatData['displayTitle'],
          lastMessage: chatData['lastMessage'],
          lastMessageTime: DateTime.parse(chatData['lastMessageTime']),
          isPinned: chatData['isPinned'] ?? false,
          createdAt: DateTime.parse(chatData['createdAt']),
          isAIChat: chatData['isAIChat'] ?? true,
          userId: _userId,
        );
      }).toList();
      
      print('📥 Загружено ${_chats.length} AI чатов из SharedPreferences');
    } catch (e) {
      print('❌ Ошибка загрузки AI чатов из SharedPreferences: $e');
      _chats = [];
    }
  }

  Future<void> _saveChatsToSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatsJson = jsonEncode(_chats.map((chat) => chat.toMap()).toList());
      await prefs.setString('ai_chats_$_userId', chatsJson);
    } catch (e) {
      print('⚠️ Ошибка сохранения чатов в SharedPreferences: $e');
    }
  }

  Future<void> saveChatHistory(String chatId, List<AIMessage> messages) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/ai/messages/save-batch'),
        headers: _headers,
        body: jsonEncode({
          'messages': messages.where((msg) => !msg.isStreaming).map((msg) {
            return {
              'chat_id': chatId,
              'message_id': msg.id,
              'text': msg.text,
              'is_from_user': msg.isFromUser,
              'created_at': msg.createdAt.toUtc().toIso8601String(),
              'is_streaming': msg.isStreaming,
            };
          }).toList(),
          'user_id': _userId,
        }),
      );

      if (response.statusCode == 200) {
        print('💾 История чата сохранена в PostgreSQL: $chatId (${messages.length} сообщений)');
      } else {
        throw Exception('Ошибка сохранения истории: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Ошибка сохранения истории чата в PostgreSQL: $e');
      await _saveChatHistoryToSharedPreferences(chatId, messages);
    }
  }

  Future<void> _saveChatHistoryToSharedPreferences(String chatId, List<AIMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = jsonEncode(messages.map((msg) => msg.toMap()).toList());
      await prefs.setString('ai_chat_history_${chatId}_$_userId', messagesJson);
      print('💾 История сохранена в SharedPreferences: $chatId');
    } catch (e) {
      print('⚠️ Ошибка сохранения истории в SharedPreferences: $e');
    }
  }

  Future<List<AIMessage>> loadChatHistory(String chatId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/ai/messages/history?chat_id=$chatId&user_id=$_userId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final messages = data['messages'] as List;
          
          return messages.map((msg) {
            return AIMessage(
              id: msg['message_id']?.toString(),
              chatId: chatId,
              messageId: msg['message_id']?.toString() ?? '',
              text: msg['text'] ?? '',
              isFromUser: msg['is_from_user'],
              createdAt: DateTime.parse(msg['created_at']).toLocal(),
              isStreaming: msg['is_streaming'],
            );
          }).toList();
        }
      }
      
      return await _loadChatHistoryFromSharedPreferences(chatId);
    } catch (e) {
      print('❌ Ошибка загрузки истории чата из PostgreSQL: $e');
      return await _loadChatHistoryFromSharedPreferences(chatId);
    }
  }

  Future<List<AIMessage>> _loadChatHistoryFromSharedPreferences(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getString('ai_chat_history_${chatId}_$_userId') ?? '[]';
      final List<dynamic> messagesList = jsonDecode(messagesJson);
      
      return messagesList.map((msgData) {
        return AIMessage.fromMap(msgData);
      }).toList();
    } catch (e) {
      print('❌ Ошибка загрузки истории из SharedPreferences: $e');
      return [];
    }
  }

  Future<void> deleteChatHistory(String chatId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/ai/chats/delete?chat_id=$chatId&user_id=$_userId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        print('🗑️ Чат удален из PostgreSQL: $chatId');
      } else {
        print('⚠️ Ошибка удаления чата: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Ошибка удаления чата из PostgreSQL: $e');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_chat_history_${chatId}_$_userId');
  }

  // НОВЫЙ МЕТОД: Создать чат с первым сообщением как заголовком
  Future<void> createChatWithFirstMessage({
    required String chatId,
    required String firstMessage,
    required int userId,
  }) async {
    // Проверяем, существует ли уже такой чат
    final existingIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (existingIndex != -1) {
      print('⚠️ Чат $chatId уже существует, пропускаем создание');
      return;
    }

    final title = _extractFirstSentence(firstMessage);
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/ai/chats/save'),
        headers: _headers,
        body: jsonEncode({
          'chat_id': chatId,
          'title': title,
          'last_message': firstMessage,
          'is_pinned': false,
          'user_id': userId,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Создан AI чат $chatId с заголовком: $title');
        
        final newChat = AIChat(
          id: chatId,
          title: title,
          displayTitle: title,
          lastMessage: firstMessage,
          lastMessageTime: DateTime.now(),
          isPinned: false,
          createdAt: DateTime.now(),
          isAIChat: true,
          userId: userId,
        );
        
        _chats.insert(0, newChat);
        await _saveChatsToSharedPreferences();
        notifyListeners();
      } else {
        print('⚠️ Ошибка создания чата: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Ошибка создания чата в PostgreSQL: $e');
      
      // Fallback на локальное создание
      final title = _extractFirstSentence(firstMessage);
      final newChat = AIChat(
        id: chatId,
        title: title,
        displayTitle: title,
        lastMessage: firstMessage,
        lastMessageTime: DateTime.now(),
        isPinned: false,
        createdAt: DateTime.now(),
        isAIChat: true,
        userId: userId,
      );
      
      _chats.insert(0, newChat);
      await _saveChatsToSharedPreferences();
      notifyListeners();
    }
  }

  // СТАРЫЙ МЕТОД (оставляем для обратной совместимости)
  Future<void> createOrUpdateChat({
    required String chatId,
    required String title,
    String? lastMessage,
  }) async {
    // Проверяем, существует ли уже такой чат
    final existingIndex = _chats.indexWhere((chat) => chat.id == chatId);
    
    if (existingIndex != -1) {
      // Обновляем существующий чат
      _chats[existingIndex] = _chats[existingIndex].copyWith(
        title: title,
        lastMessage: lastMessage,
        lastMessageTime: DateTime.now(),
      );
      
      // Перемещаем в начало списка
      final chat = _chats.removeAt(existingIndex);
      _chats.insert(0, chat);
    } else {
      // Создаем новый чат
      final newChat = AIChat(
        id: chatId,
        title: title,
        displayTitle: title,
        lastMessage: lastMessage,
        lastMessageTime: DateTime.now(),
        isPinned: false,
        createdAt: DateTime.now(),
        isAIChat: true,
        userId: _userId,
      );
      
      _chats.insert(0, newChat);
    }
    
    // Сохраняем в PostgreSQL
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/ai/chats/save'),
        headers: _headers,
        body: jsonEncode({
          'chat_id': chatId,
          'title': title,
          'last_message': lastMessage ?? '',
          'is_pinned': false,
          'user_id': _userId,
        }),
      );

      if (response.statusCode != 200) {
        print('⚠️ Ошибка сохранения чата в PostgreSQL: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Ошибка сохранения чата в PostgreSQL: $e');
    }
    
    await _saveChatsToSharedPreferences();
    notifyListeners();
  }

  Future<void> renameChat(String chatId, String newTitle) async {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index != -1) {
      _chats[index] = _chats[index].copyWith(title: newTitle, displayTitle: newTitle);
      
      try {
        final response = await http.put(
          Uri.parse('$_baseUrl/api/ai/chats/rename'),
          headers: _headers,
          body: jsonEncode({
            'chat_id': chatId,
            'title': newTitle,
            'user_id': _userId,
          }),
        );

        if (response.statusCode != 200) {
          print('⚠️ Ошибка переименования чата: ${response.statusCode}');
        }
      } catch (e) {
        print('⚠️ Ошибка переименования чата в PostgreSQL: $e');
      }
      
      await _saveChatsToSharedPreferences();
      notifyListeners();
    }
  }

  Future<void> togglePin(String chatId) async {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index != -1) {
      final isCurrentlyPinned = _chats[index].isPinned;
      _chats[index] = _chats[index].copyWith(isPinned: !isCurrentlyPinned);
      
      try {
        final response = await http.put(
          Uri.parse('$_baseUrl/api/ai/chats/toggle-pin'),
          headers: _headers,
          body: jsonEncode({
            'chat_id': chatId,
            'is_pinned': !isCurrentlyPinned,
            'user_id': _userId,
          }),
        );

        if (response.statusCode != 200) {
          print('⚠️ Ошибка закрепления чата: ${response.statusCode}');
        }
      } catch (e) {
        print('⚠️ Ошибка закрепления чата в PostgreSQL: $e');
      }
      
      await _saveChatsToSharedPreferences();
      notifyListeners();
    }
  }

  Future<void> deleteChat(String chatId) async {
    await deleteChatHistory(chatId);
    
    _chats.removeWhere((chat) => chat.id == chatId);
    
    await _saveChatsToSharedPreferences();
    
    notifyListeners();
  }

  Future<void> updateLastMessage(String chatId, String message) async {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index != -1) {
      _chats[index] = _chats[index].copyWith(
        lastMessage: message,
        lastMessageTime: DateTime.now(),
      );
      
      final chat = _chats.removeAt(index);
      _chats.insert(0, chat);
      
      try {
        final response = await http.put(
          Uri.parse('$_baseUrl/api/ai/chats/update-last-message'),
          headers: _headers,
          body: jsonEncode({
            'chat_id': chatId,
            'last_message': message,
            'user_id': _userId,
          }),
        );

        if (response.statusCode != 200) {
          print('⚠️ Ошибка обновления последнего сообщения: ${response.statusCode}');
        }
      } catch (e) {
        print('⚠️ Ошибка обновления последнего сообщения в PostgreSQL: $e');
      }
      
      await _saveChatsToSharedPreferences();
      notifyListeners();
    }
  }

  String _extractFirstSentence(String text) {
    text = text.trim();
    
    final patterns = ['.', '!', '?', '\n', ';', ':'];
    int endIndex = text.length;
    
    for (var pattern in patterns) {
      final index = text.indexOf(pattern);
      if (index != -1 && index < endIndex) {
        endIndex = index;
      }
    }
    
    String firstSentence = endIndex < text.length ? 
        text.substring(0, endIndex + 1) : text;
    
    firstSentence = firstSentence.trim();
    firstSentence = firstSentence.replaceAll(RegExp(r'\s+'), ' ');
    
    if (firstSentence.length > 30) {
      return '${firstSentence.substring(0, 27).trim()}...';
    }
    
    return firstSentence.isNotEmpty ? firstSentence : 'Новый чат';
  }

  String generateNewChatId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(1000000);
    return 'ai_chat_${timestamp}_$random';
  }
}