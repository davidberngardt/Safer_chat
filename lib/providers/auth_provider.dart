import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  static const String _baseUrl = 'https://your-api.com';

  String? _token;
  String? _email;
  int? _userId;

  // =====================
  // GETTERS
  // =====================

  String? get token => _token;
  String? get email => _email;
  String? get userEmail => _email;
  int? get userId => _userId;

  bool get isAuthenticated => _token != null;

  // ✅ Регулярные выражения для валидации
  static const String _emailPattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';

  // =====================
  // INIT / STORAGE
  // =====================

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _email = prefs.getString('user_email');
    _userId = prefs.getInt('user_id');
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    if (_token != null) {
      await prefs.setString('auth_token', _token!);
    }
    if (_email != null) {
      await prefs.setString('user_email', _email!);
    }
    if (_userId != null) {
      await prefs.setInt('user_id', _userId!);
    }
  }

  // ✅ Санитизация входных данных
  String _sanitizeInput(String input) {
    // Удаляем управляющие символы и лишние пробелы
    return input.trim().replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  }

  // ✅ Валидация email
  bool _isValidEmail(String email) {
    return RegExp(_emailPattern).hasMatch(email);
  }

  // =====================
  // LEGACY METHODS
  // =====================

  void setAuthData(String token, String email, int userId) async {
    // ✅ Валидация email перед сохранением
    if (!_isValidEmail(email)) {
      throw Exception('Неверный формат email');
    }

    _token = token;
    _email = email;
    _userId = userId;

    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> clearAuthData() async {
    _token = null;
    _email = null;
    _userId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    notifyListeners();
  }

  // =====================
  // AUTH
  // =====================

  Future<void> login({
    required String email,
    required String password,
  }) async {
    // ✅ Санитизация и валидация на клиенте
    final cleanEmail = _sanitizeInput(email);
    final cleanPassword = _sanitizeInput(password);

    if (!_isValidEmail(cleanEmail)) {
      throw Exception('Неверный формат email');
    }

    if (cleanPassword.isEmpty) {
      throw Exception('Пароль не может быть пустым');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': cleanEmail,
        'password': cleanPassword,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Ошибка входа');
    }

    // ✅ Валидация ответа сервера
    final token = data['token']?.toString();
    final responseEmail = data['email']?.toString();
    final responseUserId = data['user_id'];

    if (token == null || token.isEmpty) {
      throw Exception('Сервер не вернул токен');
    }

    if (responseEmail == null || !_isValidEmail(responseEmail)) {
      throw Exception('Сервер вернул некорректный email');
    }

    if (responseUserId == null) {
      throw Exception('Сервер не вернул ID пользователя');
    }

    setAuthData(
      token,
      responseEmail,
      responseUserId is int ? responseUserId : int.tryParse(responseUserId.toString()) ?? 0,
    );
  }

  // =====================
  // EMAIL VERIFICATION
  // =====================

  Future<void> sendEmailVerificationCode(String newEmail) async {
    _ensureAuthenticated();

    // ✅ Санитизация и валидация
    final cleanEmail = _sanitizeInput(newEmail);
    if (!_isValidEmail(cleanEmail)) {
      throw Exception('Неверный формат email');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/auth/email/send-code'),
      headers: _authHeaders,
      body: jsonEncode({
        'email': cleanEmail,
      }),
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Не удалось отправить код');
    }
  }

  Future<void> verifyEmailCode(String code) async {
    _ensureAuthenticated();

    // ✅ Санитизация кода (только цифры)
    final cleanCode = _sanitizeInput(code).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleanCode.length != 4) {
      throw Exception('Код должен содержать 4 цифры');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/auth/email/verify'),
      headers: _authHeaders,
      body: jsonEncode({
        'code': cleanCode,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Неверный код');
    }

    if (data['email'] != null) {
      final newEmail = data['email'].toString();
      if (_isValidEmail(newEmail)) {
        _email = newEmail;
        await _saveToPrefs();
      }
    }

    notifyListeners();
  }

  // =====================
  // HELPERS
  // =====================

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  void _ensureAuthenticated() {
    if (_token == null) {
      throw Exception('Пользователь не авторизован');
    }
  }
}