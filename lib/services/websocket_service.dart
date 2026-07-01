import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

enum MessagePriority {
  high,
  normal,
  low,
}

class QueuedMessage {
  final Map<String, dynamic> data;
  final MessagePriority priority;
  final DateTime timestamp;
  final String id;
  int retryCount;

  QueuedMessage({
    required this.data,
    this.priority = MessagePriority.normal,
    DateTime? timestamp,
    String? id,
    this.retryCount = 0,
  })  : timestamp = timestamp ?? DateTime.now(),
        id = id ??
            'msg_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'data': data,
    'priority': priority.index,
    'timestamp': timestamp.toIso8601String(),
    'retryCount': retryCount,
  };
}

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;

  String? _currentToken;
  String? _currentBaseUrl;
  int? _currentUserId;

  ConnectionStatus _status = ConnectionStatus.disconnected;

  // ✅ ДОБАВИЛИ
  ConnectionStatus get status => _status;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get onStatusChange => _statusController.stream;

  final _messageController =
  StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessage =>
      _messageController.stream;

  final List<QueuedMessage> _messageQueue = [];
  bool _isProcessingQueue = false;

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _queueProcessorTimer;
  Timer? _pongTimeoutTimer;

  int _reconnectAttempts = 0;

  static const int maxReconnectAttempts = 50;
  static const int pingInterval = 15000;
  static const int pongTimeout = 5000;
  static const int queueProcessInterval = 500;
  static const int maxRetryCount = 10;

  bool _awaitingPong = false;

  bool get isConnected => _status == ConnectionStatus.connected;

  Future<void> connect({
    required String token,
    required String baseUrl,
    int? userId,
  }) async {
    _currentToken = token;
    _currentBaseUrl = baseUrl;
    _currentUserId = userId;

    _updateStatus(ConnectionStatus.connecting);

    try {
      await _closeChannel();

      final wsUrl = _buildWebSocketUrl(baseUrl, token);

      _channel = _createChannel(wsUrl);

      _channel!.stream.listen(
        _handleIncomingMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
      );

      _updateStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;

      _startHeartbeat();
      _startQueueProcessor();
      _processQueue();
    } catch (e) {
      _handleError(e);
    }
  }

  WebSocketChannel _createChannel(String url) {
    if (kIsWeb) {
      return WebSocketChannel.connect(Uri.parse(url));
    } else {
      return IOWebSocketChannel.connect(url);
    }
  }

  String _buildWebSocketUrl(String baseUrl, String token) {
    final wsBase = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    return '$wsBase/ws?token=$token';
  }

  void _handleIncomingMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String);

      if (message['type'] == 'pong') {
        _handlePong();
        return;
      }

      if (message['type'] == 'ack' && message['message_id'] != null) {
        _messageQueue.removeWhere((m) => m.id == message['message_id']);
      }

      _messageController.add(message);
    } catch (_) {}
  }

  void _handleError(dynamic error) {
    _updateStatus(ConnectionStatus.error);
    _scheduleReconnect();
  }

  void _handleDisconnection() {
    _stopHeartbeat();
    _updateStatus(ConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) return;

    _reconnectTimer?.cancel();

    final delay = min(1000 * pow(2, _reconnectAttempts).toInt(), 30000);

    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _reconnectAttempts++;
      if (_currentToken != null && _currentBaseUrl != null) {
        connect(
          token: _currentToken!,
          baseUrl: _currentBaseUrl!,
          userId: _currentUserId,
        );
      }
    });
  }

  // ================= HEARTBEAT =================

  void _startHeartbeat() {
    _stopHeartbeat();

    _pingTimer =
        Timer.periodic(Duration(milliseconds: pingInterval), (_) {
          if (_awaitingPong) {
            _handleDisconnection();
            return;
          }

          _awaitingPong = true;

          send({
            'type': 'ping',
            'ts': DateTime.now().millisecondsSinceEpoch,
          });

          _pongTimeoutTimer?.cancel();
          _pongTimeoutTimer =
              Timer(Duration(milliseconds: pongTimeout), () {
                if (_awaitingPong) {
                  _handleDisconnection();
                }
              });
        });
  }

  void _handlePong() {
    _awaitingPong = false;
    _pongTimeoutTimer?.cancel();
  }

  void _stopHeartbeat() {
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _awaitingPong = false;
  }

  // ================= QUEUE =================

  void _startQueueProcessor() {
    _queueProcessorTimer?.cancel();
    _queueProcessorTimer =
        Timer.periodic(Duration(milliseconds: queueProcessInterval), (_) {
          _processQueue();
        });
  }

  void _processQueue() {
    if (_isProcessingQueue ||
        _messageQueue.isEmpty ||
        !isConnected) return;

    _isProcessingQueue = true;

    try {
      _messageQueue.sort((a, b) =>
          a.priority.index.compareTo(b.priority.index));

      final batch = _messageQueue.take(5).toList();

      for (final msg in batch) {
        try {
          _channel?.sink.add(jsonEncode(msg.data));
          msg.retryCount++;

          if (msg.retryCount > maxRetryCount) {
            _messageQueue.remove(msg);
          }
        } catch (_) {}
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  void send(Map<String, dynamic> data,
      {MessagePriority priority = MessagePriority.normal}) {
    final msg = QueuedMessage(data: data, priority: priority);
    _messageQueue.add(msg);

    if (isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (_) {}
    }
  }

  // ✅ ДОБАВИЛИ
  void clearQueue() {
    _messageQueue.clear();
  }

  // ================= CLEANUP =================

  Future<void> _closeChannel() async {
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _updateStatus(ConnectionStatus status) {
    if (_status != status) {
      _status = status;
      _statusController.add(status);
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _queueProcessorTimer?.cancel();
    _closeChannel();
    _updateStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
  }
}