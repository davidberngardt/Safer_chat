import 'package:flutter/foundation.dart';
import '../services/ollama_service.dart';
import '../models/message.dart';

class ChatProvider with ChangeNotifier {
  final OllamaService ollamaService;
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;

  ChatProvider({required this.ollamaService});

  // Основной метод для отправки сообщения
  Future<void> sendMessage(String text, {required int userId}) async {
    if (text.isEmpty) return;

    // Сбрасываем ошибки
    _hasError = false;
    _errorMessage = null;

    // Создаем сообщение пользователя
    final userMessage = Message.fromUser(
      id: DateTime.now().millisecondsSinceEpoch,
      userId: userId,
      text: text,
    );
    
    _messages.add(userMessage);
    _isLoading = true;
    notifyListeners();

    try {
      // Получаем ответ от AI (теперь через Ollama)
      final botResponse = await ollamaService.getBotResponse(text);
      
      // Создаем сообщение AI (userId = -1)
      final botMessage = Message.fromAI(
        text: botResponse,
        id: DateTime.now().millisecondsSinceEpoch + 1,
      );
      
      _messages.add(botMessage);
      
    } catch (e) {
      // Обрабатываем ошибку
      _hasError = true;
      _errorMessage = 'Ошибка: $e';
      
      // Создаем сообщение об ошибке от AI
      final errorMessage = Message.fromAI(
        text: _getOllamaErrorMessage(e),
        id: DateTime.now().millisecondsSinceEpoch + 1,
      );
      _messages.add(errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Метод для получения понятного сообщения об ошибке Ollama
  String _getOllamaErrorMessage(dynamic e) {
    final errorString = e.toString();
    
    if (errorString.contains('Connection refused') || 
        errorString.contains('Failed host lookup')) {
      return 'Ошибка подключения к Ollama. Пожалуйста:\n'
          '1. Убедитесь, что Ollama установлен и запущен\n'
          '2. Проверьте, что сервер работает на localhost:11434\n'
          '3. Запустите Ollama вручную через терминал';
    } else if (errorString.contains('model') && errorString.contains('not found')) {
      return 'Модель OpenChat не найдена. Пожалуйста:\n'
          '1. Установите модель: ollama pull openchat:7b\n'
          '2. Перезапустите Ollama сервер';
    } else if (errorString.contains('timeout')) {
      return 'Таймаут ожидания ответа от Ollama. Модель может быть слишком медленной на вашем устройстве.\n'
          'Попробуйте использовать более легкую модель.';
    } else {
      return 'Извините, произошла ошибка при обработке запроса: $errorString\n'
          'Пожалуйста, попробуйте еще раз или перезапустите Ollama.';
    }
  }

  // Загрузка существующих сообщений (например, из БД)
  void loadMessages(List<Message> existingMessages) {
    _messages = List.from(existingMessages);
    notifyListeners();
  }

  // Добавление существующего сообщения
  void addMessage(Message message) {
    _messages.add(message);
    notifyListeners();
  }

  // Очистка чата
  void clearChat() {
    _messages.clear();
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  // Получение только AI сообщений
  List<Message> get aiMessages {
    return _messages.where((message) => message.isFromAI).toList();
  }

  // Получение только пользовательских сообщений
  List<Message> get userMessages {
    return _messages.where((message) => message.isFromUser).toList();
  }

  // Получение последнего сообщения
  Message? get lastMessage {
    return _messages.isEmpty ? null : _messages.last;
  }

  // Сброс ошибок
  void clearError() {
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  // Удаление сообщения по ID
  void removeMessage(int messageId) {
    _messages.removeWhere((message) => message.id == messageId);
    notifyListeners();
  }

  // Обновление сообщения
  void updateMessage(int messageId, String newText) {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index != -1) {
      final oldMessage = _messages[index];
      final updatedMessage = oldMessage.copyWith(text: newText);
      _messages[index] = updatedMessage;
      notifyListeners();
    }
  }

  // Новый метод: проверка доступности Ollama сервера
  Future<bool> checkOllamaConnection() async {
    try {
      // Простая проверка подключения к API
      final response = await ollamaService.getBotResponse('Привет');
      return response.isNotEmpty && !response.contains('Ошибка');
    } catch (e) {
      return false;
    }
  }
}