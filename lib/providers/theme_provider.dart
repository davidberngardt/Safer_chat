// lib/providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safer_chat/theme.dart';

class ThemeProvider with ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  
  bool _isDarkMode = false;

  ThemeProvider() {
    _loadTheme();
  }

  bool get isDarkMode => _isDarkMode;

  ThemeData get currentTheme {
    return _isDarkMode ? MessengerTheme.darkTheme() : MessengerTheme.lightTheme();
  }

  // Загружаем сохраненную тему
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_themeKey) ?? false;
      notifyListeners();
    } catch (e) {
      print('Ошибка загрузки темы: $e');
    }
  }

  // Сохраняем тему
  Future<void> _saveTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeKey, _isDarkMode);
    } catch (e) {
      print('Ошибка сохранения темы: $e');
    }
  }

  // Переключение темы
  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _saveTheme();
    notifyListeners();
  }

  // Установка конкретной темы
  Future<void> setTheme(bool isDark) async {
    _isDarkMode = isDark;
    await _saveTheme();
    notifyListeners();
  }
}