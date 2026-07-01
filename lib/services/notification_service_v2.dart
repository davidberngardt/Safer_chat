import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:safer_chat/models/message.dart' as chat_message;
import 'package:safer_chat/services/websocket_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safer_chat/utils/platform_utils.dart';

// Условный импорт для CallKit только на iOS
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart'
if (dart.library.html) 'package:safer_chat/stubs/callkit_stub.dart';

enum NotificationType {
  chat,
  group,
  channel,
}

// Класс для отслеживания текущего открытого чата
class ActiveChatInfo {
  int? chatId;
  String? chatType; // 'chat', 'group', 'channel'

  void setActive(int id, String type) {
    chatId = id;
    chatType = type;
  }

  void clear() {
    chatId = null;
    chatType = null;
  }

  bool isActive(int id, String type) {
    return chatId == id && chatType == type;
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("📱 Handling background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  late WebSocketService _webSocket;

  // Пути к звуковым файлам
  static const String _messageSoundPath = 'sounds/notification.mp3';
  static const String _callSoundPath = 'sounds/call_ringtone.mp3';

  // Firebase Messaging
  FirebaseMessaging? _firebaseMessaging;

  bool _isInitialized = false;
  bool _soundEnabled = true;
  bool _notificationsEnabled = true;
  Timer? _soundCooldownTimer;
  static const int _soundCooldownMs = 2000;

  // Карта для отслеживания последних уведомлений по чатам (anti-spam)
  final Map<String, DateTime> _lastNotificationTime = {};
  static const int _notificationCooldownSec = 5;

  // Активный чат
  final ActiveChatInfo _activeChat = ActiveChatInfo();

  // Колбэк для навигации
  Function(Map<String, dynamic>)? onNotificationTap;

  // Колбэк для показа веб-тултипа
  Function(Map<String, dynamic>)? onShowWebTooltip;

  // Таймер для скрытия веб-тултипа
  Timer? _webTooltipTimer;

  // Переменная для отслеживания видимости приложения
  bool _isAppVisible = true;

  // VoIP токен для iOS
  String? _voipToken;

  // Переменные для хранения токенов и базового URL
  String? _currentToken;
  String? _currentBaseUrl;

  Future<void> initialize({
    required String token,
    required String baseUrl,
    required int myUserId,
  }) async {
    if (_isInitialized) return;

    try {
      _currentToken = token;
      _currentBaseUrl = baseUrl;
      _webSocket = WebSocketService();

      // Инициализация Firebase Messaging для Android и iOS
      if (!kIsWeb) {
        _firebaseMessaging = FirebaseMessaging.instance;
        await _initializeFirebaseMessaging();
      }

      // Подключаемся к WebSocket
      await _webSocket.connect(
        token: token,
        baseUrl: baseUrl,
        userId: myUserId,
      );

      // Слушаем входящие сообщения
      _webSocket.onMessage.listen((event) {
        _handleIncomingEvent(event, myUserId);
      });

      // Инициализация локальных уведомлений для мобильных
      if (!kIsWeb) {
        await _initializeLocalNotifications();
        await _configureAndroidChannels();
      }

      // Предзагрузка звуков
      await _preloadNotificationSounds();

      // Настройка для iOS
      if (!kIsWeb && Platform.isIOS) {
        await _configureiOSPush();
      }

      _isInitialized = true;
    } catch (e) {
      print('❌ Error initializing NotificationService: $e');
    }
  }

  Future<void> _initializeFirebaseMessaging() async {
    if (_firebaseMessaging == null) return;

    try {
      NotificationSettings settings = await _firebaseMessaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        criticalAlert: true,
      );

      print('📱 Firebase messaging permission: ${settings.authorizationStatus}');

      String? fcmToken = await _firebaseMessaging!.getToken();
      print('📱 FCM Token: $fcmToken');

      if (fcmToken != null) {
        _sendTokenToServer(fcmToken, 'fcm');
      }

      _firebaseMessaging!.onTokenRefresh.listen((newToken) {
        print('📱 FCM Token refreshed: $newToken');
        _sendTokenToServer(newToken, 'fcm');
      });

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📱 Received foreground message: ${message.messageId}');
        _handleFirebaseMessage(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📱 Message opened app: ${message.messageId}');
        _handleNotificationOpen(message.data);
      });

      RemoteMessage? initialMessage = await _firebaseMessaging!.getInitialMessage();
      if (initialMessage != null) {
        print('📱 App opened from notification: ${initialMessage.messageId}');
        _handleNotificationOpen(initialMessage.data);
      }
    } catch (e) {
      print('❌ Error initializing Firebase Messaging: $e');
    }
  }

  Future<void> _configureiOSPush() async {
    if (!kIsWeb && Platform.isIOS) {
      try {
        final pushKit = FlutterCallkitIncoming();

        try {
          // await pushKit.registerVoIPPush();
        } catch (e) {
          print('⚠️ VoIP push registration not available: $e');
        }

        try {
          // pushKit.onTokenRefreshed?.listen((token) {
          //   print('📱 VoIP Token refreshed: $token');
          //   _voipToken = token;
          //   _sendTokenToServer(token, 'voip');
          // });
        } catch (e) {
          print('⚠️ VoIP token refresh not available: $e');
        }

        try {
          // pushKit.onDidReceiveIncomingPush?.listen((event) {
          //   print('📱 Received VoIP push: $event');
          //   _handleIncomingCall(event as Map<String, dynamic>);
          // });
        } catch (e) {
          print('⚠️ VoIP push handler not available: $e');
        }
      } catch (e) {
        print('❌ Error configuring iOS push: $e');
      }
    }
  }

  Future<void> _sendTokenToServer(String token, String type) async {
    if (_currentBaseUrl == null || _currentToken == null) return;

    try {
      final dio = Dio();
      await dio.post(
        '$_currentBaseUrl/api/push-tokens',
        data: {
          'token': token,
          'type': type,
          'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web'),
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $_currentToken',
          },
        ),
      );
      print('✅ Push token sent to server: $type');
    } catch (e) {
      print('❌ Error sending push token to server: $e');
    }
  }

  void _handleFirebaseMessage(RemoteMessage message) {
    final data = message.data;
    final notification = message.notification;

    if (data['type'] == 'call') {
      _handleIncomingCall(data);
    } else {
      _showLocalNotification(
        title: notification?.title ?? data['title'] ?? 'Новое сообщение',
        body: notification?.body ?? data['body'] ?? '',
        payload: data,
      );
    }
  }

  void _handleIncomingCall(Map<String, dynamic> data) {
    if (kIsWeb) {
      _showWebCallNotification(data);
    } else if (Platform.isIOS) {
      _showIOSCallNotification(data);
    } else {
      _showAndroidCallNotification(data);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // В версии 21.0.0 initialize принимает ТОЛЬКО именованные параметры
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    if (!kIsWeb && Platform.isIOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> _configureAndroidChannels() async {
    if (kIsWeb) return;

    // Канал для сообщений
    const AndroidNotificationChannel messagesChannel = AndroidNotificationChannel(
      'messages_channel',
      'Сообщения',
      description: 'Уведомления о новых сообщениях',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF9800),
      showBadge: true,
    );

    // Канал для звонков
    const AndroidNotificationChannel callsChannel = AndroidNotificationChannel(
      'calls_channel',
      'Звонки',
      description: 'Уведомления о звонках',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF9800),
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(messagesChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(callsChannel);
  }

  void _handleIncomingEvent(Map<String, dynamic> event, int myUserId) {
    final type = event['type'];

    switch (type) {
      case 'new_message':
        _handleNewMessage(event, myUserId);
        break;
      case 'call':
        _handleCallEvent(event);
        break;
    }
  }

  void _handleCallEvent(Map<String, dynamic> event) {
    final callData = event['call'];
    if (callData == null) return;
    _handleIncomingCall(callData);
  }

  void _handleNewMessage(Map<String, dynamic> event, int myUserId) {
    final messageData = event['message'];
    if (messageData == null) return;

    final chatId = event['chat_id'] ?? event['group_id'] ?? event['channel_id'];
    final chatType = event['chat_type'] ?? 'chat';
    final senderId = messageData['user_id'] ?? messageData['userId'];
    final chatTitle = event['chat_title'] ??
        event['group_title'] ??
        event['channel_title'] ??
        'Новое сообщение';
    final senderName = event['sender_name'] ?? 'Пользователь';
    final senderAvatar = event['sender_avatar'];

    if (senderId == myUserId) return;

    final isChatActive = _activeChat.isActive(chatId, chatType);

    if (isChatActive) {
      print('📱 Chat $chatId is active, skipping notification');
      return;
    }

    final message = chat_message.Message(
      id: messageData['id'],
      userId: senderId,
      text: messageData['text'] ?? '',
      createdAt: DateTime.parse(
          messageData['created_at'] ?? messageData['createdAt']),
      fileUrl: messageData['file_url'] ?? messageData['fileUrl'],
      typeId: messageData['type_id'] ?? messageData['typeId'] ?? 1,
      duration: messageData['duration'],
    );

    final chatKey = '$chatType:$chatId';
    if (_shouldNotify(chatKey, message)) {
      _showNotification(
        chatId: chatId,
        chatType: chatType,
        chatTitle: chatTitle,
        message: message,
        senderName: senderName,
        senderAvatar: senderAvatar,
      );
    }
  }

  bool _shouldNotify(String chatKey, chat_message.Message message) {
    final lastTime = _lastNotificationTime[chatKey];
    if (lastTime != null) {
      final diff = DateTime.now().difference(lastTime);
      if (diff.inSeconds < _notificationCooldownSec) {
        print('⏱️ Cooldown for $chatKey, skipping notification');
        return false;
      }
    }

    final now = DateTime.now();
    final messageTime = message.createdAt;
    final difference = now.difference(messageTime);
    final isRecent = difference.inSeconds < 30;

    if (!isRecent) {
      print('⏰ Message is too old (${difference.inSeconds}s), skipping');
    }

    return isRecent;
  }

  Future<void> _showNotification({
    required int chatId,
    required String chatType,
    required String chatTitle,
    required chat_message.Message message,
    required String senderName,
    String? senderAvatar,
  }) async {
    final chatKey = '$chatType:$chatId';
    _lastNotificationTime[chatKey] = DateTime.now();

    if (_soundEnabled) {
      await _playMessageSound();
    }

    if (!kIsWeb) {
      await _updateBadgeCount();
    }

    if (kIsWeb) {
      _showWebNotification(
        chatId: chatId,
        chatType: chatType,
        chatTitle: chatTitle,
        message: message,
        senderName: senderName,
      );
    }

    if (!kIsWeb && _notificationsEnabled) {
      await _showPushNotification(
        chatId: chatId,
        chatType: chatType,
        chatTitle: chatTitle,
        message: message,
        senderName: senderName,
        senderAvatar: senderAvatar,
      );
    }
  }

  Future<void> _updateBadgeCount() async {
    print('ℹ️ Badge count update skipped - using badges package for in-app badges');
  }

  Future<void> _playMessageSound() async {
    if (_soundCooldownTimer?.isActive ?? false) return;

    try {
      await _audioPlayer.play(AssetSource(_messageSoundPath));
      _soundCooldownTimer = Timer(Duration(milliseconds: _soundCooldownMs), () {});
    } catch (e) {
      print('Error playing message sound: $e');
    }
  }

  Future<void> _playCallSound() async {
    try {
      await _audioPlayer.play(AssetSource(_callSoundPath));
    } catch (e) {
      print('Error playing call sound: $e');
    }
  }

  Future<void> _preloadNotificationSounds() async {
    try {
      await _audioPlayer.setSource(AssetSource(_messageSoundPath));
      await _audioPlayer.setSource(AssetSource(_callSoundPath));
      print('✅ Sounds preloaded successfully');
    } catch (e) {
      print('Error preloading sounds: $e');
    }
  }

  void _showWebNotification({
    required int chatId,
    required String chatType,
    required String chatTitle,
    required chat_message.Message message,
    required String senderName,
  }) {
    final payload = {
      'type': chatType,
      'chatId': chatId,
      'chatTitle': chatTitle,
      'messageId': message.id,
      'senderName': senderName,
      'messageText': message.text,
    };

    if (onShowWebTooltip != null) {
      onShowWebTooltip!(payload);
    }
  }

  void _showWebCallNotification(Map<String, dynamic> callData) {
    print('📱 Web call notification: $callData');
  }

  Future<void> _showIOSCallNotification(Map<String, dynamic> callData) async {
    print('📱 iOS Call notification: $callData');

    _showLocalNotification(
      title: callData['call_type'] == 'video' ? '📹 Видеозвонок' : '📞 Аудиозвонок',
      body: 'Входящий звонок от ${callData['caller_name'] ?? 'пользователя'}',
      payload: callData,
    );

    if (_soundEnabled) {
      await _playCallSound();
    }
  }

  Future<void> _showAndroidCallNotification(Map<String, dynamic> callData) async {
    try {
      final title = callData['call_type'] == 'video' ? '📹 Видеозвонок' : '📞 Аудиозвонок';
      final body = 'Входящий звонок от ${callData['caller_name'] ?? 'пользователя'}';

      final payload = {
        'type': 'call',
        'chatId': callData['chat_id'],
        'callerId': callData['caller_id'],
        'callType': callData['call_type'],
        'callData': callData,
      };

      if (_soundEnabled) {
        await _playCallSound();
      }

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'calls_channel',
        'Звонки',
        channelDescription: 'Уведомления о звонках',
        importance: Importance.max,
        priority: Priority.high,
        color: const Color(0xFFFF9800),
        icon: '@mipmap/ic_launcher',
        sound: RawResourceAndroidNotificationSound('call_ringtone'),
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        autoCancel: false,
        timeoutAfter: 30000,
      );

      final NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
      );

      // v21.0.0: show принимает ТОЛЬКО именованные параметры
      await _localNotifications.show(
        id: callData['chat_id'],
        title: title,
        body: body,
        notificationDetails: platformDetails,
        payload: jsonEncode(payload),
      );
    } catch (e) {
      print('Error showing Android call notification: $e');
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    if (kIsWeb) return;

    // v21.0.0: show принимает ТОЛЬКО именованные параметры
    await _localNotifications.show(
      id: payload.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'messages_channel',
          'Сообщения',
          channelDescription: 'Уведомления о новых сообщениях',
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFFFF9800),
          icon: '@mipmap/ic_launcher',
          sound: RawResourceAndroidNotificationSound('notification'),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(payload),
    );
  }

  Future<void> _showPushNotification({
    required int chatId,
    required String chatType,
    required String chatTitle,
    required chat_message.Message message,
    required String senderName,
    String? senderAvatar,
  }) async {
    if (kIsWeb) return;

    try {
      String body = _formatMessageForNotification(message, senderName);

      final payload = {
        'type': chatType,
        'chatId': chatId,
        'chatTitle': chatTitle,
        'messageId': message.id,
      };

      AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'messages_channel',
        'Сообщения',
        channelDescription: 'Уведомления о новых сообщениях',
        importance: Importance.high,
        priority: Priority.high,
        color: const Color(0xFFFF9800),
        icon: '@mipmap/ic_launcher',
        sound: RawResourceAndroidNotificationSound('notification'),
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        autoCancel: true,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: '${chatType}_$chatId',
        categoryIdentifier: 'MESSAGE_CATEGORY',
      );

      final NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final notificationId = chatId.hashCode ^ message.id.hashCode;

      // v21.0.0: show принимает ТОЛЬКО именованные параметры
      await _localNotifications.show(
        id: notificationId,
        title: chatTitle,
        body: body,
        notificationDetails: platformDetails,
        payload: jsonEncode(payload),
      );

      print('✅ Push notification shown for chat $chatId');
    } catch (e) {
      print('Error showing push notification: $e');
    }
  }

  String _formatMessageForNotification(chat_message.Message message, String senderName) {
    if (message.text.isNotEmpty) {
      return '$senderName: ${message.text}';
    }

    switch (message.typeId) {
      case 2:
        return '$senderName: 📷 Фото';
      case 3:
        return '$senderName: 🎥 Видео';
      case 4:
        return '$senderName: 🎤 Голосовое сообщение';
      case 5:
        return '$senderName: 📎 Файл';
      case 6:
        return '$senderName: 🖼️ GIF';
      default:
        return '$senderName: Новое сообщение';
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;

    try {
      final Map<String, dynamic> payload = jsonDecode(response.payload!);

      if (onNotificationTap != null) {
        onNotificationTap!(payload);
      }
    } catch (e) {
      print('Error parsing notification payload: $e');
    }
  }

  void _handleNotificationOpen(Map<String, dynamic> data) {
    if (onNotificationTap != null) {
      onNotificationTap!(data);
    }
  }

  // Управление активным чатом
  void setActiveChat(int chatId, String chatType) {
    _activeChat.setActive(chatId, chatType);
    print('🔔 Active chat set to: $chatType:$chatId');
  }

  void clearActiveChat() {
    _activeChat.clear();
    print('🔔 Active chat cleared');
  }

  // Управление видимостью приложения
  void setAppVisibility(bool isVisible) {
    _isAppVisible = isVisible;
  }

  // Управление настройками
  void enableSound() => _soundEnabled = true;
  void disableSound() => _soundEnabled = false;
  void enableNotifications() => _notificationsEnabled = true;
  void disableNotifications() => _notificationsEnabled = false;

  // Очистка
  Future<void> clearNotificationsForChat(int chatId) async {
    if (kIsWeb) return;
    // v21.0.0: cancel принимает ТОЛЬКО именованный параметр id
    await _localNotifications.cancel(id: chatId.hashCode);
  }

  Future<void> clearAllNotifications() async {
    if (kIsWeb) return;
    await _localNotifications.cancelAll();
    print('ℹ️ All notifications cleared');
  }

  bool get isSoundEnabled => _soundEnabled;
  bool get areNotificationsEnabled => _notificationsEnabled;
  bool get isInitialized => _isInitialized;

  void dispose() {
    _webSocket.dispose();
    _audioPlayer.dispose();
    _soundCooldownTimer?.cancel();
    _webTooltipTimer?.cancel();
    _lastNotificationTime.clear();
  }
}