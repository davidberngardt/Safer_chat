import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'connection_quality_service.dart';

enum RequestPriority {
  high, // Критические запросы (звонки, отправка сообщений)
  normal, // Обычные запросы (загрузка чатов)
  low // Фоновые запросы (обновление статусов)
}

enum RequestMethod { get, post, put, patch, delete }

class CachedResponse {
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String etag;

  CachedResponse({
    required this.data,
    required this.timestamp,
    required this.etag,
  });

  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(timestamp) > maxAge;
  }
}

class ApiService {
  final String baseUrl;
  final String token;
  final ConnectionQualityService connectionQuality;

  // Кэш для GET запросов
  final Map<String, CachedResponse> _cache = {};
  static const Map<RequestPriority, Duration> cacheDurations = {
    RequestPriority.high: Duration(minutes: 1),
    RequestPriority.normal: Duration(minutes: 5),
    RequestPriority.low: Duration(minutes: 15),
  };

  // Статистика
  int _totalRequests = 0;
  int _failedRequests = 0;
  int _retriedRequests = 0;
  int _cacheHits = 0;
  final Map<int, int> _statusCodeCount = {};

  // Последний запрос для отладки
  http.Request? _lastRequest;

  // Геттер для совместимости с кодом, который использует request
  http.Request? get request => _lastRequest;

  // Настройки повторных попыток
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 1);

  // Таймауты по умолчанию
  static const Map<ConnectionQuality, Duration> timeouts = {
    ConnectionQuality.excellent: Duration(seconds: 5),
    ConnectionQuality.good: Duration(seconds: 10),
    ConnectionQuality.fair: Duration(seconds: 15),
    ConnectionQuality.poor: Duration(seconds: 25),
    ConnectionQuality.offline: Duration(milliseconds: 500),
    ConnectionQuality.unknown: Duration(seconds: 10),
  };

  ApiService({
    required this.baseUrl,
    required this.token,
    required this.connectionQuality,
  });

  // ==================== ПУБЛИЧНЫЕ МЕТОДЫ ====================

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
    bool useCache = true,
    RequestPriority priority = RequestPriority.normal,
    Duration? customTimeout,
  }) async {
    return _request(
      method: RequestMethod.get,
      path: path,
      queryParams: queryParams,
      useCache: useCache,
      priority: priority,
      customTimeout: customTimeout,
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? queryParams,
    RequestPriority priority = RequestPriority.normal,
    Duration? customTimeout,
  }) async {
    return _request(
      method: RequestMethod.post,
      path: path,
      data: data,
      queryParams: queryParams,
      priority: priority,
      customTimeout: customTimeout,
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? queryParams,
    RequestPriority priority = RequestPriority.normal,
    Duration? customTimeout,
  }) async {
    return _request(
      method: RequestMethod.put,
      path: path,
      data: data,
      queryParams: queryParams,
      priority: priority,
      customTimeout: customTimeout,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? queryParams,
    RequestPriority priority = RequestPriority.normal,
    Duration? customTimeout,
  }) async {
    return _request(
      method: RequestMethod.patch,
      path: path,
      data: data,
      queryParams: queryParams,
      priority: priority,
      customTimeout: customTimeout,
    );
  }

  Future<void> delete(
    String path, {
    Map<String, String>? queryParams,
    RequestPriority priority = RequestPriority.normal,
    Duration? customTimeout,
  }) async {
    await _request(
      method: RequestMethod.delete,
      path: path,
      queryParams: queryParams,
      priority: priority,
      customTimeout: customTimeout,
    );
  }

  Future<Map<String, dynamic>> uploadFile(
    String path,
    List<int> fileBytes,
    String fileName, {
    Map<String, String>? fields,
    String fieldName =
        'avatar', // Changed default field name for profile uploads
    RequestPriority priority = RequestPriority.normal,
    void Function(int sent, int total)? onProgress,
  }) async {
    _totalRequests++;

    final uri = _buildUri(path);
    final quality = connectionQuality.currentQuality;

    // Проверяем соединение
    if (quality == ConnectionQuality.offline) {
      throw NoInternetException('Нет подключения к интернету');
    }

    // Для больших файлов увеличиваем таймаут
    final fileSizeMB = fileBytes.length / (1024 * 1024);
    final timeout =
        fileSizeMB > 10 ? Duration(minutes: 5) : timeouts[quality]! * 2;

    print(
        '📤 Uploading file: $fileName (${fileSizeMB.toStringAsFixed(1)}MB) to $path');

    try {
      // Use PUT method for profile updates, POST for others
      final method = path.contains('user') ? 'PUT' : 'POST';
      var request = http.MultipartRequest(method, uri);

      // Заголовки
      request.headers.addAll(_getHeaders());

      // Добавляем поля формы
      if (fields != null) {
        request.fields.addAll(fields);
      }

      // Добавляем файл
      final multipartFile = http.MultipartFile.fromBytes(
        fieldName,
        fileBytes,
        filename: fileName,
        contentType: _getContentType(fileName),
      );

      request.files.add(multipartFile);

      print(
          '🌐 Making $method request to $uri with ${request.fields.length} fields and 1 file');

      // Отправляем с таймаутом
      final streamedResponse = await request.send().timeout(
        timeout,
        onTimeout: () {
          _failedRequests++;
          throw TimeoutException('Превышено время ожидания загрузки');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      _updateStats(response.statusCode);

      print(
          '📨 Upload response: ${response.statusCode} - ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');

      if (response.statusCode >= 400) {
        throw ApiException(
          message: _parseErrorMessage(response),
          statusCode: response.statusCode,
          uri: uri,
        );
      }

      final responseData = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      print('✅ Upload complete: $fileName (${response.statusCode})');
      return responseData;
    } on SocketException catch (e) {
      _failedRequests++;
      throw NetworkException('Ошибка сети: $e');
    } on TimeoutException catch (e) {
      _failedRequests++;
      rethrow;
    } catch (e) {
      _failedRequests++;
      throw ApiException(message: 'Ошибка загрузки: $e');
    }
  }

  // ==================== ВНУТРЕННИЕ МЕТОДЫ ====================

  Future<Map<String, dynamic>> _request({
    required RequestMethod method,
    required String path,
    Map<String, dynamic>? data,
    Map<String, String>? queryParams,
    bool useCache = false,
    RequestPriority priority = RequestPriority.normal,
    Duration? customTimeout,
    int retryCount = 0,
  }) async {
    _totalRequests++;

    final uri = _buildUri(path, queryParams);
    final cacheKey = uri.toString();
    final quality = connectionQuality.currentQuality;

    // Проверяем соединение
    if (quality == ConnectionQuality.offline && method == RequestMethod.get) {
      // При офлайн пытаемся вернуть кэш
      if (_cache.containsKey(cacheKey)) {
        _cacheHits++;
        return _cache[cacheKey]!.data;
      }
      throw NoInternetException('Нет подключения к интернету');
    }

    // Проверяем кэш для GET запросов
    if (method == RequestMethod.get &&
        useCache &&
        _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      final maxAge = cacheDurations[priority]!;

      if (!cached.isExpired(maxAge)) {
        _cacheHits++;
        print('📦 Cache hit: $path');
        return cached.data;
      } else {
        _cache.remove(cacheKey);
      }
    }

    // Определяем таймаут
    final timeout = customTimeout ?? timeouts[quality]!;

    try {
      print(
          '🌐 ${method.name.toUpperCase()} $path (timeout: ${timeout.inSeconds}s)');

      final request = _buildRequest(method, uri, data);
      final response = await _sendRequest(request, timeout);

      _updateStats(response.statusCode);

      // Обрабатываем ошибки
      if (response.statusCode >= 400) {
        return await _handleErrorResponse(response, method, path, data,
            queryParams, useCache, priority, customTimeout, retryCount);
      }

      final responseData = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      // Кэшируем успешный GET запрос
      if (method == RequestMethod.get && useCache) {
        final etag = response.headers['etag'] ?? '';
        _cache[cacheKey] = CachedResponse(
          data: responseData,
          timestamp: DateTime.now(),
          etag: etag,
        );
      }

      return responseData;
    } on SocketException catch (e) {
      _failedRequests++;
      return _handleNetworkError(e, method, path, data, queryParams, useCache,
          priority, customTimeout, retryCount);
    } on TimeoutException catch (e) {
      _failedRequests++;
      return _handleTimeoutError(e, method, path, data, queryParams, useCache,
          priority, customTimeout, retryCount);
    } catch (e) {
      _failedRequests++;
      throw ApiException(message: 'Неизвестная ошибка: $e');
    }
  }

  http.Request _buildRequest(
    RequestMethod method,
    Uri uri,
    Map<String, dynamic>? data,
  ) {
    late http.Request request;

    switch (method) {
      case RequestMethod.get:
        request = http.Request('GET', uri);
        break;
      case RequestMethod.post:
        request = http.Request('POST', uri);
        if (data != null) {
          request.body = jsonEncode(data);
        }
        break;
      case RequestMethod.put:
        request = http.Request('PUT', uri);
        if (data != null) {
          request.body = jsonEncode(data);
        }
        break;
      case RequestMethod.patch:
        request = http.Request('PATCH', uri);
        if (data != null) {
          request.body = jsonEncode(data);
        }
        break;
      case RequestMethod.delete:
        request = http.Request('DELETE', uri);
        break;
    }

    request.headers.addAll(_getHeaders(
      contentType: data != null ? 'application/json' : null,
    ));

    return request;
  }

  Future<http.Response> _sendRequest(
      http.Request request, Duration timeout) async {
    // Сохраняем последний запрос
    _lastRequest = request;

    final streamedResponse = await request.send().timeout(
          timeout,
          onTimeout: () => throw TimeoutException('Request timeout'),
        );

    return await http.Response.fromStream(streamedResponse);
  }

  Future<Map<String, dynamic>> _handleErrorResponse(
    http.Response response,
    RequestMethod method,
    String path,
    Map<String, dynamic>? data,
    Map<String, String>? queryParams,
    bool useCache,
    RequestPriority priority,
    Duration? customTimeout,
    int retryCount,
  ) async {
    final statusCode = response.statusCode;
    final errorMessage = _parseErrorMessage(response);
    final currentUri = _buildUri(path, queryParams);

    // 401 - Неавторизован
    if (statusCode == 401) {
      throw UnauthorizedException('Сессия истекла. Войдите снова.');
    }

    // 403 - Доступ запрещен
    if (statusCode == 403) {
      throw ForbiddenException('Доступ запрещен');
    }

    // 404 - Не найдено (не повторяем)
    if (statusCode == 404) {
      throw NotFoundException('Ресурс не найден: $path');
    }

    // 429 - Too Many Requests (повторяем с задержкой)
    if (statusCode == 429 && retryCount < maxRetries) {
      await Future.delayed(retryDelay * (retryCount + 1) * 2);
      return _request(
        method: method,
        path: path,
        data: data,
        queryParams: queryParams,
        useCache: useCache,
        priority: priority,
        customTimeout: customTimeout,
        retryCount: retryCount + 1,
      );
    }

    // 5xx - Серверные ошибки (повторяем)
    if (statusCode >= 500 && retryCount < maxRetries) {
      await Future.delayed(retryDelay * (retryCount + 1));
      return _request(
        method: method,
        path: path,
        data: data,
        queryParams: queryParams,
        useCache: useCache,
        priority: priority,
        customTimeout: customTimeout,
        retryCount: retryCount + 1,
      );
    }

    throw ApiException(
      message: errorMessage,
      statusCode: statusCode,
      uri: currentUri,
    );
  }

  Future<Map<String, dynamic>> _handleNetworkError(
    dynamic error,
    RequestMethod method,
    String path,
    Map<String, dynamic>? data,
    Map<String, String>? queryParams,
    bool useCache,
    RequestPriority priority,
    Duration? customTimeout,
    int retryCount,
  ) async {
    // Для GET запросов пробуем кэш при ошибке сети
    if (method == RequestMethod.get) {
      final cacheKey = _buildUri(path, queryParams).toString();
      if (_cache.containsKey(cacheKey)) {
        print('📦 Returning stale cache due to network error');
        return _cache[cacheKey]!.data;
      }
    }

    // Повторяем запрос для всех методов, кроме DELETE
    if (method != RequestMethod.delete && retryCount < maxRetries) {
      _retriedRequests++;
      final delay = retryDelay * (retryCount + 1);
      print('🔄 Retry ${retryCount + 1}/$maxRetries after ${delay.inSeconds}s');

      await Future.delayed(delay);
      return _request(
        method: method,
        path: path,
        data: data,
        queryParams: queryParams,
        useCache: useCache,
        priority: priority,
        customTimeout: customTimeout,
        retryCount: retryCount + 1,
      );
    }

    throw NetworkException('Ошибка сети: ${error.toString()}');
  }

  Future<Map<String, dynamic>> _handleTimeoutError(
    TimeoutException error,
    RequestMethod method,
    String path,
    Map<String, dynamic>? data,
    Map<String, String>? queryParams,
    bool useCache,
    RequestPriority priority,
    Duration? customTimeout,
    int retryCount,
  ) async {
    // Для GET запросов пробуем кэш при таймауте
    if (method == RequestMethod.get) {
      final cacheKey = _buildUri(path, queryParams).toString();
      if (_cache.containsKey(cacheKey)) {
        print('📦 Returning stale cache due to timeout');
        return _cache[cacheKey]!.data;
      }
    }

    // Повторяем запрос для приоритетных запросов
    if (priority == RequestPriority.high && retryCount < maxRetries) {
      _retriedRequests++;
      print('🔄 Retry high priority request after timeout');

      await Future.delayed(retryDelay);
      return _request(
        method: method,
        path: path,
        data: data,
        queryParams: queryParams,
        useCache: useCache,
        priority: priority,
        customTimeout: customTimeout,
        retryCount: retryCount + 1,
      );
    }

    throw TimeoutException('Превышено время ожидания');
  }

  // ==================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ====================

  Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final url =
        baseUrl.endsWith('/') ? '$baseUrl$cleanPath' : '$baseUrl/$cleanPath';

    if (queryParams == null || queryParams.isEmpty) {
      return Uri.parse(url);
    }

    final encodedParams = queryParams
        .map((key, value) => MapEntry(key, Uri.encodeQueryComponent(value)));

    return Uri.parse(url).replace(queryParameters: encodedParams);
  }

  Map<String, String> _getHeaders({String? contentType}) {
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Accept-Charset': 'utf-8',
      'Accept-Encoding': 'gzip',
      'X-Client-Version': '1.0.0',
      'X-Client-Platform': _getPlatformName(),
      'X-Connection-Quality': connectionQuality.currentQuality.toString(),
    };

    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }

    return headers;
  }

  String _getPlatformName() {
    try {
      if (kIsWeb) {
        return 'web';
      }
      return Platform.isIOS ? 'ios' : 'android';
    } catch (e) {
      // Fallback для случаев когда Platform недоступен
      return 'web';
    }
  }

  MediaType _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'mp3':
        return MediaType('audio', 'mpeg');
      case 'pdf':
        return MediaType('application', 'pdf');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  String _parseErrorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body['error'] ??
          body['message'] ??
          'Ошибка ${response.statusCode}';
    } catch (_) {
      return response.body.isNotEmpty
          ? response.body
          : 'Ошибка ${response.statusCode}';
    }
  }

  void _updateStats(int statusCode) {
    _statusCodeCount[statusCode] = (_statusCodeCount[statusCode] ?? 0) + 1;
  }

  // ==================== УПРАВЛЕНИЕ КЭШЕМ ====================

  void clearCache() {
    _cache.clear();
    print('🧹 API cache cleared');
  }

  void invalidateCacheForPath(String path) {
    final keysToRemove =
        _cache.keys.where((key) => key.contains(path)).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
    print('🧹 Cache invalidated for path: $path');
  }

  // ==================== СТАТИСТИКА ====================

  Map<String, dynamic> getStats() {
    return {
      'total_requests': _totalRequests,
      'failed_requests': _failedRequests,
      'retried_requests': _retriedRequests,
      'cache_hits': _cacheHits,
      'cache_size': _cache.length,
      'status_codes': _statusCodeCount,
      'connection_quality': connectionQuality.currentQuality.toString(),
    };
  }

  void printStats() {
    print('=== API Service Stats ===');
    print('Total requests: $_totalRequests');
    print('Failed: $_failedRequests');
    print('Retried: $_retriedRequests');
    print('Cache hits: $_cacheHits');
    print('Cache size: ${_cache.length}');
    print('Status codes: $_statusCodeCount');
    print('Quality: ${connectionQuality.currentQuality}');
    print('=========================');
  }
}

// ==================== КАСТОМНЫЕ ИСКЛЮЧЕНИЯ ====================

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Uri? uri;

  ApiException({required this.message, this.statusCode, this.uri});

  @override
  String toString() {
    final buffer = StringBuffer('ApiException: $message');
    if (statusCode != null) buffer.write(' (HTTP $statusCode)');
    if (uri != null) buffer.write(' at $uri');
    return buffer.toString();
  }
}

class NoInternetException extends ApiException {
  NoInternetException(String message) : super(message: message);
}

class TimeoutException extends ApiException {
  TimeoutException(String message) : super(message: message);
}

class NetworkException extends ApiException {
  NetworkException(String message) : super(message: message);
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(String message) : super(message: message);
}

class ForbiddenException extends ApiException {
  ForbiddenException(String message) : super(message: message);
}

class NotFoundException extends ApiException {
  NotFoundException(String message) : super(message: message);
}
