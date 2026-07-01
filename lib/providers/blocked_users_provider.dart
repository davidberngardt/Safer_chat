// providers/blocked_users_provider.dart
import 'package:flutter/foundation.dart';

class BlockedUsersProvider extends ChangeNotifier {
  List<int> _blockedUsers = [];
  
  List<int> get blockedUsers => _blockedUsers;
  
  // Для хранения дополнительной информации о заблокированных пользователях
  Map<int, String> _blockedUserNames = {};
  
  // Блокировать пользователя
  void blockUser(int userId, String userName) {
    if (!_blockedUsers.contains(userId)) {
      _blockedUsers.add(userId);
      _blockedUserNames[userId] = userName;
      notifyListeners();
      _saveToStorage();
    }
  }
  
  // Разблокировать пользователя
  void unblockUser(int userId) {
    if (_blockedUsers.contains(userId)) {
      _blockedUsers.remove(userId);
      _blockedUserNames.remove(userId);
      notifyListeners();
      _saveToStorage();
    }
  }
  
  // Проверить, заблокирован ли пользователь
  bool isUserBlocked(int userId) {
    return _blockedUsers.contains(userId);
  }
  
  // Получить имя заблокированного пользователя
  String? getBlockedUserName(int userId) {
    return _blockedUserNames[userId];
  }
  
  // Загрузка из локального хранилища
  Future<void> loadFromStorage() async {
    // TODO: Реализовать загрузку из SharedPreferences или другой БД
    await Future.delayed(Duration(milliseconds: 100));
    
    // Пример загрузки
    _blockedUsers = [5, 8]; // Пример: пользователи с ID 5 и 8 заблокированы
    _blockedUserNames = {
      5: 'Алексей',
      8: 'Мария',
    };
    
    notifyListeners();
  }
  
  // Сохранение в локальное хранилище
  Future<void> _saveToStorage() async {
    // TODO: Реализовать сохранение в SharedPreferences или другую БД
    await Future.delayed(Duration(milliseconds: 100));
  }
}