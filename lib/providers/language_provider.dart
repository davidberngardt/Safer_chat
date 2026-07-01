import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  Locale? _currentLocale;
  final List<VoidCallback> _onLanguageChangedCallbacks = [];
  
  // Список поддерживаемых языков
  static const List<String> _supportedLanguages = ['ru', 'en', 'es', 'zh', 'ko', 'de', 'fr', 'it', 'ja', 'hi', 'ar', 'he'];

  Locale get currentLocale {
    return _currentLocale ?? const Locale('ru');
  }

  Future<void> initialize() async {
    await _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('language_code') ?? 'ru';
      
      final validCode = _supportedLanguages.contains(languageCode) ? languageCode : 'ru';
      
      _currentLocale = Locale(validCode);
    } catch (e) {
      print('LanguageProvider: ошибка загрузки языка: $e');
      _currentLocale = const Locale('ru');
    }
  }

  Future<void> setLanguage(String languageCode) async {
    print('Текущий язык: ${_currentLocale?.languageCode}');
    
    // Проверяем поддерживается ли язык
    if (!_supportedLanguages.contains(languageCode)) {
      print('LanguageProvider: язык $languageCode не поддерживается');
      return;
    }
    
    // Проверяем, не тот же ли язык уже установлен
    if (_currentLocale?.languageCode == languageCode) {
      print('LanguageProvider: язык уже установлен, пропускаем');
      return;
    }
    
    // Сохраняем в SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language_code', languageCode);
      print('LanguageProvider: язык сохранен в SharedPreferences: $languageCode');
    } catch (e) {
      print('LanguageProvider: ошибка сохранения в SharedPreferences: $e');
      return;
    }
    
    // Обновляем в памяти
    _currentLocale = Locale(languageCode);
    
    // Даем небольшое время на обновление
    await Future.delayed(const Duration(milliseconds: 10));
    
    // Уведомляем слушателей
    notifyListeners();
    
    // Уведомляем callback'и
    for (final callback in _onLanguageChangedCallbacks) {
      try {
        callback();
      } catch (e) {
        print('LanguageProvider: ошибка в callback: $e');
      }
    }
  }

  // Добавляем обратно метод getCurrentLanguage
  Future<String> getCurrentLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString('language_code') ?? 'ru';
      return _supportedLanguages.contains(savedCode) ? savedCode : 'ru';
    } catch (e) {
      print('LanguageProvider: ошибка получения языка: $e');
      return 'ru';
    }
  }

  // Добавляем остальные методы, которые могут быть нужны
  void addOnLanguageChangedCallback(VoidCallback callback) {
    if (!_onLanguageChangedCallbacks.contains(callback)) {
      _onLanguageChangedCallbacks.add(callback);
    }
  }

  void removeOnLanguageChangedCallback(VoidCallback callback) {
    _onLanguageChangedCallbacks.remove(callback);
    print('LanguageProvider: callback удален, осталось: ${_onLanguageChangedCallbacks.length}');
  }
  
  List<String> getSupportedLanguages() => _supportedLanguages;
  
  List<Locale> getSupportedLocales() {
    return _supportedLanguages.map((code) => Locale(code)).toList();
  }
  
  bool isLanguageSupported(String languageCode) {
    return _supportedLanguages.contains(languageCode);
  }
}