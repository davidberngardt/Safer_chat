import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

enum ConnectionQuality {
  unknown,
  excellent, // WiFi или очень быстрый мобильный интернет
  good,       // Хороший 4G/5G
  fair,       // Средний 3G/4G
  poor,       // Плохое соединение (2G/Edge)
  offline     // Нет соединения
}

class ConnectionQualityService extends ChangeNotifier {
  static final ConnectionQualityService _instance = ConnectionQualityService._internal();
  factory ConnectionQualityService() => _instance;
  ConnectionQualityService._internal();

  final Connectivity _connectivity = Connectivity();
  final _qualityController = StreamController<ConnectionQuality>.broadcast();
  
  Stream<ConnectionQuality> get qualityStream => _qualityController.stream;
  
  ConnectionQuality _currentQuality = ConnectionQuality.unknown;
  ConnectionQuality get currentQuality => _currentQuality;
  
  // Для измерения задержки
  Timer? _measurementTimer;
  final List<int> _latencySamples = [];
  static const int maxSamples = 5;
  
  // Для мониторинга
  bool _isMonitoring = false;
  ConnectivityResult? _lastConnectivityResult;
  
  // Статистика
  int _totalMeasurements = 0;
  int _failedMeasurements = 0;
  double? _averageLatency;
  
  double? get averageLatency => _averageLatency;
  int get totalMeasurements => _totalMeasurements;
  
  // События для UI
  final _bannerController = StreamController<String>.broadcast();
  Stream<String> get onBannerMessage => _bannerController.stream;

  Future<void> initialize() async {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    
    // Начальное определение по типу соединения
    await _updateFromConnectivity();
    
    // Слушаем изменения типа соединения
    _connectivity.onConnectivityChanged.listen((results) {
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      _lastConnectivityResult = result;
      _updateFromConnectivity();
    });
    
    // Запускаем измерение задержки
    _startLatencyMeasurement();
    
    print('✅ ConnectionQualityService initialized');
  }

  Future<void> _updateFromConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    
    ConnectionQuality newQuality;
    
    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
        newQuality = ConnectionQuality.excellent;
        break;
        
      case ConnectivityResult.mobile:
        // Для мобильных нужно более точное определение через latency
        newQuality = ConnectionQuality.good; // По умолчанию
        break;
        
      case ConnectivityResult.bluetooth:
      case ConnectivityResult.other:
        newQuality = ConnectionQuality.fair;
        break;
        
      case ConnectivityResult.none:
        newQuality = ConnectionQuality.offline;
        break;
        
      case ConnectivityResult.vpn:
        newQuality = ConnectionQuality.excellent;
        break;
        
      case ConnectivityResult.satellite:
        newQuality = ConnectionQuality.fair;
        break;
        
      default:
        newQuality = ConnectionQuality.unknown;
        break;
    }
    
    _updateQuality(newQuality);
  }

  void _startLatencyMeasurement() {
    _measurementTimer?.cancel();
    _measurementTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _measureLatency();
    });
    
    // Первое измерение сразу
    _measureLatency();
  }

  Future<void> _measureLatency() async {
    // Не измеряем, если нет интернета
    if (_currentQuality == ConnectionQuality.offline) {
      return;
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Пингуем несколько известных быстрых серверов
      final servers = [
        'https://www.google.com/generate_204',
        'https://www.cloudflare.com/cdn-cgi/trace',
        'https://www.apple.com/library/test/success.html',
      ];
      
      // Выбираем случайный сервер для распределения нагрузки
      final server = servers[Random().nextInt(servers.length)];
      
      final response = await http.get(
        Uri.parse(server),
        headers: {
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ).timeout(const Duration(seconds: 5));
      
      stopwatch.stop();
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        final latency = stopwatch.elapsedMilliseconds;
        _totalMeasurements++;
        
        _latencySamples.add(latency);
        if (_latencySamples.length > maxSamples) {
          _latencySamples.removeAt(0);
        }
        
        // Усредняем
        if (_latencySamples.isNotEmpty) {
          _averageLatency = _latencySamples.reduce((a, b) => a + b) / _latencySamples.length;
          
          // Корректируем качество на основе задержки
          _adjustQualityBasedOnLatency(_averageLatency!);
        }
        
        print('📶 Latency: ${latency}ms, avg: ${_averageLatency?.toStringAsFixed(0)}ms');
      } else {
        _failedMeasurements++;
      }
      
    } catch (e) {
      _failedMeasurements++;
      print('⚠️ Latency measurement failed: $e');
      
      // Если много ошибок подряд, возможно проблемы с сетью
      if (_failedMeasurements > 3) {
        _updateQuality(ConnectionQuality.poor);
      }
    }
  }

  void _adjustQualityBasedOnLatency(double latency) {
    // Если уже офлайн, не меняем
    if (_currentQuality == ConnectionQuality.offline) return;
    
    ConnectionQuality newQuality;
    
    if (latency < 100) {
      newQuality = ConnectionQuality.excellent;
    } else if (latency < 200) {
      newQuality = ConnectionQuality.good;
    } else if (latency < 500) {
      newQuality = ConnectionQuality.fair;
    } else {
      newQuality = ConnectionQuality.poor;
    }
    
    // Для мобильных сетей корректируем с учетом типа соединения
    if (_lastConnectivityResult == ConnectivityResult.mobile) {
      if (newQuality == ConnectionQuality.excellent) {
        newQuality = ConnectionQuality.good; // На мобильных never say perfect
      }
    }
    
    _updateQuality(newQuality);
  }

  void _updateQuality(ConnectionQuality quality) {
    if (_currentQuality != quality) {
      final oldQuality = _currentQuality;
      _currentQuality = quality;
      
      print('📶 Connection quality changed: $oldQuality -> $quality');
      
      // Уведомляем подписчиков
      _qualityController.add(quality);
      notifyListeners();
      
      // Показываем баннер при ухудшении
      if (quality == ConnectionQuality.poor && oldQuality != ConnectionQuality.poor) {
        _bannerController.add('Медленное соединение');
      } else if (quality == ConnectionQuality.offline && oldQuality != ConnectionQuality.offline) {
        _bannerController.add('Нет подключения к интернету');
      } else if (quality == ConnectionQuality.excellent && 
                 (oldQuality == ConnectionQuality.poor || oldQuality == ConnectionQuality.offline)) {
        _bannerController.add('Соединение восстановлено');
      }
    }
  }

  // ==================== ПУБЛИЧНЫЕ МЕТОДЫ ====================

  // Рекомендуемое качество изображений
  ImageQuality getRecommendedImageQuality() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
        return ImageQuality.high;
      case ConnectionQuality.good:
        return ImageQuality.medium;
      case ConnectionQuality.fair:
      case ConnectionQuality.poor:
        return ImageQuality.low;
      default:
        return ImageQuality.medium;
    }
  }

  // Нужно ли предзагружать медиа
  bool get shouldPreloadMedia {
    return _currentQuality == ConnectionQuality.excellent ||
           _currentQuality == ConnectionQuality.good;
  }

  // Таймаут для запросов (в миллисекундах)
  int getRequestTimeout() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
        return 5000;
      case ConnectionQuality.good:
        return 10000;
      case ConnectionQuality.fair:
        return 20000;
      case ConnectionQuality.poor:
        return 30000;
      case ConnectionQuality.offline:
        return 1000; // Быстрый таймаут при офлайн
      default:
        return 15000;
    }
  }

  // Максимальный размер файла для авто-загрузки (в байтах)
  int getAutoDownloadMaxSize() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
        return 50 * 1024 * 1024; // 50 MB
      case ConnectionQuality.good:
        return 20 * 1024 * 1024; // 20 MB
      case ConnectionQuality.fair:
        return 5 * 1024 * 1024; // 5 MB
      case ConnectionQuality.poor:
        return 1024 * 1024; // 1 MB
      case ConnectionQuality.offline:
        return 0; // Не загружать
      default:
        return 10 * 1024 * 1024; // 10 MB
    }
  }

  // Рекомендуемое качество видео для звонков
  VideoQuality getRecommendedVideoQuality() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
        return VideoQuality.high; // 720p
      case ConnectionQuality.good:
        return VideoQuality.medium; // 480p
      case ConnectionQuality.fair:
        return VideoQuality.low; // 360p
      case ConnectionQuality.poor:
        return VideoQuality.audioOnly; // Только аудио
      case ConnectionQuality.offline:
        return VideoQuality.none; // Не звонить
      default:
        return VideoQuality.medium;
    }
  }

  // Проверка, можно ли совершить звонок
  bool get canMakeCall {
    return _currentQuality != ConnectionQuality.offline &&
           _currentQuality != ConnectionQuality.poor;
  }

  // Проверка, можно ли совершить видеозвонок
  bool get canMakeVideoCall {
    return _currentQuality == ConnectionQuality.excellent ||
           _currentQuality == ConnectionQuality.good;
  }

  // Получить понятное название качества
  String getQualityName() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
        return 'Отличное';
      case ConnectionQuality.good:
        return 'Хорошее';
      case ConnectionQuality.fair:
        return 'Среднее';
      case ConnectionQuality.poor:
        return 'Плохое';
      case ConnectionQuality.offline:
        return 'Офлайн';
      default:
        return 'Неизвестно';
    }
  }

  // Получить цвет для индикатора
  Color getQualityColor() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
        return Colors.green;
      case ConnectionQuality.good:
        return Colors.lightGreen;
      case ConnectionQuality.fair:
        return Colors.orange;
      case ConnectionQuality.poor:
        return Colors.deepOrange;
      case ConnectionQuality.offline:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Сбросить статистику
  void resetStats() {
    _latencySamples.clear();
    _totalMeasurements = 0;
    _failedMeasurements = 0;
    _averageLatency = null;
  }

  // Принудительно проверить соединение
  Future<void> checkNow() async {
    await _updateFromConnectivity();
    await _measureLatency();
  }

  // Остановить мониторинг
  void stopMonitoring() {
    _isMonitoring = false;
    _measurementTimer?.cancel();
  }

  // Возобновить мониторинг
  void startMonitoring() {
    if (!_isMonitoring) {
      _isMonitoring = true;
      _startLatencyMeasurement();
    }
  }

  void dispose() {
    _measurementTimer?.cancel();
    _qualityController.close();
    _bannerController.close();
    stopMonitoring();
  }
}

// ==================== ВСПОМОГАТЕЛЬНЫЕ ENUM ====================

enum ImageQuality {
  low,    // 320x320, качество 30%
  medium, // 640x640, качество 60%
  high    // оригинальный размер
}

enum VideoQuality {
  none,       // не звонить
  audioOnly,  // только аудио
  low,        // 360p
  medium,     // 480p
  high        // 720p
}

// ==================== РАСШИРЕНИЯ ====================

extension ConnectionQualityExtension on ConnectionQuality {
  // Проверка, можно ли отправлять медиа
  bool get canSendMedia {
    return this != ConnectionQuality.offline && this != ConnectionQuality.poor;
  }
  
  // Проверка, можно ли отправлять большие файлы
  bool get canSendLargeFiles {
    return this == ConnectionQuality.excellent || this == ConnectionQuality.good;
  }
  
  // Является ли соединение активным
  bool get isActive {
    return this != ConnectionQuality.offline && this != ConnectionQuality.unknown;
  }
  
  // Нужно ли показывать предупреждение
  bool get shouldShowWarning {
    return this == ConnectionQuality.poor || this == ConnectionQuality.offline;
  }
}