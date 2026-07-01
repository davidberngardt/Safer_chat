import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'models/message.dart';
import 'package:uuid/uuid.dart';

class MediaService {
  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = Uuid();

  Future<List<XFile>> pickMultipleImages() async {
    try {
      final files = await _picker.pickMultiImage();
      return files;
    } catch (e) {
      print('Ошибка при выборе изображений: $e');
      rethrow;
    }
  }

  Future<XFile?> pickSingleImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      return file;
    } catch (e) {
      print('Ошибка при выборе изображения: $e');
      rethrow;
    }
  }

  // Обновленный метод для загрузки медиафайлов
  Future<List<Message>> uploadMediaFiles({
    required List<XFile> files,
    required String token,
    required String baseUrl,
    required int chatId,
    required int myUserId,
    String? text,
  }) async {
    final dio = Dio();
    dio.options.headers['Authorization'] = 'Bearer $token';

    List<Message> uploadedMessages = [];

    for (final file in files) {
      try {
        FormData formData;
        if (kIsWeb) {
          final bytes = await file.readAsBytes();
          formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(bytes, filename: file.name),
            'chat_id': chatId,
            'text': text ?? '', // Передаем только пользовательский текст
          });
        } else {
          formData = FormData.fromMap({
            'file': await MultipartFile.fromFile(file.path, filename: file.name),
            'chat_id': chatId,
            'text': text ?? '', // Передаем только пользовательский текст
          });
        }

        final response = await dio.post('$baseUrl/api/upload', data: formData);

        if (response.statusCode == 200) {
          final data = response.data;
          final message = Message(
            id: data['message_id'] ?? _uuid.v4().hashCode,
            userId: myUserId,
            text: text ?? '', // ИСПРАВЛЕНО: используем только пользовательский текст, не название файла
            createdAt: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
            fileUrl: data['file_url'],
            typeId: _getTypeIdFromFilename(file.name), // Определяем тип по расширению файла
          );
          uploadedMessages.add(message);
        } else {
          throw Exception('Ошибка загрузки файла: ${file.name}');
        }
      } catch (e) {
        print('Ошибка при загрузке файла ${file.name}: $e');
        rethrow;
      }
    }

    return uploadedMessages;
  }

  Future<Message> uploadSingleFile({
    required XFile file,
    required String token,
    required String baseUrl,
    required int chatId,
    required int myUserId,
  }) async {
    final dio = Dio();
    dio.options.headers['Authorization'] = 'Bearer $token';

    FormData formData;
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
        'chat_id': chatId,
      });
    } else {
      formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: file.name),
        'chat_id': chatId,
      });
    }

    final response = await dio.post('$baseUrl/api/upload', data: formData);

    if (response.statusCode == 200) {
      final data = response.data;
      return Message(
        id: data['message_id'] ?? _uuid.v4().hashCode,
        userId: myUserId,
        text: '', // ИСПРАВЛЕНО: не показываем название файла
        createdAt: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
        fileUrl: data['file_url'],
        typeId: _getTypeIdFromFilename(file.name),
      );
    } else {
      throw Exception('Ошибка загрузки файла: HTTP ${response.statusCode}');
    }
  }

  // Добавьте этот метод для определения типа файла
  int _getTypeIdFromFilename(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      return 2; // image
    } else if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'].contains(ext)) {
      return 5; // video
    } else if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(ext)) {
      return 4; // audio
    } else {
      return 6; // file
    }
  }
}