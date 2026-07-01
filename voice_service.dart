import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'models/message.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

enum RecordingState { idle, recording, paused, stopped }

class VoiceService {
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _audioPlayer = FlutterSoundPlayer();
  
  RecordingState _recordingState = RecordingState.idle;
  String? _currentRecordingPath;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  StreamSubscription? _playerSubscription;
  DateTime? _recordingStartTime;
  
  // Ограничение записи - 3 минуты
  static const int MAX_RECORDING_SECONDS = 180;
  
  // Геттеры для доступа к состоянию
  RecordingState get recordingState => _recordingState;
  String? get currentRecordingPath => _currentRecordingPath;
  int get recordingSeconds => _recordingSeconds;
  
  // Колбэки для обновления UI
  VoidCallback? onRecordingStateChanged;
  VoidCallback? onRecordingProgress;
  Function(bool)? onPlayingStateChanged;
  Function(int)? onPlayingMessageIdChanged;

  Future<void> initialize() async {
    try {
      if (!kIsWeb) {
        await Permission.microphone.request();
        await Permission.storage.request();
      }
      
      await _audioRecorder.openRecorder();
      await _audioPlayer.openPlayer();
      
    } catch (e) {
      print('Ошибка инициализации аудио: $e');
      rethrow;
    }
  }

  Future<void> startRecording() async {
    try {
      if (!kIsWeb) {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          throw Exception('Необходимо разрешение на использование микрофона');
        }
      }

      _recordingState = RecordingState.recording;
      _recordingSeconds = 0;
      _recordingStartTime = DateTime.now();
      _notifyStateChanged();

      if (kIsWeb) {
        await _audioRecorder.startRecorder(codec: Codec.opusWebM);
      } else {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.startRecorder(
          toFile: filePath,
          codec: Codec.aacMP4,
        );
        _currentRecordingPath = filePath;
      }

      // Исправленный таймер без скачков
      _recordingTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (_recordingStartTime != null) {
          final elapsed = DateTime.now().difference(_recordingStartTime!);
          final newSeconds = elapsed.inSeconds;
          
          if (newSeconds != _recordingSeconds) {
            _recordingSeconds = newSeconds;
            _notifyProgress();
            
            // Автоматическая остановка при достижении лимита
            if (_recordingSeconds >= MAX_RECORDING_SECONDS) {
              stopRecording();
            }
          }
        }
      });

    } catch (e) {
      print('Ошибка при начале записи: $e');
      _recordingState = RecordingState.idle;
      _recordingStartTime = null;
      _notifyStateChanged();
      rethrow;
    }
  }

  Future<void> pauseRecording() async {
    try {
      await _audioRecorder.pauseRecorder();
      _recordingState = RecordingState.paused;
      _notifyStateChanged();
      _recordingTimer?.cancel();
    } catch (e) {
      print('Ошибка при паузе записи: $e');
      rethrow;
    }
  }

  Future<void> resumeRecording() async {
    try {
      await _audioRecorder.resumeRecorder();
      _recordingState = RecordingState.recording;
      _recordingStartTime = DateTime.now().subtract(Duration(seconds: _recordingSeconds));
      _notifyStateChanged();
      
      _recordingTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (_recordingStartTime != null) {
          final elapsed = DateTime.now().difference(_recordingStartTime!);
          final newSeconds = elapsed.inSeconds;
          
          if (newSeconds != _recordingSeconds) {
            _recordingSeconds = newSeconds;
            _notifyProgress();
            
            // Автоматическая остановка при достижении лимита
            if (_recordingSeconds >= MAX_RECORDING_SECONDS) {
              stopRecording();
            }
          }
        }
      });
    } catch (e) {
      print('Ошибка при возобновлении записи: $e');
      rethrow;
    }
  }

  Future<void> stopRecording() async {
    try {
      if (kIsWeb) {
        final recordingPath = await _audioRecorder.stopRecorder();
        _currentRecordingPath = recordingPath;
      } else {
        await _audioRecorder.stopRecorder();
      }
      
      _recordingTimer?.cancel();
      _recordingStartTime = null;
      _recordingState = RecordingState.stopped;
      _notifyStateChanged();
    } catch (e) {
      print('Ошибка при остановке записи: $e');
      _recordingState = RecordingState.idle;
      _recordingStartTime = null;
      _notifyStateChanged();
      rethrow;
    }
  }

  Future<void> deleteRecording() async {
    try {
      if (!kIsWeb && _currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      _recordingState = RecordingState.idle;
      _currentRecordingPath = null;
      _recordingSeconds = 0;
      _recordingStartTime = null;
      _recordingTimer?.cancel();
      _notifyStateChanged();
    } catch (e) {
      print('Ошибка при удалении записи: $e');
      rethrow;
    }
  }

  Future<void> playVoiceMessage(Message message, int playingMessageId) async {
    if (message.fileUrl == null || message.fileUrl!.isEmpty) {
      throw Exception('URL голосового сообщения пустой');
    }

    // Останавливаем предыдущее воспроизведение
    if (_audioPlayer.isPlaying) {
      await _audioPlayer.stopPlayer();
      _playerSubscription?.cancel();
    }

    try {
      onPlayingStateChanged?.call(true);
      onPlayingMessageIdChanged?.call(message.id);

      final codec = kIsWeb ? Codec.opusWebM : Codec.aacMP4;
      
      await _audioPlayer.startPlayer(
        fromURI: message.fileUrl!,
        codec: codec,
      );

      _playerSubscription = _audioPlayer.onProgress?.listen((event) {
        if (event.duration != null && event.position >= event.duration!) {
          _stopPlaying();
        }
      });

    } catch (e) {
      print('Ошибка при воспроизведении: $e');
      _stopPlaying();
      rethrow;
    }
  }

  Future<void> stopPlaying() async {
    await _audioPlayer.stopPlayer();
    _playerSubscription?.cancel();
    onPlayingStateChanged?.call(false);
    onPlayingMessageIdChanged?.call(-1);
  }

  bool get isPlaying => _audioPlayer.isPlaying;

  // Обновленный метод для загрузки голосового сообщения
  Future<Message> uploadVoiceMessage({
    required String token,
    required String baseUrl,
    required int chatId,
    required int myUserId,
    required Duration duration,
  }) async {
    if (_currentRecordingPath == null) {
      throw Exception('Путь к записи не найден');
    }

    final dio = Dio();
    dio.options.headers['Authorization'] = 'Bearer $token';

    final file = File(_currentRecordingPath!);
    if (!await file.exists()) {
      throw Exception('Файл записи не найден: $_currentRecordingPath');
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        _currentRecordingPath!,
        filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      ),
      'chat_id': chatId.toString(),
      'type': 'voice',
      'duration': duration.inSeconds.toString(),
    });

    final response = await dio.post(
      '$baseUrl/api/upload', 
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: Duration(seconds: 30),
        receiveTimeout: Duration(seconds: 30),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.statusMessage}');
    }

    final data = response.data;
    return Message(
      id: data['message_id'] ?? const Uuid().v4().hashCode,
      userId: myUserId,
      text: 'Голосовое сообщение',
      createdAt: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
      fileUrl: data['file_url'],
      typeId: 4, // audio type
      duration: duration.inSeconds,
    );
  }

  void dispose() {
    _recordingTimer?.cancel();
    _playerSubscription?.cancel();
    _audioRecorder.closeRecorder();
    _audioPlayer.closePlayer();
  }

  void _notifyStateChanged() {
    onRecordingStateChanged?.call();
  }

  void _notifyProgress() {
    onRecordingProgress?.call();
  }

  void _stopPlaying() {
    _audioPlayer.stopPlayer();
    _playerSubscription?.cancel();
    onPlayingStateChanged?.call(false);
    onPlayingMessageIdChanged?.call(-1);
  }
}