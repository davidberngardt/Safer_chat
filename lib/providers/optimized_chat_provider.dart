import 'dart:async';
import 'package:flutter/material.dart';
import 'package:safer_chat/services/api_service.dart';
import 'package:safer_chat/models/chat.dart';
import 'package:safer_chat/models/message.dart';

class OptimizedChatProvider extends ChangeNotifier {
  final ApiService apiService;
  final int userId;
  
  // Список чатов с пагинацией
  List<Chat> _chats = [];
  int _currentPage = 1;
  bool _hasMoreChats = true;
  bool _isLoadingChats = false;
  
  // Сообщения для каждого чата (кешированные)
  final Map<int, List<Message>> _chatMessages = {};
  final Map<int, int> _messagePages = {};
  final Map<int, bool> _hasMoreMessages = {};
  final Map<int, bool> _isLoadingMessages = {};
  
  // Поиск
  List<Chat> _searchResults = [];
  bool _isSearching = false;
  
  // Ошибки
  String? _lastError;
  
  // Статистика непрочитанных
  int _totalUnreadCount = 0;
  
  // Геттеры
  List<Chat> get chats => _chats;
  List<Chat> get searchResults => _searchResults;
  bool get isLoadingChats => _isLoadingChats;
  bool get isSearching => _isSearching;
  bool get hasMoreChats => _hasMoreChats;
  String? get lastError => _lastError;
  int get totalUnreadCount => _totalUnreadCount;
  
  OptimizedChatProvider({
    required this.apiService,
    required this.userId,
  });

  // ==================== ЧАТЫ ====================

  // Загрузка чатов (пагинированная)
  Future<bool> loadChats({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMoreChats = true;
      _chats.clear();
      _totalUnreadCount = 0;
    }
    
    if (_isLoadingChats || !_hasMoreChats) return false;
    
    _isLoadingChats = true;
    _lastError = null;
    notifyListeners();
    
    try {
      print('📱 Загрузка чатов: страница $_currentPage');
      
      final response = await apiService.get(
        '/chats/paginated?page=$_currentPage&limit=10',
      );
      
      if (response['success'] == true) {
        final List<dynamic> chatsJson = response['chats'] ?? [];
        
        for (var json in chatsJson) {
          // Конвертируем snake_case в camelCase для вашей модели
          final chat = Chat.regular(
            id: json['id'],
            title: json['title'] ?? 'Чат',
            lastMessage: json['last_message'],
            lastMessageTime: json['last_message_time'] != null 
                ? DateTime.parse(json['last_message_time']) 
                : null,
            unreadCount: json['unread_count'] ?? 0,
            participants: json['participants'] ?? [],
            isMuted: json['is_muted'] ?? false,
            isPinned: json['is_pinned'] ?? false,
            isArchived: false, // По умолчанию
            myUserId: userId,
            isBlocked: false,
            isChannel: json['is_channel'] ?? false,
            recipientUserId: json['recipient_user_id'],
            isGroup: json['is_group'] ?? false,
          );
          
          _chats.add(chat);
          _totalUnreadCount += chat.unreadCount;
        }
        
        _hasMoreChats = response['pagination']?['hasMore'] ?? false;
        if (_hasMoreChats) _currentPage++;
        
        print('✅ Загружено ${chatsJson.length} чатов, всего: ${_chats.length}');
        return true;
      } else {
        _lastError = response['error'] ?? 'Неизвестная ошибка';
        return false;
      }
      
    } on TimeoutException catch (e) {
      _lastError = 'Превышено время ожидания. Проверьте интернет.';
      print('❌ Timeout loading chats: $e');
      return false;
      
    } catch (e) {
      _lastError = 'Ошибка загрузки чатов: $e';
      print('❌ Error loading chats: $e');
      return false;
      
    } finally {
      _isLoadingChats = false;
      notifyListeners();
    }
  }

  // Поиск чатов
  Future<void> searchChats(String query) async {
    if (query.isEmpty) {
      _isSearching = false;
      _searchResults.clear();
      notifyListeners();
      return;
    }
    
    _isSearching = true;
    notifyListeners();
    
    try {
      // Фильтруем локально для быстроты
      _searchResults = _chats.where((chat) {
        return chat.title.toLowerCase().contains(query.toLowerCase());
      }).toList();
      
    } catch (e) {
      print('❌ Search error: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  // ==================== СООБЩЕНИЯ ====================

  // Получить сообщения чата (из кэша)
  List<Message> getMessages(int chatId) {
    return _chatMessages[chatId] ?? [];
  }

  // Загрузить сообщения чата
  Future<List<Message>> loadMessages(int chatId, {bool refresh = false}) async {
    if (refresh) {
      _chatMessages[chatId] = [];
      _messagePages[chatId] = 1;
      _hasMoreMessages[chatId] = true;
    }
    
    final currentPage = _messagePages[chatId] ?? 1;
    final hasMore = _hasMoreMessages[chatId] ?? true;
    
    if (_isLoadingMessages[chatId] == true || !hasMore) {
      return _chatMessages[chatId] ?? [];
    }
    
    _isLoadingMessages[chatId] = true;
    notifyListeners();
    
    try {
      print('📨 Загрузка сообщений чата $chatId: страница $currentPage');
      
      final response = await apiService.get(
        '/chat-messages?chat_id=$chatId&page=$currentPage&limit=20',
      );
      
      if (response['success'] == true) {
        final List<dynamic> messagesJson = response['messages'] ?? [];
        final newMessages = messagesJson.map((json) => Message.fromMap(json)).toList();
        
        final existingMessages = _chatMessages[chatId] ?? [];
        
        if (refresh) {
          _chatMessages[chatId] = newMessages;
        } else {
          // Добавляем старые сообщения в начало (для пагинации вверх)
          _chatMessages[chatId] = [...newMessages, ...existingMessages];
        }
        
        _hasMoreMessages[chatId] = response['pagination']?['hasMore'] ?? false;
        if (_hasMoreMessages[chatId]!) {
          _messagePages[chatId] = currentPage + 1;
        }
        
        print('✅ Загружено ${newMessages.length} сообщений для чата $chatId');
        return _chatMessages[chatId]!;
      }
      
      return _chatMessages[chatId] ?? [];
      
    } catch (e) {
      print('❌ Error loading messages for chat $chatId: $e');
      return _chatMessages[chatId] ?? [];
      
    } finally {
      _isLoadingMessages[chatId] = false;
      notifyListeners();
    }
  }

  // Добавить новое сообщение в чат (после отправки)
  void addMessage(int chatId, Message message) {
    final messages = _chatMessages[chatId] ?? [];
    messages.insert(0, message); // Новые сообщения в начало
    _chatMessages[chatId] = messages;
    
    // Обновляем последнее сообщение в чате
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      final updatedChat = _chats[chatIndex].copyWith(
        lastMessage: message.text,
        lastMessageTime: message.createdAt,
      );
      _chats[chatIndex] = updatedChat;
      
      // Перемещаем чат вверх
      final chat = _chats.removeAt(chatIndex);
      _chats.insert(0, chat);
    }
    
    notifyListeners();
  }

  // Обновить статус сообщения (для будущего использования)
  void updateMessageStatus(int chatId, int messageId, String status) {
    // В вашей модели Message нет поля status, поэтому пропускаем
    // Но можно добавить позже если нужно
  }

  // Пометить чат как прочитанный
  Future<void> markChatAsRead(int chatId) async {
    try {
      await apiService.post('/chats/$chatId/mark-read');
      
      // Обновляем счетчик непрочитанных
      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        _totalUnreadCount -= _chats[chatIndex].unreadCount;
        final updatedChat = _chats[chatIndex].copyWith(unreadCount: 0);
        _chats[chatIndex] = updatedChat;
        notifyListeners();
      }
      
    } catch (e) {
      print('❌ Error marking chat as read: $e');
    }
  }

  // ==================== УПРАВЛЕНИЕ ЧАТАМИ ====================

  // Закрепить чат
  Future<bool> togglePinChat(int chatId, bool pin) async {
    try {
      await apiService.patch('/chats/$chatId/pin', data: {'is_pinned': pin});
      
      final index = _chats.indexWhere((c) => c.id == chatId);
      if (index != -1) {
        final updatedChat = _chats[index].togglePin();
        _chats[index] = updatedChat;
        
        // Пересортировка
        _chats.sort((a, b) {
          if (a.isPinned && !b.isPinned) return -1;
          if (!a.isPinned && b.isPinned) return 1;
          return 0;
        });
        notifyListeners();
      }
      
      return true;
      
    } catch (e) {
      print('❌ Error toggling pin: $e');
      return false;
    }
  }

  // Включить/выключить звук
  Future<bool> toggleMuteChat(int chatId, bool mute) async {
    try {
      await apiService.patch('/chats/$chatId/mute', data: {'is_muted': mute});
      
      final index = _chats.indexWhere((c) => c.id == chatId);
      if (index != -1) {
        final updatedChat = _chats[index].toggleMute();
        _chats[index] = updatedChat;
        notifyListeners();
      }
      
      return true;
      
    } catch (e) {
      print('❌ Error toggling mute: $e');
      return false;
    }
  }

  // Архивировать чат
  Future<bool> archiveChat(int chatId) async {
    try {
      // Здесь должен быть API запрос
      // await apiService.post('/chats/$chatId/archive');
      
      final index = _chats.indexWhere((c) => c.id == chatId);
      if (index != -1 && _chats[index].canBeArchived) {
        final updatedChat = _chats[index].archive();
        _chats[index] = updatedChat;
        notifyListeners();
      }
      
      return true;
      
    } catch (e) {
      print('❌ Error archiving chat: $e');
      return false;
    }
  }

  // Восстановить из архива
  Future<bool> restoreChat(int chatId) async {
    try {
      // Здесь должен быть API запрос
      // await apiService.post('/chats/$chatId/restore');
      
      final index = _chats.indexWhere((c) => c.id == chatId);
      if (index != -1) {
        final updatedChat = _chats[index].restore();
        _chats[index] = updatedChat;
        notifyListeners();
      }
      
      return true;
      
    } catch (e) {
      print('❌ Error restoring chat: $e');
      return false;
    }
  }

  // Отправить сообщение
  Future<Map<String, dynamic>?> sendMessage(
    int chatId,
    String text, {
    int? replyToMessageId,
  }) async {
    try {
      final response = await apiService.post(
        '/send-message',
        data: {
          'chat_id': chatId,
          'text': text,
          if (replyToMessageId != null) 'reply_to': replyToMessageId,
        },
      );
      
      if (response['success'] == true) {
        // Создаем временное сообщение для немедленного отображения
        final tempMessage = Message.fromUser(
          id: response['message_id'] ?? DateTime.now().millisecondsSinceEpoch,
          userId: userId,
          text: text,
          createdAt: DateTime.now(),
        );
        
        addMessage(chatId, tempMessage);
        return response;
      }
      
      return null;
      
    } catch (e) {
      print('❌ Error sending message: $e');
      return null;
    }
  }

  // ==================== AI ЧАТЫ ====================

  // Создать AI чат
  void addAIChat(Chat aiChat) {
    if (!_chats.any((c) => c.id == aiChat.id)) {
      _chats.insert(0, aiChat);
      notifyListeners();
    }
  }

  // ==================== ОЧИСТКА ====================

  // Очистить кэш сообщений
  void clearMessagesCache() {
    _chatMessages.clear();
    _messagePages.clear();
    _hasMoreMessages.clear();
    _isLoadingMessages.clear();
  }

  // Сбросить всё (при логауте)
  void dispose() {
    _chats.clear();
    _chatMessages.clear();
    _messagePages.clear();
    _hasMoreMessages.clear();
    _isLoadingMessages.clear();
    _searchResults.clear();
    _currentPage = 1;
    _hasMoreChats = true;
    _totalUnreadCount = 0;
    _lastError = null;
  }
}