import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_message.dart';

enum QueryType {
  currency,
  weather,
  joke,
  country,
  crypto,
  quote,
  animal,
  design,
  general
}

class AIChatProvider with ChangeNotifier {
  List<AIMessage> _messages = [];
  bool _isLoading = false;
  String _currentStreamingMessageId = '';
  String _currentStreamingText = '';
  String _currentChatId = '';
  int _userId = 0;
  
  // Настройки Ollama
  final String _ollamaUrl = 'http://localhost:11434';
  final String _model = 'messenger-assistant';
  
  // PostgreSQL сервис параметры
  final String _baseUrl;
  final String _token;
  
  Map<String, String> get _headers {
    return {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };
  }
  
  // История диалога для контекста
  final List<Map<String, String>> _conversationHistory = [];

  // Конструктор
  AIChatProvider({
    required String baseUrl,
    required String token,
    required int userId,
  }) : _baseUrl = baseUrl, _token = token, _userId = userId;

  List<AIMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String get currentStreamingText => _currentStreamingText;

  // ========== ЗАГРУЗКА ИСТОРИИ ИЗ POSTGRESQL ==========
  Future<void> loadMessagesFromPostgres(String chatId) async {
    _currentChatId = chatId;
    
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/ai/messages/history?chat_id=$chatId&user_id=$_userId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final messages = data['messages'] as List;
          
          _messages.clear();
          _conversationHistory.clear();
          
          for (final msg in messages) {
            final message = AIMessage(
              id: msg['message_id']?.toString(),
              chatId: _currentChatId,
              messageId: msg['message_id']?.toString() ?? '',
              text: msg['text'] ?? '',
              isFromUser: msg['is_from_user'],
              createdAt: DateTime.parse(msg['created_at']).toLocal(),
              isStreaming: msg['is_streaming'],
            );
            
            _messages.add(message);
            _addToHistory(
              message.isFromUser ? 'user' : 'assistant',
              message.text,
            );
          }
          
          notifyListeners();
        }
      }
    } catch (e) {
      print('❌ Ошибка загрузки сообщений из PostgreSQL: $e');
      rethrow;
    }
  }

  // ========== МЕТОД ДЛЯ ЗАГРУЗКИ ИЗ ЛОКАЛЬНОГО СПИСКА (FALLBACK) ==========
  void loadMessages(List<AIMessage> messages) {
    _messages = List.from(messages);
    _conversationHistory.clear();
    
    for (final msg in _messages) {
      _addToHistory(
        msg.isFromUser ? 'user' : 'assistant',
        msg.text,
      );
    }
    
    notifyListeners();
  }

  // ========== УНИВЕРСАЛЬНЫЙ МЕТОД ДЛЯ ПРОКСИ ==========
  Future<dynamic> _proxyRequest(String url, {bool returnRaw = false}) async {
    try {
      final encodedUrl = Uri.encodeComponent(url);
      final proxyUrl = Uri.parse('$_baseUrl/api/proxy?url=$encodedUrl');
      
      final response = await http.get(
        proxyUrl,
        headers: _headers,
      ).timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          if (returnRaw) {
            return result;
          }
          return result['data'];
        }
      }
      
      print('⚠️ Прокси вернул ошибку: ${response.statusCode}');
      return null;
    } catch (e) {
      print('❌ Ошибка прокси: $e');
      return null;
    }
  }

  // ========== ОСНОВНОЙ МЕТОД ОТПРАВКИ ==========
  Future<void> sendMessage(String text, {required int userId, required String chatId}) async {
    if (_isLoading) {
      print('Предотвращена повторная отправка: isLoading=true');
      return;
    }
    
    _currentChatId = chatId;
    _userId = userId;
    
    _addToHistory('user', text);
    
    // Создаем сообщение пользователя
    final userMessage = AIMessage.fromUser(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
      text: text,
      createdAt: DateTime.now(),
    );
    
    // Добавляем в UI
    _messages.add(userMessage.copyWith(chatId: _currentChatId));
    notifyListeners();
    
    // ✅ ИСПРАВЛЕНО: СОХРАНЯЕМ СООБЩЕНИЕ ПОЛЬЗОВАТЕЛЯ
    await _saveMessageToPostgres(userMessage.copyWith(chatId: _currentChatId));
    
    final QueryType queryType = _determineQueryType(text);
    
    try {
      switch (queryType) {
        case QueryType.currency:
          await _handleCurrencyQuery(text);
          break;
        case QueryType.weather:
          await _handleWeatherQuery(text);
          break;
        case QueryType.joke:
          await _handleJokeQuery(text);
          break;
        case QueryType.country:
          await _handleCountryQuery(text);
          break;
        case QueryType.crypto:
          await _handleCryptoQuery(text);
          break;
        case QueryType.quote:
          await _handleQuoteQuery(text);
          break;
        case QueryType.animal:
          await _handleAnimalQuery(text);
          break;
        case QueryType.design:
          await _handleDesignQuery(text);
          break;
        case QueryType.general:
        default:
          await _getAIResponse(text);
          break;
      }
    } catch (e) {
      print('❌ Ошибка при обработке запроса: $e');
      _isLoading = false;
      _currentStreamingMessageId = '';
      _currentStreamingText = '';
      notifyListeners();
      
      final errorMessage = AIMessage.fromAI(
        id: 'error_${DateTime.now().millisecondsSinceEpoch}',
        text: '⚠️ Произошла ошибка при обработке запроса. Попробуйте еще раз.',
        createdAt: DateTime.now(),
        isStreaming: false,
      );
      
      _messages.add(errorMessage.copyWith(chatId: _currentChatId));
      notifyListeners();
      _saveMessageToPostgres(errorMessage);
    }
  }

  // ========== СОХРАНЕНИЕ В POSTGRESQL ==========
  Future<void> _saveMessageToPostgres(AIMessage message) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/ai/messages/save'),
        headers: _headers,
        body: jsonEncode({
          'chat_id': _currentChatId,
          'message_id': message.id,
          'text': message.text,
          'is_from_user': message.isFromUser,
          'created_at': message.createdAt.toUtc().toIso8601String(),
          'is_streaming': message.isStreaming,
          'user_id': _userId,
        }),
      );

      if (response.statusCode == 200) {
        print('💾 Сообщение сохранено: ${message.id} (${message.isFromUser ? "пользователь" : "ИИ"})');
      } else {
        print('⚠️ Ошибка сохранения сообщения: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Ошибка сохранения сообщения в PostgreSQL: $e');
    }
  }

  // ========== ОБРАБОТЧИКИ ЗАПРОСОВ ==========

  Future<void> _handleWeatherQuery(String query) async {
    await _startStreamingMessage();
    
    try {
      final city = _extractCityFromQuery(query);
      
      if (city == null) {
        await _addTextFastTypingEffect('❌ Я не понял, для какого города вы хотите узнать погоду. Укажите город, например: "погода в Москве" или "сколько градусов в Питере".');
        _finishStreamingMessage();
        return;
      }
      
      print('🌤️ Запрашиваю погоду для города: $city');
      final weather = await _getWeatherData(city);
      await _addTextFastTypingEffect(weather);
      _finishStreamingMessage();
      
    } catch (e) {
      print('❌ Ошибка погоды: $e');
      await _addTextFastTypingEffect('❌ Не удалось получить данные о погоде. Попробуйте позже.');
      _finishStreamingMessage();
    }
  }

  Future<void> _handleCurrencyQuery(String query) async {
    await _startStreamingMessage();
    
    try {
      final currencyData = await _getCurrencyRates();
      
      if (currencyData != null) {
        final response = _formatCurrencyResponse(query, currencyData);
        await _addTextFastTypingEffect(response);
      } else {
        await _addTextFastTypingEffect('❌ Не удалось получить курсы валют. Попробуйте позже.');
      }
      
      _finishStreamingMessage();
    } catch (e) {
      print('❌ Ошибка валют: $e');
      await _addTextFastTypingEffect('❌ Ошибка получения курсов валют.');
      _finishStreamingMessage();
    }
  }

  Future<void> _handleJokeQuery(String query) async {
    await _startStreamingMessage();
    
    try {
      final joke = await _getJokeData();
      await _addTextFastTypingEffect(joke);
      _finishStreamingMessage();
    } catch (e) {
      print('❌ Ошибка шутки: $e');
      await _addTextFastTypingEffect('😄 Почему программисты не рассказывают анекдоты в шестнадцатеричной системе? Потому что у них F по юмору!');
      _finishStreamingMessage();
    }
  }

  Future<void> _handleCountryQuery(String query) async {
    await _startStreamingMessage();
    
    try {
      final country = _extractCountryFromQuery(query) ?? 'russia';
      final info = await _getCountryInfo(country);
      await _addTextFastTypingEffect(info);
      _finishStreamingMessage();
    } catch (e) {
      print('❌ Ошибка страны: $e');
      await _addTextFastTypingEffect('❌ Не удалось получить информацию о стране.');
      _finishStreamingMessage();
    }
  }

  Future<void> _handleCryptoQuery(String query) async {
    await _startStreamingMessage();
    
    try {
      final crypto = _extractCryptoFromQuery(query) ?? 'BTCRUB';
      final price = await _getCryptoPrice(crypto);
      await _addTextFastTypingEffect(price);
      _finishStreamingMessage();
    } catch (e) {
      print('❌ Ошибка крипты: $e');
      await _addTextFastTypingEffect('❌ Не удалось получить данные о криптовалюте.');
      _finishStreamingMessage();
    }
  }

  Future<void> _handleQuoteQuery(String query) async {
    await _startStreamingMessage();
    
    try {
      final quote = await _getRandomQuote();
      await _addTextFastTypingEffect(quote);
      _finishStreamingMessage();
    } catch (e) {
      print('❌ Ошибка цитаты: $e');
      await _addTextFastTypingEffect('📜 "Единственный способ сделать великую работу — любить то, что вы делаете." — Стив Джобс');
      _finishStreamingMessage();
    }
  }

  Future<void> _handleAnimalQuery(String query) async {
    await _startStreamingMessage();
    
    try {
      final isCat = query.toLowerCase().contains('кот') || 
                    query.toLowerCase().contains('cat');
      
      final animalInfo = isCat ? 
          await _getCatImage() : 
          await _getDogImage();
      
      await _addTextFastTypingEffect(animalInfo);
      _finishStreamingMessage();
    } catch (e) {
      print('❌ Ошибка животного: $e');
      await _addTextFastTypingEffect('🐱 Представьте самого милого котика! (Фото временно недоступно)');
      _finishStreamingMessage();
    }
  }

  Future<void> _handleDesignQuery(String query) async {
    await _startStreamingMessage();
    
    try {
      final designInfo = await _getDesignAdvice(query);
      await _addTextFastTypingEffect(designInfo);
      _finishStreamingMessage();
    } catch (e) {
      print('❌ Ошибка дизайна: $e');
      await _addTextFastTypingEffect('🏠 Я могу помочь с советами по дизайну. Уточните, пожалуйста, параметры помещения.');
      _finishStreamingMessage();
    }
  }

  // ========== API МЕТОДЫ (все через прокси) ==========

  Future<String> _getWeatherData(String city) async {
    try {
      final geoUrl = 'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=ru&format=json';
      final geoResult = await _proxyRequest(geoUrl);
      
      if (geoResult == null) {
        print('❌ geoResult = null');
        return '❌ Не удалось найти город.';
      }
      
      if (geoResult['results'] == null || geoResult['results'].isEmpty) {
        print('❌ results пустой или null');
        return '❌ Город не найден.';
      }
      
      final location = geoResult['results'][0];
      final lat = location['latitude'];
      final lon = location['longitude'];
      final cityName = location['name'] ?? city;
      final country = location['country'] ?? 'Неизвестно';
      
      final weatherUrl = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&timezone=auto';
      final weatherResult = await _proxyRequest(weatherUrl);
      
      if (weatherResult == null || weatherResult['current_weather'] == null) {
        return '❌ Не удалось получить данные о погоде.';
      }
      
      final weatherCodes = {
        0: 'Ясно',
        1: 'Преимущественно ясно',
        2: 'Переменная облачность',
        3: 'Пасмурно',
        45: 'Туман',
        48: 'Иней',
        51: 'Легкая морось',
        53: 'Умеренная морось',
        55: 'Сильная морось',
        56: 'Легкий ледяной дождь',
        57: 'Сильный ледяной дождь',
        61: 'Небольшой дождь',
        63: 'Умеренный дождь',
        65: 'Сильный дождь',
        66: 'Легкий ледяной дождь',
        67: 'Сильный ледяной дождь',
        71: 'Небольшой снег',
        73: 'Умеренный снег',
        75: 'Сильный снег',
        77: 'Снежная крупа',
        80: 'Легкий ливень',
        81: 'Умеренный ливень',
        82: 'Сильный ливень',
        85: 'Небольшой снегопад',
        86: 'Сильный снегопад',
        95: 'Гроза',
        96: 'Гроза с градом',
        99: 'Сильная гроза с градом'
      };
      
      final current = weatherResult['current_weather'];
      final weatherDesc = weatherCodes[current['weathercode']] ?? 'Неизвестно';
      final windDir = _getWindDirection(current['winddirection']);
      
      final now = DateTime.now();
      final formattedDate = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
      
      return '''🌤️ **Погода в $cityName, $country:**
          
🌡️ Температура: ${current['temperature']}°C
💨 Ветер: ${current['windspeed']} км/ч $windDir
📝 $weatherDesc

🕐 Обновлено: $formattedDate
*Данные: Open-Meteo.com*''';
      
    } catch (e) {
      print('⚠️ Ошибка погоды: $e');
      return '❌ Ошибка при запросе погоды.';
    }
  }

  String _getWindDirection(num degrees) {
    if (degrees >= 337.5 || degrees < 22.5) return '⬆️ (С)';
    if (degrees >= 22.5 && degrees < 67.5) return '↗️ (СВ)';
    if (degrees >= 67.5 && degrees < 112.5) return '➡️ (В)';
    if (degrees >= 112.5 && degrees < 157.5) return '↘️ (ЮВ)';
    if (degrees >= 157.5 && degrees < 202.5) return '⬇️ (Ю)';
    if (degrees >= 202.5 && degrees < 247.5) return '↙️ (ЮЗ)';
    if (degrees >= 247.5 && degrees < 292.5) return '⬅️ (З)';
    if (degrees >= 292.5 && degrees < 337.5) return '↖️ (СЗ)';
    return '';
  }

  Future<Map<String, dynamic>?> _getCurrencyRates() async {
    final url = 'https://www.cbr-xml-daily.ru/daily_json.js';
    return await _proxyRequest(url);
  }

  Future<String> _getJokeData() async {
    final url = 'https://v2.jokeapi.dev/joke/Any?lang=ru&type=single';
    final result = await _proxyRequest(url);
    
    if (result != null && result['error'] == false) {
      return '🎭 **Шутка из категории "${result['category']}":**\n\n"${result['joke']}"\n\n😄';
    }
    
    final fallbackJokes = [
      'Почему программист всегда мокрый? Потому что он постоянно в потоках! 💻',
      'Что сказал один бит другому? "Давай встретимся на шоссе!" 🛣️',
    ];
    return '🎭 **Случайная шутка:**\n\n"${fallbackJokes[Random().nextInt(fallbackJokes.length)]}"\n\n😄';
  }

  Future<String> _getCountryInfo(String countryName) async {
    final url = 'https://restcountries.com/v3.1/name/${countryName.toLowerCase()}';
    final result = await _proxyRequest(url);
    
    if (result == null || result is! List || result.isEmpty) {
      return '❌ Не удалось найти информацию о стране.';
    }
    
    try {
      final data = result[0];
      return '''🇺🇳 **${data['name']['common']}**
        
🏛️ Официальное название: ${data['name']['official']}
📍 Столица: ${data['capital']?[0] ?? 'нет данных'}
👥 Население: ${_formatNumber(data['population'])}
🗺️ Регион: ${data['region']}
📏 Площадь: ${_formatNumber(data['area'])} км²
💬 Языки: ${data['languages']?.values.join(', ') ?? 'нет данных'}
💰 Валюта: ${data['currencies']?.values.first['name'] ?? 'нет данных'}''';
    } catch (e) {
      return '❌ Ошибка обработки данных о стране.';
    }
  }

  Future<String> _getCryptoPrice(String symbol) async {
    final url = 'https://api.binance.com/api/v3/ticker/price?symbol=${symbol.toUpperCase()}';
    final result = await _proxyRequest(url);
    
    if (result == null || result['price'] == null) {
      return '❌ Не удалось получить данные о криптовалюте.';
    }
    
    try {
      final price = double.parse(result['price']).toStringAsFixed(2);
      final cryptoName = symbol.replaceAll('RUB', '').replaceAll('USDT', '');
      
      return '''💰 **${cryptoName.toUpperCase()}**
        
💸 Цена: $price ₽
🕐 Данные Binance

💡 Курс может меняться каждую секунду.''';
    } catch (e) {
      return '❌ Ошибка обработки данных.';
    }
  }

  Future<String> _getRandomQuote() async {
    final url = 'https://api.quotable.io/random';
    final result = await _proxyRequest(url);
    
    if (result != null && result['content'] != null) {
      return '''📜 **"${result['content']}"**
        
✍️ — ${result['author']}''';
    }
    
    return '''📜 **"Единственный способ сделать великую работу — любить то, что вы делаете."**
        
✍️ — Стив Джобс''';
  }

  Future<String> _getCatImage() async {
    final url = 'https://api.thecatapi.com/v1/images/search';
    final result = await _proxyRequest(url);
    
    if (result != null && result is List && result.isNotEmpty) {
      return '🐱 **Случайный котик!**\n\n🖼️ ${result[0]['url']}\n\n😻 *Нажмите на ссылку, чтобы увидеть фото*';
    }
    return '🐱 **Вот котик!** 😻 (Фото временно недоступно)';
  }

  Future<String> _getDogImage() async {
    final url = 'https://dog.ceo/api/breeds/image/random';
    final result = await _proxyRequest(url);
    
    if (result != null && result['message'] != null) {
      return '🐶 **Случайная собачка!**\n\n🖼️ ${result['message']}\n\n🐕 *Нажмите на ссылку, чтобы увидеть фото*';
    }
    return '🐶 **Вот собачка!** 🐕 (Фото временно недоступно)';
  }

  Future<String> _getDesignAdvice(String query) async {
    try {
      final areaMatch = RegExp(r'(\d+)\s*(метр|м²|кв\.?м|квадратных)').firstMatch(query.toLowerCase());
      final area = areaMatch?.group(1) ?? '30';
      
      String roomType = 'студии';
      if (query.toLowerCase().contains('квартир')) roomType = 'квартиры';
      if (query.toLowerCase().contains('офис')) roomType = 'офиса';
      
      return '''🏠 **Советы по проектированию $roomType площадью $area м²:**

📐 **Планировка:**
• Разделите на функциональные зоны
• Используйте модульную мебель

🎨 **Дизайн:**
• Светлые тона расширяют пространство
• Зеркала создают глубину

💡 **Рекомендации:**
• Минимум 30% свободной площади
• Трансформируемая мебель

📝 *Уточните стиль и бюджет для деталей.*''';
    } catch (e) {
      return '🏠 Уточните площадь и тип помещения.';
    }
  }

  // ========== AI ОТВЕТ ==========

  Future<void> _getAIResponse(String userMessage) async {
    _isLoading = true;
    _currentStreamingMessageId = 'ai_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
    _currentStreamingText = '';
    
    final streamingMessage = AIMessage.fromAI(
      id: _currentStreamingMessageId,
      text: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );
    
    _messages.add(streamingMessage.copyWith(chatId: _currentChatId));
    notifyListeners();

    try {
      await _getResponseFromOllama(userMessage);
    } catch (e) {
      print('❌ Ошибка Ollama: $e');
      _handleOllamaError(e);
    }
  }

  void _handleOllamaError(dynamic e) {
    _isLoading = false;
    
    final messageIndex = _messages.indexWhere((m) => m.id == _currentStreamingMessageId);
    if (messageIndex != -1) {
      _messages.removeAt(messageIndex);
    }
    
    String errorMessageText = '⚠️ Произошла ошибка. Попробуйте позже.';
    
    if (e.toString().contains('Connection refused')) {
      errorMessageText = '🔌 Не удалось подключиться к AI-модели. Убедитесь, что Ollama запущен.';
    }
    
    final errorMessage = AIMessage.fromAI(
      id: 'error_${DateTime.now().millisecondsSinceEpoch}',
      text: errorMessageText,
      createdAt: DateTime.now(),
      isStreaming: false,
    );
    
    _messages.add(errorMessage.copyWith(chatId: _currentChatId));
    _currentStreamingMessageId = '';
    _currentStreamingText = '';
    notifyListeners();
  }

  Future<void> _getResponseFromOllama(String userMessage) async {
    try {
      final detectedLanguage = _detectLanguage(userMessage);
      final prompt = _formatPrompt(userMessage, detectedLanguage);
      
      final response = await http.post(
        Uri.parse('$_ollamaUrl/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _model.trim(),
          'prompt': prompt,
          'stream': true,
          'options': {
            'temperature': 0.7,
            'top_p': 0.9,
            'num_predict': 800,
            'repeat_penalty': 1.1,
          }
        }),
      ).timeout(Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Ошибка сервера Ollama: ${response.statusCode}');
      }

      final utf8Response = utf8.decode(response.bodyBytes);
      final lines = utf8Response.split('\n');
      bool hasContent = false;
      
      _currentStreamingText = '';
      String textBuffer = '';
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        try {
          final jsonResponse = jsonDecode(line);
          final responseText = jsonResponse['response']?.toString() ?? '';
          final done = jsonResponse['done'] == true;
          
          if (responseText.isNotEmpty) {
            hasContent = true;
            textBuffer += responseText;
            
            if (done || textBuffer.length >= 20) {
              if (textBuffer.isNotEmpty) {
                await _addTextFastTypingEffect(textBuffer);
                textBuffer = '';
              }
            }
          }
          
          if (done) {
            if (textBuffer.isNotEmpty) {
              await _addTextFastTypingEffect(textBuffer);
            }
            break;
          }
        } catch (e) {
          continue;
        }
      }
      
      if (!hasContent) {
        throw Exception('Пустой ответ от Ollama');
      }
      
      _addToHistory('assistant', _currentStreamingText);
      _completeStreamingMessage();
      
    } catch (e) {
      print('❌ Ошибка в _getResponseFromOllama: $e');
      rethrow;
    }
  }

  // ========== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ==========

  String _formatNumber(num value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), 
      (m) => '${m[1]} '
    );
  }

  String _detectLanguage(String text) {
    final russianChars = RegExp(r'[а-яА-ЯёЁ]').allMatches(text).length;
    final englishChars = RegExp(r'[a-zA-Z]').allMatches(text).length;
    return russianChars >= englishChars ? 'russian' : 'english';
  }

  String _formatPrompt(String userMessage, String language) {
    return language == 'russian' ?
      '''Ты — полезный AI ассистент в мессенджере. Отвечай на русском языке кратко и по делу (3-4 предложения).

Запрос пользователя: $userMessage

Твой ответ:''' :
      '''You are a helpful AI assistant in a messenger. Respond in English concisely (3-4 sentences).

User query: $userMessage

Your response:''';
  }

  String? _extractCityFromQuery(String query) {
    final lowerQuery = query.toLowerCase();
    
    final knownCities = {
      'москва': 'Москва',
      'питер': 'Санкт-Петербург',
      'санкт-петербург': 'Санкт-Петербург',
      'ленинград': 'Санкт-Петербург',
      'спб': 'Санкт-Петербург',
      'петербург': 'Санкт-Петербург',
      'новосибирск': 'Новосибирск',
      'екатеринбург': 'Екатеринбург',
      'казань': 'Казань',
      'нижний новгород': 'Нижний Новгород',
    };
    
    for (final entry in knownCities.entries) {
      if (lowerQuery.contains(entry.key)) {
        print('✅ Найден город по списку: ${entry.key} -> ${entry.value}');
        return entry.value;
      }
    }
    
    final patterns = [
      RegExp(r'погод[ау]\s+в\s+([а-яА-ЯёЁ\-]+)'),
      RegExp(r'погод[ау]\s+([а-яА-ЯёЁ\-]+)'),
      RegExp(r'в\s+([а-яА-ЯёЁ\-]+)\s+погод'),
      RegExp(r'([а-яА-ЯёЁ\-]+)\s+погод'),
      RegExp(r'температур[ау]\s+в\s+([а-яА-ЯёЁ\-]+)'),
      RegExp(r'сколько\s+градусов\s+в\s+([а-яА-ЯёЁ\-]+)'),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(lowerQuery);
      if (match != null && match.group(1) != null) {
        final city = match.group(1)!;
        final cleanCity = _cleanCityName(city);
        print('✅ Найден город по паттерну: $city -> $cleanCity');
        return cleanCity;
      }
    }
    
    print('❌ Город не найден в запросе: "$query"');
    return null;
  }

  String _cleanCityName(String cityWithCase) {
    final cityMappings = {
      'москве': 'Москва',
      'москвой': 'Москва',
      'москву': 'Москва',
      'питере': 'Санкт-Петербург',
      'питером': 'Санкт-Петербург',
      'питер': 'Санкт-Петербург',
      'петербурге': 'Санкт-Петербург',
      'петербургом': 'Санкт-Петербург',
      'петербург': 'Санкт-Петербург',
      'казани': 'Казань',
      'казанью': 'Казань',
    };
    
    final lower = cityWithCase.toLowerCase();
    
    if (cityMappings.containsKey(lower)) {
      return cityMappings[lower]!;
    }
    
    if (lower.endsWith('е') && lower.length > 3) {
      final base = lower.substring(0, lower.length - 1);
      if (base == 'москв') return 'Москва';
      if (base == 'питер') return 'Санкт-Петербург';
      if (base == 'петербург') return 'Санкт-Петербург';
      return base[0].toUpperCase() + base.substring(1);
    }
    
    if (cityWithCase.isNotEmpty) {
      return cityWithCase[0].toUpperCase() + cityWithCase.substring(1);
    }
    
    return cityWithCase;
  }

  String? _extractCountryFromQuery(String query) {
    final countries = {
      'россия': 'russia', 'сша': 'usa', 'германия': 'germany',
      'франция': 'france', 'китай': 'china', 'япония': 'japan'
    };
    
    for (final entry in countries.entries) {
      if (query.toLowerCase().contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _extractCryptoFromQuery(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('биткоин') || lower.contains('btc')) return 'BTCRUB';
    if (lower.contains('эфириум') || lower.contains('eth')) return 'ETHRUB';
    return null;
  }

  String _formatCurrencyResponse(String query, Map<String, dynamic> data) {
    try {
      final usd = data['Valute']['USD'];
      final eur = data['Valute']['EUR'];
      
      return '''📊 **Курсы валют ЦБ РФ**

💵 Доллар США: ${(usd['Value'] as num).toStringAsFixed(2)} ₽
💶 Евро: ${(eur['Value'] as num).toStringAsFixed(2)} ₽

🕐 Данные Центрального банка РФ

Есть вопросы по другим валютам?''';
    } catch (e) {
      return '❌ Ошибка обработки курсов валют.';
    }
  }

  // ========== УПРАВЛЕНИЕ СООБЩЕНИЯМИ ==========

  Future<void> _startStreamingMessage() async {
    _isLoading = true;
    _currentStreamingMessageId = 'api_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
    _currentStreamingText = '';
    
    final streamingMessage = AIMessage.fromAI(
      id: _currentStreamingMessageId,
      text: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );
    
    _messages.add(streamingMessage.copyWith(chatId: _currentChatId));
    notifyListeners();
  }

  void _finishStreamingMessage() {
    _addToHistory('assistant', _currentStreamingText);
    _completeStreamingMessage();
  }

  Future<void> _addTextFastTypingEffect(String text) async {
    if (text.isEmpty) return;
    
    if (text.length <= 10) {
      _currentStreamingText += text;
      _updateCurrentMessage();
      return;
    }
    
    final runes = text.runes.toList();
    
    for (int i = 0; i < runes.length; i++) {
      _currentStreamingText += String.fromCharCode(runes[i]);
      
      if (i % 5 == 0) {
        _updateCurrentMessage();
      }
      
      if (i < runes.length - 1) {
        await Future.delayed(Duration(milliseconds: 2 + Random().nextInt(5)));
      }
    }
    
    _updateCurrentMessage();
  }

  void _updateCurrentMessage() {
    final messageIndex = _messages.indexWhere((m) => m.id == _currentStreamingMessageId);
    if (messageIndex != -1) {
      _messages[messageIndex] = _messages[messageIndex].copyWith(
        text: _currentStreamingText,
        chatId: _currentChatId,
      );
      notifyListeners();
    }
  }

  void _addToHistory(String role, String content) {
    _conversationHistory.add({'role': role, 'content': content});
    if (_conversationHistory.length > 15) {
      _conversationHistory.removeAt(0);
    }
  }

  void _completeStreamingMessage() {
    _isLoading = false;
    
    final messageIndex = _messages.indexWhere((m) => m.id == _currentStreamingMessageId);
    if (messageIndex != -1) {
      _messages[messageIndex] = _messages[messageIndex].copyWith(
        isStreaming: false,
        chatId: _currentChatId,
      );
      
      if (!_messages[messageIndex].isStreaming) {
        _saveMessageToPostgres(_messages[messageIndex]);
      }
    }
    
    _currentStreamingMessageId = '';
    _currentStreamingText = '';
    notifyListeners();
  }

  QueryType _determineQueryType(String text) {
    final lowerText = text.toLowerCase().trim();
    
    if (lowerText.contains('курс') && (lowerText.contains('доллар') || lowerText.contains('евро'))) 
      return QueryType.currency;
    if (lowerText.contains('погода') && !lowerText.contains('дизайн')) 
      return QueryType.weather;
    if (lowerText.contains('шутк') || lowerText.contains('анекдот')) 
      return QueryType.joke;
    if (lowerText.contains('страна') || lowerText.contains('столица')) 
      return QueryType.country;
    if (lowerText.contains('биткоин') || lowerText.contains('крипт')) 
      return QueryType.crypto;
    if (lowerText.contains('цитат')) 
      return QueryType.quote;
    if (lowerText.contains('котик') || lowerText.contains('собака')) 
      return QueryType.animal;
    if (lowerText.contains('дизайн') || lowerText.contains('студи')) 
      return QueryType.design;
    
    return QueryType.general;
  }

  void clearMessages() {
    _messages.clear();
    _conversationHistory.clear();
    notifyListeners();
  }

  void loadFromMap(List<Map<String, dynamic>> messagesMap) {
    _messages = messagesMap.map((map) => AIMessage.fromMap(map)).toList();
    for (final msg in _messages) {
      _addToHistory(msg.isFromUser ? 'user' : 'assistant', msg.text);
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> getMessagesAsMap() {
    return _messages
        .where((msg) => !msg.isStreaming)
        .map((msg) => msg.toMap())
        .toList();
  }
}