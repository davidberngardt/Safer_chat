import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../models/message.dart';
import 'package:uuid/uuid.dart';
import '../utils/platform_utils.dart';

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

  // ✅ ИСПРАВЛЕНО: Добавлен метод для выбора любого файла
  Future<XFile?> pickAnyFile() async {
    try {
      final file = await _picker.pickMedia();
      return file;
    } catch (e) {
      print('Ошибка при выборе файла: $e');
      rethrow;
    }
  }

  // ✅ ИСПРАВЛЕНО: Добавлен метод для выбора нескольких файлов любого типа
  Future<List<XFile>> pickMultipleFiles() async {
    try {
      // На вебе pickMultiImage() работает только для изображений
      if (kIsWeb) {
        // Для веба используем отдельный подход через input[type=file]
        final file = await _picker.pickMedia();
        return file != null ? [file] : [];
      } else {
        // На мобильных устройствах можно использовать pickMultipleMedia если доступно
        // Но для кросс-платформенности используем pickMultiImage с ограничениями
        final files = await _picker.pickMultiImage();
        return files;
      }
    } catch (e) {
      print('Ошибка при выборе файлов: $e');
      rethrow;
    }
  }

  // ✅ ИСПРАВЛЕНО: Улучшенное определение типа файла
  int getTypeIdFromFilename(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    
    // Изображения
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif'].contains(ext)) {
      return 2; // image
    }
    // Видео
    else if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v', '3gp'].contains(ext)) {
      return 5; // video
    }
    // Аудио
    else if (['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma'].contains(ext)) {
      return 4; // audio
    }
    // Все остальные файлы
    else {
      return 6; // file
    }
  }

  // ✅ ИСПРАВЛЕНО: Улучшенная загрузка с правильным type_id
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
        
        // Определяем тип файла до загрузки
        final typeId = getTypeIdFromFilename(file.name);
        
        if (kIsWeb) {
          final bytes = await file.readAsBytes();
          formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(bytes, filename: file.name),
            'chat_id': chatId,
            'text': text ?? '',
            'type_id': typeId, // ✅ Добавляем type_id в запрос
          });
        } else {
          formData = FormData.fromMap({
            'file': await MultipartFile.fromFile(file.path, filename: file.name),
            'chat_id': chatId,
            'text': text ?? '',
            'type_id': typeId, // ✅ Добавляем type_id в запрос
          });
        }

        final response = await dio.post('$baseUrl/api/upload', data: formData);
        if (response.statusCode == 200) {
          final data = response.data;
          
          // ✅ ИСПРАВЛЕНИЕ: Безопасный парсинг даты
          DateTime createdAt;
          try {
            final dateString = data['created_at'] ?? data['createdat'] ?? data['createdAt'];
            createdAt = dateString != null ? DateTime.parse(dateString) : DateTime.now();
          } catch (e) {
            createdAt = DateTime.now();
          }
          
          // ✅ ИСПРАВЛЕНИЕ: Используем наш type_id если сервер не вернул правильный
          final serverTypeId = data['type_id'] ?? data['typeid'];
          final finalTypeId = serverTypeId != null 
              ? (serverTypeId is int ? serverTypeId : int.tryParse(serverTypeId.toString()) ?? typeId)
              : typeId;
          
          final message = Message(
            id: data['message_id'] ?? data['id'] ?? _uuid.v4().hashCode,
            userId: myUserId,
            text: text ?? '',
            createdAt: createdAt,
            fileUrl: data['file_url'] ?? data['fileurl'],
            typeId: finalTypeId,
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

  // ✅ ИСПРАВЛЕНО: Улучшенная загрузка одного файла
  Future<Message> uploadSingleFile({
    required XFile file,
    required String token,
    required String baseUrl,
    required int chatId,
    required int myUserId,
  }) async {
    final dio = Dio();
    dio.options.headers['Authorization'] = 'Bearer $token';

    // Определяем тип файла до загрузки
    final typeId = getTypeIdFromFilename(file.name);

    FormData formData;
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
        'chat_id': chatId,
        'type_id': typeId, // ✅ Добавляем type_id в запрос
      });
    } else {
      formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: file.name),
        'chat_id': chatId,
        'type_id': typeId, // ✅ Добавляем type_id в запрос
      });
    }

    final response = await dio.post('$baseUrl/api/upload', data: formData);
    if (response.statusCode == 200) {
      final data = response.data;
      
      // ✅ ИСПРАВЛЕНИЕ: Безопасный парсинг даты
      DateTime createdAt;
      try {
        final dateString = data['created_at'] ?? data['createdat'] ?? data['createdAt'];
        createdAt = dateString != null ? DateTime.parse(dateString) : DateTime.now();
      } catch (e) {
        createdAt = DateTime.now();
      }
      
      // ✅ ИСПРАВЛЕНИЕ: Используем наш type_id если сервер не вернул правильный
      final serverTypeId = data['type_id'] ?? data['typeid'];
      final finalTypeId = serverTypeId != null 
          ? (serverTypeId is int ? serverTypeId : int.tryParse(serverTypeId.toString()) ?? typeId)
          : typeId;
      
      return Message(
        id: data['message_id'] ?? data['id'] ?? _uuid.v4().hashCode,
        userId: myUserId,
        text: '',
        createdAt: createdAt,
        fileUrl: data['file_url'] ?? data['fileurl'],
        typeId: finalTypeId,
      );
    } else {
      throw Exception('Ошибка загрузки файла: HTTP ${response.statusCode}');
    }
  }
}