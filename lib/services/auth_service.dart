import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../utils/platform_utils.dart'; // Добавлен импорт

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _refreshTokenKey = 'refresh_token';
  
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  // Сохраняем токен
  Future<void> saveToken(String token) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
      await saveUserDataFromToken(token);
    } catch (e) {
      print('Ошибка при сохранении токена: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await saveUserDataFromToken(token);
    }
  }
  
  // Сохраняем refresh токен
  Future<void> saveRefreshToken(String refreshToken) async {
    try {
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    } catch (e) {
      print('Ошибка при сохранении refresh токена: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
  }
  
  // Получаем токен
  Future<String?> getToken() async {
    try {
      String? token = await _secureStorage.read(key: _tokenKey);
      if (token != null) return token;
      
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      print('Ошибка при получении токена: $e');
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    }
  }
  
  // Получаем refresh токен
  Future<String?> getRefreshToken() async {
    try {
      String? refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (refreshToken != null) return refreshToken;
      
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_refreshTokenKey);
    } catch (e) {
      print('Ошибка при получении refresh токена: $e');
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_refreshTokenKey);
    }
  }
  
  // Получаем email пользователя
  Future<String?> getUserEmail() async {
    try {
      String? email = await _secureStorage.read(key: _userEmailKey);
      if (email != null) return email;
      
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userEmailKey);
    } catch (e) {
      print('Ошибка при получении email пользователя: $e');
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userEmailKey);
    }
  }
  
  // Удаляем токен (выход)
  Future<void> deleteToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _userIdKey);
      await _secureStorage.delete(key: _userEmailKey);
      await _secureStorage.delete(key: _refreshTokenKey);
    } catch (e) {
      print('Ошибка при удалении токена: $e');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_refreshTokenKey);
  }
  
  // Проверяем, авторизован ли пользователь
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
  
  // Проверяем, истек ли срок действия токена
  Future<bool> isTokenExpired() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return true;
    
    try {
      return JwtDecoder.isExpired(token);
    } catch (e) {
      print('Ошибка при проверке срока действия токена: $e');
      return true;
    }
  }
  
  // Получаем информацию о сроке действия токена
  Future<Map<String, dynamic>?> getTokenExpirationInfo() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    
    try {
      final expirationDate = JwtDecoder.getExpirationDate(token);
      final remainingTime = JwtDecoder.getRemainingTime(token);
      
      return {
        'expirationDate': expirationDate,
        'remainingTime': remainingTime,
        'isExpired': JwtDecoder.isExpired(token),
      };
    } catch (e) {
      print('Ошибка при получении информации о токене: $e');
      return null;
    }
  }
  
  // Получаем данные из токена
  Future<Map<String, dynamic>?> getTokenData() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    
    try {
      return JwtDecoder.decode(token);
    } catch (e) {
      print('Ошибка при декодировании токена: $e');
      return null;
    }
  }
  
  // Сохраняем user data из токена
  Future<void> saveUserDataFromToken(String token) async {
    try {
      final decoded = JwtDecoder.decode(token);
      final userId = decoded['userId']?.toString();
      final userEmail = decoded['email']?.toString();
      
      if (userId != null) {
        await _secureStorage.write(key: _userIdKey, value: userId);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userIdKey, userId);
      }
      
      if (userEmail != null && userEmail.isNotEmpty) {
        await _secureStorage.write(key: _userEmailKey, value: userEmail);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userEmailKey, userEmail);
      }
    } catch (e) {
      print('Ошибка при извлечении user data из токена: $e');
    }
  }
  
  // Сохраняем email отдельно
  Future<void> saveUserEmail(String email) async {
    if (email.isEmpty) return;
    
    try {
      await _secureStorage.write(key: _userEmailKey, value: email);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userEmailKey, email);
    } catch (e) {
      print('Ошибка при сохранении email: $e');
    }
  }
  
  // Получаем сохраненный userId
  Future<int?> getUserId() async {
    try {
      String? userIdStr = await _secureStorage.read(key: _userIdKey);
      if (userIdStr != null) return int.tryParse(userIdStr);
      
      final prefs = await SharedPreferences.getInstance();
      final userIdFromPrefs = prefs.getString(_userIdKey);
      return userIdFromPrefs != null ? int.tryParse(userIdFromPrefs) : null;
    } catch (e) {
      print('Ошибка при получении userId: $e');
      final prefs = await SharedPreferences.getInstance();
      final userIdFromPrefs = prefs.getString(_userIdKey);
      return userIdFromPrefs != null ? int.tryParse(userIdFromPrefs) : null;
    }
  }
  
  // Получаем все данные пользователя
  Future<Map<String, dynamic>?> getUserData() async {
    try {
      final tokenData = await getTokenData();
      final userId = await getUserId();
      final userEmail = await getUserEmail();
      
      return {
        'userId': userId,
        'email': userEmail,
        'tokenData': tokenData,
      };
    } catch (e) {
      print('Ошибка при получении данных пользователя: $e');
      return null;
    }
  }
  
  // Очистка всех данных аутентификации
  Future<void> clearAllAuthData() async {
    await deleteToken();
  }
  
  // Проверка валидности токена (не пустой и не истекший)
  Future<bool> isValidToken() async {
    if (!await isLoggedIn()) return false;
    return !(await isTokenExpired());
  }
}