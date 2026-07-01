import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import '../models/message.dart';

enum RecordingState {
  idle,
  recording,
  stopped,
  error,
}

class VoiceService {
  late AudioRecorder _audioRecorder;
  late AudioPlayer _audioPlayer;
  RecordingState _recordingState = RecordingState.idle;
  String? _currentRecordingPath;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  
  // Callbacks
  VoidCallback? onRecordingStateChanged;
  VoidCallback? onRecordingProgress;
  ValueChanged<bool>? onPlayingStateChanged;
  ValueChanged<int?>? onPlayingMessageIdChanged;
  
  VoiceService() {
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();
    
    _setupAudioPlayerListeners();
  }
  
  void _setupAudioPlayerListeners() {
    _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      onPlayingStateChanged?.call(isPlaying);
      
      if (playerState.processingState == ProcessingState.completed) {
        onPlayingStateChanged?.call(false);
        onPlayingMessageIdChanged?.call(null);
        _playingMessageId = null;
      }
    });
    
    _audioPlayer.playbackEventStream.listen((event) {},
      onError: (error) {
        print('Ошибка воспроизведения аудио: $error');
        onPlayingStateChanged?.call(false);
        onPlayingMessageIdChanged?.call(null);
        _playingMessageId = null;
      }
    );
  }
  
  Future<void> initialize() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        print('Нет разрешения на использование микрофона');
        throw Exception('Разрешение на использование микрофона не предоставлено');
      }
      
    } catch (e) {
      print('Ошибка инициализации голосового сервиса: $e');
      _recordingState = RecordingState.error;
      rethrow;
    }
  }
  
  // ========== СОСТОЯНИЕ ЗАПИСИ ==========
  RecordingState get recordingState => _recordingState;
  String? get currentRecordingPath => _currentRecordingPath;
  int get recordingSeconds => _recordingSeconds;
  
  Future<bool> get hasVoiceMessage async {
    if (_recordingState != RecordingState.stopped || 
        _currentRecordingPath == null) {
      return false;
    }
    
    try {
      final file = File(_currentRecordingPath!);
      return await file.exists();
    } catch (e) {
      print('Ошибка проверки файла записи: $e');
      return false;
    }
  }
  
  // ========== ЗАПИСЬ ГОЛОСА ==========
  Future<void> startRecording() async {
    if (_recordingState == RecordingState.recording) {
      print('Запись уже идет');
      return;
    }
    
    try {
      // Останавливаем воспроизведение
      await stopPlaying();
      
      // Проверяем разрешение
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Нет разрешения на запись аудио');
      }
      
      // Создаем временный файл
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = path.join(tempDir.path, 'voice_$timestamp.m4a');
      
      // Настраиваем параметры записи
      final recordConfig = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      );
      
      await _audioRecorder.start(
        recordConfig,
        path: _currentRecordingPath!,
      );
      
      _recordingState = RecordingState.recording;
      _recordingSeconds = 0;
      
      // Запускаем таймер
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingSeconds++;
        onRecordingProgress?.call();
      });
      
      onRecordingStateChanged?.call();
      
    } catch (e) {
      print('Ошибка начала записи: $e');
      _recordingState = RecordingState.error;
      onRecordingStateChanged?.call();
      rethrow;
    }
  }
  
  Future<void> stopRecording() async {
    if (_recordingState != RecordingState.recording) {
      return;
    }
    
    try {
      print('Останавливаем запись...');
      
      final recordedPath = await _audioRecorder.stop();
      
      _recordingTimer?.cancel();
      _recordingTimer = null;
      
      if (recordedPath != null && recordedPath.isNotEmpty) {
        _currentRecordingPath = recordedPath;
        print('Запись сохранена в: $recordedPath');
      } else if (_currentRecordingPath != null) {
        print('Используем путь из памяти: $_currentRecordingPath');
      } else {
        print('Предупреждение: путь к записи не определен');
      }
      
      _recordingState = RecordingState.stopped;
      
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        final fileExists = await file.exists();
        final fileSize = fileExists ? await file.length() : 0;
        print('Файл записи: exists=$fileExists, size=${fileSize}bytes');
      }
      
      onRecordingStateChanged?.call();
      print('Запись успешно остановлена, длительность: $_recordingSeconds сек');
      
    } catch (e) {
      print('Ошибка остановки записи: $e');
      _recordingState = RecordingState.error;
      onRecordingStateChanged?.call();
      rethrow;
    }
  }
  
  Future<void> deleteRecording() async {
    
    _recordingTimer?.cancel();
    _recordingTimer = null;
    
    _recordingState = RecordingState.idle;
    _recordingSeconds = 0;
    
    if (_currentRecordingPath != null) {
      try {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
          print('Файл записи удален: $_currentRecordingPath');
        }
      } catch (e) {
        print('Ошибка удаления файла записи: $e');
      }
      _currentRecordingPath = null;
    }
    
    onRecordingStateChanged?.call();
  }
  
  // ========== ЗАГРУЗКА ГОЛОСОВОГО СООБЩЕНИЯ ==========
  Future<Message> uploadVoiceMessage({
    required String token,
    required String baseUrl,
    required int chatId,
    required int myUserId,
    required Duration duration,
  }) async {
    
    if (_currentRecordingPath == null) {
      throw Exception('Нет записи для отправки');
    }
    
    final file = File(_currentRecordingPath!);
    final fileExists = await file.exists();
    final fileSize = fileExists ? await file.length() : 0;
    
    print('Проверка файла: path=$_currentRecordingPath, exists=$fileExists, size=${fileSize}bytes');
    
    if (!fileExists || fileSize == 0) {
      throw Exception('Файл записи не найден или пуст');
    }
    
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };
      
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);
      dio.options.sendTimeout = const Duration(seconds: 30);
      
      final formData = FormData.fromMap({
        'chat_id': chatId,
        'duration': duration.inSeconds,
        'voice_file': await MultipartFile.fromFile(
          _currentRecordingPath!,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        ),
      });
      
      print('Отправляем запрос на сервер: $baseUrl/api/send-voice-message');
      
      final response = await dio.post(
        '$baseUrl/api/send-voice-message',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) {
            final progress = (sent / total * 100).toStringAsFixed(1);
            print('Прогресс загрузки: $progress%');
          }
        },
      );
      
      print('Ответ сервера: status=${response.statusCode}, data=${response.data}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        final message = Message(
          id: data['message_id'] ?? data['id'] ?? DateTime.now().millisecondsSinceEpoch,
          userId: myUserId,
          text: 'Голосовое сообщение',
          createdAt: DateTime.now(),
          fileUrl: data['file_url'] ?? data['fileUrl'],
          typeId: 4,
          duration: duration.inSeconds,
        );
        
        return message;
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode} - ${response.statusMessage}');
      }
    } catch (e) {
      print('Ошибка загрузки голосового сообщения: $e');
      if (e is DioException) {
        print('Dio error: ${e.response?.statusCode} - ${e.response?.data}');
      }
      rethrow;
    } finally {
      print('Очищаем запись после отправки...');
      await deleteRecording();
    }
  }
  
  // ========== ВОСПРОИЗВЕДЕНИЕ ГОЛОСОВЫХ СООБЩЕНИЙ ==========
  int? _playingMessageId;
  int? get playingMessageId => _playingMessageId;
  
  Future<void> playVoiceMessage(Message message, int messageId) async {
    try {
      // Если уже воспроизводится это же сообщение - ставим на паузу
      if (_audioPlayer.playing && _playingMessageId == messageId) {
        await _audioPlayer.pause();
        onPlayingStateChanged?.call(false);
        onPlayingMessageIdChanged?.call(null);
        _playingMessageId = null;
        return;
      }
      
      // Если воспроизводится другое сообщение - останавливаем
      if (_audioPlayer.playing) {
        await _audioPlayer.stop();
        _playingMessageId = null;
      }
      
      // Загружаем и воспроизводим аудио
      if (message.fileUrl != null && message.fileUrl!.isNotEmpty) {
        
        await _audioPlayer.setAudioSource(
          AudioSource.uri(Uri.parse(message.fileUrl!)),
        );
        
        await _audioPlayer.play();
        
        _playingMessageId = messageId;
        onPlayingStateChanged?.call(true);
        onPlayingMessageIdChanged?.call(messageId);
        
      } else {
        print('У сообщения нет ссылки на аудио файл');
        throw Exception('Аудио файл не найден');
      }
      
    } catch (e) {
      print('Ошибка воспроизведения голосового сообщения: $e');
      
      // Пробуем альтернативный способ для локальных файлов
      if (_currentRecordingPath != null && message.id.toString().contains('temp')) {
        await _playLocalFile(_currentRecordingPath!, messageId);
      } else {
        onPlayingStateChanged?.call(false);
        onPlayingMessageIdChanged?.call(null);
        _playingMessageId = null;
        rethrow;
      }
    }
  }
  
  Future<void> _playLocalFile(String filePath, int messageId) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await _audioPlayer.setFilePath(filePath);
        await _audioPlayer.play();
        
        _playingMessageId = messageId;
        onPlayingStateChanged?.call(true);
        onPlayingMessageIdChanged?.call(messageId);
        
      }
    } catch (e) {
      print('Ошибка воспроизведения локального файла: $e');
      onPlayingStateChanged?.call(false);
      onPlayingMessageIdChanged?.call(null);
      _playingMessageId = null;
      rethrow;
    }
  }
  
  Future<void> stopPlaying() async {
    try {
      await _audioPlayer.stop();
      onPlayingStateChanged?.call(false);
      onPlayingMessageIdChanged?.call(null);
      _playingMessageId = null;
    } catch (e) {
      print('Ошибка остановки воспроизведения: $e');
    }
  }
  
  Future<void> pausePlaying() async {
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        onPlayingStateChanged?.call(false);
      }
    } catch (e) {
      print('Ошибка паузы воспроизведения: $e');
    }
  }
  
  Future<void> resumePlaying() async {
    try {
      if (!_audioPlayer.playing && _playingMessageId != null) {
        await _audioPlayer.play();
        onPlayingStateChanged?.call(true);
      }
    } catch (e) {
      print('Ошибка возобновления воспроизведения: $e');
    }
  }
  
  // Получить текущую позицию воспроизведения
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  
  // Получить длительность текущего аудио
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  
  // Управление позицией воспроизведения
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      print('Ошибка перемотки: $e');
    }
  }
  
  // ========== ОЧИСТКА ==========
  void dispose() {
    print('Очистка голосового сервиса...');
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _recordingState = RecordingState.idle;
    _playingMessageId = null;
    print('Голосовой сервис очищен');
  }
  
  // ========== ПРОВЕРКА ДОСТУПНОСТИ ==========
  Future<bool> checkMicrophonePermission() async {
    try {
      return await _audioRecorder.hasPermission();
    } catch (e) {
      print('Ошибка проверки разрешения микрофона: $e');
      return false;
    }
  }
}