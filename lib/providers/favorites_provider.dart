import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/favorite_message.dart';
import 'package:safer_chat/generated/app_localizations.dart';

class FavoritesProvider with ChangeNotifier {
  List<FavoriteMessage> _favoriteMessages = [];
  int _nextId = 1;

  List<FavoriteMessage> get favoriteMessages => List.from(_favoriteMessages);

  void addFavoriteMessage({
    required int originalMessageId,
    required int chatId,
    required String chatTitle,
    required String text,
    required DateTime createdAt,
    String? fileUrl,
    required int typeId,
    int? duration,
    required int originalUserId,
  }) {
    final message = FavoriteMessage.fromMessage(
      id: _nextId++,
      originalMessageId: originalMessageId,
      chatId: chatId,
      chatTitle: chatTitle,
      text: text,
      createdAt: createdAt,
      fileUrl: fileUrl,
      typeId: typeId,
      duration: duration,
      originalUserId: originalUserId,
    );
    
    _favoriteMessages.insert(0, message);
    notifyListeners();
    
    // Здесь можно сохранить в локальную БД
  }

  void removeFavoriteMessage(int id) {
    _favoriteMessages.removeWhere((msg) => msg.id == id);
    notifyListeners();
    
    // Здесь можно удалить из локальной БД
  }

  bool isMessageFavorite(int originalMessageId) {
    return _favoriteMessages.any((msg) => msg.originalMessageId == originalMessageId);
  }

  void clearAllFavorites() {
    _favoriteMessages.clear();
    notifyListeners();
  }
}