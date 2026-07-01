import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'models/message.dart';

class Api {
  static const String baseUrl = 'http://localhost:3004';
  static String? _authToken;

  // Установка токена авторизации
  static void setAuthToken(String token) {
    _authToken = token;
  }

  // Получение всех сообщений (с авторизацией)
  static Future<List<Message>> getMessages() async {
    final headers = {
      'Content-Type': 'application/json',
    };
    
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    
    final res = await http.get(
      Uri.parse('$baseUrl/api/chat-messages?chat_id=1'),
      headers: headers,
    );
    
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data['success'] == true) {
        List<Message> messages = (data['messages'] as List)
            .map((e) => Message.fromJson(e))
            .toList();
        return messages;
      } else {
        throw Exception(data['error'] ?? 'Ошибка получения сообщений');
      }
    } else {
      throw Exception('Ошибка сервера: ${res.statusCode}');
    }
  }

  // Отправка текста (с авторизацией)
  static Future<Map<String, dynamic>> sendMessage(String text) async {
    final headers = {
      'Content-Type': 'application/json',
    };
    
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    
    final res = await http.post(
      Uri.parse('$baseUrl/api/send-message'),
      headers: headers,
      body: jsonEncode({'text': text}),
    );
    
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } else {
      throw Exception('Ошибка отправки сообщения');
    }
  }

  // Загрузка файла (с авторизацией)
  static Future<Map<String, dynamic>> uploadFile(File file, {String? chatId}) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'));
    
    // Добавляем заголовок авторизации
    if (_authToken != null) {
      request.headers['Authorization'] = 'Bearer $_authToken';
    }
    
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    
    // Добавляем chat_id если есть
    if (chatId != null) {
      request.fields['chat_id'] = chatId;
    }
    
    var response = await request.send();
    final resString = await response.stream.bytesToString();
    
    if (response.statusCode == 200) {
      return jsonDecode(resString);
    } else {
      throw Exception('Ошибка загрузки файла: $resString');
    }
  }

  // Выбор файла
  static Future<File?> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  // Отправка обращения в поддержку
  static Future<Map<String, dynamic>> sendSupportTicket({
    required String name,
    required String message,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/support-ticket'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'name': name,
          'message': message,
        }),
      );

      final responseData = json.decode(utf8.decode(response.bodyBytes));
      
      if (response.statusCode == 200) {
        return responseData;
      } else {
        return {
          'success': false,
          'error': responseData['error'] ?? 'Неизвестная ошибка',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Регистрация
  static Future<Map<String, dynamic>> register(String email, String password, String verificationCode) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
        'verificationCode': verificationCode,
      }),
    );

    final responseData = json.decode(utf8.decode(response.bodyBytes));
    
    if (response.statusCode == 200 && responseData['success'] == true) {
      _authToken = responseData['token'];
    }
    
    return responseData;
  }

  // Логин
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
      }),
    );

    final responseData = json.decode(utf8.decode(response.bodyBytes));
    
    if (response.statusCode == 200 && responseData['success'] == true) {
      _authToken = responseData['token'];
    }
    
    return responseData;
  }

  // Отправка кода подтверждения
  static Future<Map<String, dynamic>> sendVerificationCode(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/send-verification-code'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );

    return json.decode(utf8.decode(response.bodyBytes));
  }

  // Проверка кода подтверждения
  static Future<Map<String, dynamic>> verifyEmailCode(String email, String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/verify-email-code'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'code': code}),
    );

    return json.decode(utf8.decode(response.bodyBytes));
  }

  // Выход
  static void logout() {
    _authToken = null;
  }
}