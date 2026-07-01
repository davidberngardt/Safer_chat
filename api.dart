import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'models/message.dart';

class Api {
  static const String baseUrl = 'http://localhost:3000'; // твой сервер

  // Получение всех сообщений
  static Future<List<Message>> getMessages() async {
    final res = await http.get(Uri.parse('$baseUrl/messages'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      List<Message> messages = (data['messages'] as List)
          .map((e) => Message.fromJson(e))
          .toList();
      return messages;
    } else {
      throw Exception('Ошибка получения сообщений');
    }
  }

  // Отправка текста
  static Future<Map<String, dynamic>> sendMessage(String text) async {
    final res = await http.post(
      Uri.parse('$baseUrl/send-message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      throw Exception('Ошибка отправки сообщения');
    }
  }

  // Загрузка файла
  static Future<Map<String, dynamic>> uploadFile(File file) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    var response = await request.send();
    final resString = await response.stream.bytesToString();
    if (response.statusCode == 200) {
      return jsonDecode(resString);
    } else {
      throw Exception('Ошибка загрузки файла');
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
}
