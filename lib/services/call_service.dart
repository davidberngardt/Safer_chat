import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/services/call_screen.dart';
import '../utils/platform_utils.dart';

// Модель для WebRTC соединения
class WebRTCConnection {
  final String roomId;
  final String janusSessionId;
  final String handleId;
  bool isVideoEnabled;
  bool isAudioEnabled;
  
  WebRTCConnection({
    required this.roomId,
    required this.janusSessionId,
    required this.handleId,
    this.isVideoEnabled = true,
    this.isAudioEnabled = true,
  });
}

class CallService {
  // Здесь будет логика звонков с использованием WebRTC через Janus Gateway
  
  CallScreen? _activeCallScreen;
  WebRTCConnection? _currentCall;
  Timer? _callTimeoutTimer;
  
  // Временное хранилище для демо-режима
  final Map<int, Timer> _demoRingingTimers = {};
  
  Future<void> startCall({
    required String token,
    required String baseUrl,
    required int myUserId,
    required int recipientId,
    required int chatId,
    required String recipientName,
    String? recipientAvatar,
    required BuildContext context,
    required CallType callType,
  }) async {
    print('Starting ${callType == CallType.video ? 'video' : 'audio'} call to $recipientId');
    
    try {
      // 1. Создаем комнату в Janus Gateway
      final roomId = await _createJanusRoom(token, baseUrl, chatId, callType);
      
      // 2. Создаем сессию Janus
      final sessionId = await _createJanusSession(token, baseUrl);
      
      // 3. Создаем handle для WebRTC
      final handleId = await _attachWebRTCPlugin(token, baseUrl, sessionId);
      
      // 4. Сохраняем информацию о звонке
      _currentCall = WebRTCConnection(
        roomId: roomId,
        janusSessionId: sessionId,
        handleId: handleId,
        isVideoEnabled: callType == CallType.video,
        isAudioEnabled: true,
      );
      
      // 5. Отправляем уведомление о звонке получателю
      await _notifyRecipient(token, baseUrl, recipientId, chatId, callType, roomId);
      
      // 6. Показываем экран звонка
      _showCallScreen(
        context: context,
        myUserId: myUserId,
        otherUserId: recipientId,
        otherUserName: recipientName,
        otherUserAvatar: recipientAvatar,
        callType: callType,
        callDirection: CallDirection.outgoing,
      );
      
      // 7. Устанавливаем таймаут на ответ (30 секунд)
      _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_currentCall != null && mounted(context)) {
          _handleCallTimeout(context);
        }
      });
      
    } catch (e) {
      print('❌ Failed to start call: $e');
      _showErrorDialog(context, 'Failed to start call: $e');
    }
  }

  Future<void> receiveCall({
    required String token,
    required String baseUrl,
    required int myUserId,
    required int callerId,
    required int chatId,
    required String callerName,
    String? callerAvatar,
    required BuildContext context,
    required CallType callType,
    required String roomId,
  }) async {
    print('Receiving ${callType == CallType.video ? 'video' : 'audio'} call from $callerId');
    
    try {
      // 1. Присоединяемся к существующей комнате Janus
      final sessionId = await _createJanusSession(token, baseUrl);
      final handleId = await _attachWebRTCPlugin(token, baseUrl, sessionId);
      
      // 2. Сохраняем информацию о звонке
      _currentCall = WebRTCConnection(
        roomId: roomId,
        janusSessionId: sessionId,
        handleId: handleId,
        isVideoEnabled: callType == CallType.video,
        isAudioEnabled: true,
      );
      
      // 3. Показываем экран входящего звонка
      _showCallScreen(
        context: context,
        myUserId: myUserId,
        otherUserId: callerId,
        otherUserName: callerName,
        otherUserAvatar: callerAvatar,
        callType: callType,
        callDirection: CallDirection.incoming,
      );
      
    } catch (e) {
      print('❌ Failed to receive call: $e');
      _showErrorDialog(context, 'Failed to receive call: $e');
    }
  }

  // Методы для Janus Gateway API
  Future<String> _createJanusRoom(String token, String baseUrl, int chatId, CallType callType) async {
    // TODO: Реальная реализация создания комнаты в Janus
    // Сейчас возвращаем тестовый roomId
    return 'room_${chatId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _createJanusSession(String token, String baseUrl) async {
    // TODO: Реальная реализация создания сессии Janus
    return 'session_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _attachWebRTCPlugin(String token, String baseUrl, String sessionId) async {
    // TODO: Реальная реализация прикрепления WebRTC плагина
    return 'handle_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _notifyRecipient(
    String token, 
    String baseUrl, 
    int recipientId, 
    int chatId, 
    CallType callType,
    String roomId,
  ) async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      
      // Отправляем уведомление через WebSocket или HTTP
      await dio.post(
        '$baseUrl/api/calls/notify',
        data: {
          'recipient_id': recipientId,
          'chat_id': chatId,
          'call_type': callType == CallType.video ? 'video' : 'audio',
          'room_id': roomId,
        },
      );
      
      print('📞 Notification sent to user $recipientId');
      
    } catch (e) {
      print('❌ Failed to notify recipient: $e');
    }
  }

  void _showCallScreen({
    required BuildContext context,
    required int myUserId,
    required int otherUserId,
    required String otherUserName,
    String? otherUserAvatar,
    required CallType callType,
    required CallDirection callDirection,
  }) {
    final isWeb = MediaQuery.of(context).size.width > 600;
    
    if (isWeb) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => CallScreen(
          myUserId: myUserId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          otherUserAvatar: otherUserAvatar,
          callType: callType,
          callDirection: callDirection,
          onAccept: () => _handleAccept(callDirection, dialogContext),
          onReject: () => _handleReject(dialogContext),
          onEnd: () => _handleEnd(dialogContext),
          onToggleMute: _handleToggleMute,
          onToggleVideo: callType == CallType.video ? _handleToggleVideo : null,
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (routeContext) => CallScreen(
            myUserId: myUserId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            otherUserAvatar: otherUserAvatar,
            callType: callType,
            callDirection: callDirection,
            onAccept: () => _handleAccept(callDirection, routeContext),
            onReject: () => _handleReject(routeContext),
            onEnd: () => _handleEnd(routeContext),
            onToggleMute: _handleToggleMute,
            onToggleVideo: callType == CallType.video ? _handleToggleVideo : null,
          ),
        ),
      );
    }
  }

  void _handleAccept(CallDirection direction, BuildContext context) {
    print('Call accepted');
    _callTimeoutTimer?.cancel();
    
    // Здесь запускаем WebRTC streaming
    _startWebRTCStream();
  }

  void _handleReject(BuildContext context) {
    print('Call rejected');
    _cleanupCall();
    Navigator.of(context).pop();
  }

  void _handleEnd(BuildContext context) {
    print('Call ended');
    _cleanupCall();
    Navigator.of(context).pop();
  }

  void _handleToggleMute(bool isMuted) {
    print('Microphone ${isMuted ? 'muted' : 'unmuted'}');
    if (_currentCall != null) {
      _currentCall!.isAudioEnabled = !isMuted;
      // TODO: Отправить команду в Janus на отключение/включение аудио
    }
  }

  void _handleToggleVideo(bool isVideoEnabled) {
    print('Video ${isVideoEnabled ? 'enabled' : 'disabled'}');
    if (_currentCall != null) {
      _currentCall!.isVideoEnabled = isVideoEnabled;
      // TODO: Отправить команду в Janus на отключение/включение видео
    }
  }

  void _handleCallTimeout(BuildContext context) {
    print('⏰ Call timeout - no answer');
    _cleanupCall();
    
    if (mounted(context)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The user did not answer'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _startWebRTCStream() {
    // TODO: Запуск WebRTC потока через Janus
    print('🎥 Starting WebRTC stream...');
  }

  void _cleanupCall() {
    _callTimeoutTimer?.cancel();
    // TODO: Очистка WebRTC соединений в Janus
    _currentCall = null;
  }

  bool mounted(BuildContext context) {
    return context is Element && context.mounted;
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  Future<void> endCall() async {
    print('Ending call');
    _cleanupCall();
    // TODO: Уведомить другого участника о завершении звонка
  }
  
  void dispose() {
    _callTimeoutTimer?.cancel();
    _demoRingingTimers.forEach((key, timer) => timer.cancel());
    _demoRingingTimers.clear();
    _cleanupCall();
  }
}