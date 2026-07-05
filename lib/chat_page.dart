import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:safer_chat/theme.dart';
import 'models/message.dart';
import 'services/emoji_data.dart';
import 'services/voice_service.dart';
import 'services/media_service.dart';
import 'services/websocket_service.dart';
import 'services/notification_service_v2.dart';
import 'providers/font_scale_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/blocked_users_provider.dart';
import 'forward_message_page.dart';
import 'providers/theme_provider.dart';
import 'services/contacts_modal.dart';
import 'services/media_gallery_modal.dart';
import 'utils/platform_utils.dart';
import 'services/call_service.dart';
import 'services/call_screen.dart';
import '../models/call_history.dart';
import 'services/api_service.dart';

class ChatPage extends StatefulWidget {
  final int myUserId;
  final String baseUrl;
  final String token;
  final int chatId;
  final String chatTitle;
  final int? recipientUserId;

  final WebSocketService? webSocketService;
  final ApiService? apiService;
  final Message? forwardedMessage;

  const ChatPage({
    Key? key,
    required this.myUserId,
    required this.baseUrl,
    required this.token,
    required this.chatId,
    required this.chatTitle,
    this.recipientUserId,
    this.webSocketService,
    this.apiService,
    this.forwardedMessage,
  }) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode focusNode = FocusNode();
  final FocusNode _rawKeyboardFocusNode = FocusNode();

  late VoiceService _voiceService;
  final MediaService _mediaService = MediaService();
  late CallService _callService;
  late WebSocketService _webSocketService;
  late NotificationService _notificationService;

  bool _showScrollDownButton = false;
  bool _showEmojiPicker = false;
  bool _isLoading = true;
  bool _hasMoreMessages = true;
  int _currentPage = 1;
  late TabController _tabController;

  List<Message> _pinnedMessages = [];
  bool _showPinnedMessages = false;

  List<XFile> _attachedFiles = [];
  bool _hasAttachments = false;

  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;
  bool _showVideoModal = false;
  String? _currentVideoUrl;

  bool _isPlaying = false;
  int? _playingMessageId;

  bool _showSearch = false;
  List<Message> _searchResults = [];
  int _currentSearchIndex = -1;

  Map<String, dynamic> _contactInfo = {
    'photoUrl': null,
    'name': '',
    'nickname': '',
    'birthday': 'Не указано',
    'isContact': false,
    'isBlocked': false,
  };

  bool _audioAvailable = false;
  bool _audioInitialized = false;
  bool _microphonePermissionGranted = false;
  bool _shiftPressed = false;
  Timer? _progressTimer;
  Timer? _notificationCheckTimer;
  OverlayEntry? _contextMenuOverlay;
  Message? _selectedMessageForContextMenu;
  Offset _contextMenuPosition = Offset.zero;
  bool _contextMenuOpen = false;
  bool _isChatBlocked = false;
  int? _otherParticipantId;
  bool _notificationsEnabled = true;
  int? _muteDuration;
  DateTime? _muteUntil;
  bool _showMuteOptions = false;
  Timer? _tooltipTimer;
  Timer? _delayedFocusTimer;
  int? _highlightedMessageId;
  Timer? _highlightTimer;
  bool _hasMarkedAsRead = false;
  int? _contactId;

  List<CallHistory> _callHistory = [];
  bool _isLoadingCallHistory = false;
  bool _showCallHistory = false;

  bool _isSendingFiles = false;

  // WebSocket subscription
  StreamSubscription<Map<String, dynamic>>? _webSocketSubscription;

  Future<bool> get _canSendMessage async {
    final hasVoiceMessage = await _voiceService.hasVoiceMessage;
    return _controller.text.trim().isNotEmpty ||
        _attachedFiles.isNotEmpty ||
        hasVoiceMessage;
  }

  Future<bool> get _isSendButtonActive async {
    return await _canSendMessage;
  }

  @override
  void initState() {
    super.initState();

    _voiceService = VoiceService();
    _callService = CallService();
    _webSocketService = WebSocketService();
    _notificationService = NotificationService();

    _scrollController.addListener(_scrollListener);
    _tabController = TabController(
      length: EmojiData.categories.length,
      vsync: this,
    );

    _initializeServices();
    _loadMessages();
    _loadContactInfo();
    _loadPinnedMessages();
    _checkIfChatBlocked();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadNotificationSettings();
      await _initializeWebSocket();
    });

    _startNotificationCheckTimer();

    if (kIsWeb) {
      _setupWebContextMenu();
    }

    // Отложенный фокус на поле ввода
    _delayedFocusTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        focusNode.requestFocus();
        // Также запрашиваем фокус для RawKeyboardListener
        _rawKeyboardFocusNode.requestFocus();
      }
    });

    _controller.addListener(_updateSendButtonState);
    _setupVoiceServiceListeners();

    if (widget.forwardedMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleForwardedMessage();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _markChatAsRead();
        }
      });
    });
  }

  void _setupWebContextMenu() {
    if (!kIsWeb) return;
    PlatformUtils.blockContextMenu();
  }

  void _handleForwardedMessage() {
    final forwarded = widget.forwardedMessage!;
    _sendForwardedMessage(forwarded);
  }

  Future<void> _initializeWebSocket() async {
    try {
      await _notificationService.initialize(
        token: widget.token,
        baseUrl: widget.baseUrl,
        myUserId: widget.myUserId,
      );

      // Подписываемся на сообщения этого чата
      _webSocketSubscription = _webSocketService.onMessage.listen((event) {
        _handleNewWebSocketMessage(event);
      });

      print('✅ WebSocket initialized for chat ${widget.chatId}');
    } catch (e) {
      print('❌ Error initializing WebSocket: $e');
    }
  }

  void _handleNewWebSocketMessage(Map<String, dynamic> event) {
    final type = event['type'];

    if (type == 'new_message') {
      final messageData = event['message'];
      if (messageData == null) return;

      final senderId = messageData['user_id'] ?? messageData['userId'];

      // Не обрабатываем свои сообщения (они уже добавлены через отправку)
      if (senderId == widget.myUserId) return;

      // Создаем объект сообщения
      String? fileUrl = messageData['fileUrl'] ?? messageData['file_url'];
      if (fileUrl != null && !fileUrl.startsWith('http')) {
        fileUrl = '${widget.baseUrl}$fileUrl';
      }

      DateTime createdAt;
      try {
        createdAt = DateTime.parse(
                messageData['createdAt'] ?? messageData['created_at'])
            .toLocal();
      } catch (e) {
        createdAt = DateTime.now();
      }

      String text = messageData['text'] ?? '';

      // Декодируем зашифрованный текст если нужно
      if (text.isNotEmpty && _looksLikeEncrypted(text)) {
        try {
          text = _decodeMessageText(text);
        } catch (e) {
          // Игнорируем
        }
      }

      final newMessage = Message(
        id: messageData['id'],
        userId: senderId,
        text: text,
        createdAt: createdAt,
        fileUrl: fileUrl,
        typeId: messageData['typeId'] ?? messageData['type_id'] ?? 1,
        duration: messageData['duration'],
        isForwarded:
            messageData['isForwarded'] ?? messageData['is_forwarded'] ?? false,
        forwardedFrom:
            messageData['forwardedFrom'] ?? messageData['forwarded_from'],
      );

      // Добавляем сообщение в список
      setState(() {
        _messages.add(newMessage);
      });

      // Прокручиваем вниз, если пользователь уже внизу
      if (_scrollController.hasClients) {
        final isAtBottom = _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100;
        if (isAtBottom) {
          _scrollToBottom();
        }
      }

      // Помечаем как прочитанное, если окно активно
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _markChatAsRead();
      }
    }
  }

  void _setupVoiceServiceListeners() {
    _voiceService.onPlayingStateChanged = (isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
      });
    };

    _voiceService.onPlayingMessageIdChanged = (messageId) {
      setState(() {
        _playingMessageId = messageId;

        if (messageId != null) {
          _startProgressTimer();
        } else {
          _stopProgressTimer();
        }
      });
    };

    _voiceService.onRecordingStateChanged = () {
      setState(() {
        focusNode.requestFocus();
      });
    };

    _voiceService.onRecordingProgress = () {
      setState(() {});
    };
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _updateSendButtonState() {
    setState(() {});
  }

  Future<void> _initializeServices() async {
    try {
      await _voiceService.initialize();

      _microphonePermissionGranted =
          await _voiceService.checkMicrophonePermission();

      _audioAvailable = true;
      _audioInitialized = true;
    } catch (e) {
      _audioInitialized = true;
      _audioAvailable = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showInfoDialog(
          AppLocalizations.of(context)!.voiceMessages,
          AppLocalizations.of(context)!
              .voiceMessagesMicrophonePermissionRequired,
        );
      });
    }
  }

  void _showInfoDialog(String title, String message) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(fontSize: 18 * fontSizeScale)),
        content: Text(message, style: TextStyle(fontSize: 16 * fontSizeScale)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.gotIt,
                style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: MessengerTheme.lightAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadContactInfo() async {
    if (widget.recipientUserId == null) return;

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final userResponse = await dio.get(
        '${widget.baseUrl}/api/user',
        queryParameters: {'id': widget.recipientUserId},
      );

      if (userResponse.statusCode == 200) {
        final userData = userResponse.data;

        String name = userData['name']?.toString() ?? '';
        final nickname = userData['nickname']?.toString() ?? '';

        String formattedBirthday = AppLocalizations.of(context)!.notSpecified;
        if (userData['birthday'] != null) {
          try {
            final birthdayStr = userData['birthday'].toString();
            if (birthdayStr.isNotEmpty && birthdayStr != 'null') {
              final date = DateTime.parse(birthdayStr);
              formattedBirthday =
                  '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
            }
          } catch (e) {
            formattedBirthday = userData['birthday'].toString();
          }
        }

        final photoUrl = userData['photo_url'];

        bool isContact = false;
        int? contactId;
        String contactName = name;

        try {
          final contactsResponse =
              await dio.get('${widget.baseUrl}/api/contacts');
          if (contactsResponse.statusCode == 200) {
            final contactsData = contactsResponse.data;
            if (contactsData['success'] == true &&
                contactsData['contacts'] != null) {
              final contacts =
                  List<Map<String, dynamic>>.from(contactsData['contacts']);
              final contact = contacts.firstWhere(
                (c) => c['contact_user_id'] == widget.recipientUserId,
                orElse: () => <String, dynamic>{},
              );

              if (contact.isNotEmpty) {
                isContact = true;
                contactId = contact['id'];
                if (contact['contact_name'] != null &&
                    contact['contact_name'].toString().isNotEmpty) {
                  contactName = contact['contact_name'].toString();
                }
              }
            }
          }
        } catch (e) {
          // Игнорируем ошибки загрузки контактов
        }

        setState(() {
          _contactInfo = {
            'photoUrl': photoUrl,
            'name': contactName,
            'nickname': nickname,
            'birthday': formattedBirthday,
            'isContact': isContact,
            'isBlocked': _isChatBlocked,
          };
          _contactId = contactId;
        });
      } else {
        _setDefaultContactInfo();
      }
    } catch (e) {
      _setDefaultContactInfo();
    }
  }

  void _setDefaultContactInfo() {
    setState(() {
      _contactInfo = {
        'photoUrl': null,
        'name': '',
        'nickname': '@user_${widget.recipientUserId}',
        'birthday': AppLocalizations.of(context)!.notSpecified,
        'isContact': false,
        'isBlocked': _isChatBlocked,
      };
    });
  }

  Future<void> _refreshContactInfo() async {
    await _loadContactInfo();
  }

  @override
  void dispose() {
    _webSocketSubscription?.cancel();
    _controller.removeListener(_updateSendButtonState);
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    focusNode.dispose();
    _rawKeyboardFocusNode.dispose();
    _tabController.dispose();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _voiceService.dispose();
    _callService.dispose();
    _progressTimer?.cancel();
    _notificationCheckTimer?.cancel();
    _tooltipTimer?.cancel();
    _delayedFocusTimer?.cancel();
    _highlightTimer?.cancel();
    _closeContextMenu();

    _markChatAsRead();

    super.dispose();
  }

  Future<void> _loadPinnedMessages() async {
    if (widget.chatId <= 0) return;

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/chats/${widget.chatId}/pinned-messages',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> pinnedMessagesData = data['pinned_messages'] ?? [];

        final messages = pinnedMessagesData.map<Message>((msg) {
          try {
            String text = msg['text']?.toString() ?? '';

            if (text.isNotEmpty && _looksLikeEncrypted(text)) {
              try {
                text = _decodeMessageText(text);
              } catch (e) {
                text = '[Сообщение не может быть отображено]';
              }
            }

            if (text.isEmpty || text.trim().isEmpty) {
              final typeId = msg['typeId'] ?? msg['type_id'] ?? 1;
              switch (typeId) {
                case 2:
                  text = '🖼️ Изображение';
                  break;
                case 3:
                  text = '🎬 Видео';
                  break;
                case 4:
                  text = '🎤 Голосовое сообщение';
                  break;
                case 5:
                  text = '📎 Файл';
                  break;
                case 6:
                  text = '🖼️ GIF';
                  break;
                default:
                  text = '📝 Сообщение';
              }
            }

            return Message(
              id: msg['id'] ?? 0,
              userId: msg['userId'] ?? msg['user_id'] ?? 0,
              text: text,
              createdAt: DateTime.parse(msg['createdAt'] ?? msg['created_at'])
                  .toLocal(),
              typeId: msg['typeId'] ?? msg['type_id'] ?? 1,
            );
          } catch (e) {
            return Message(
              id: msg['id'] ?? 0,
              userId: msg['userId'] ?? msg['user_id'] ?? 0,
              text: '[Ошибка загрузки сообщения]',
              createdAt: DateTime.now(),
              typeId: 1,
            );
          }
        }).toList();

        setState(() {
          _pinnedMessages = messages;
        });
      }
    } catch (e) {
      // Игнорируем ошибки загрузки закрепленных сообщений
    }
  }

  bool _looksLikeEncrypted(String text) {
    if (text.isEmpty) return false;

    final hexRegex = RegExp(r'^[0-9a-fA-F]+$');
    if (hexRegex.hasMatch(text.replaceAll(':', ''))) {
      return true;
    }

    if (text.length % 4 == 0) {
      final base64Regex = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
      if (base64Regex.hasMatch(text)) {
        return true;
      }
    }

    return false;
  }

  String _decodeMessageText(String encryptedText) {
    if (encryptedText.isEmpty) return encryptedText;

    try {
      if (encryptedText.contains(':')) {
        final parts = encryptedText.split(':');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          final hexText = parts[0];
          if (_isValidHex(hexText)) {
            final bytes = _hexStringToBytes(hexText);
            final decoded = String.fromCharCodes(bytes);
            if (decoded.isNotEmpty && !_looksLikeEncrypted(decoded)) {
              return decoded;
            }
          }
        }
      } else if (_isValidHex(encryptedText)) {
        final bytes = _hexStringToBytes(encryptedText);
        final decoded = String.fromCharCodes(bytes);
        if (decoded.isNotEmpty && !_looksLikeEncrypted(decoded)) {
          return decoded;
        }
      }

      try {
        final decodedBytes = base64Decode(encryptedText);
        final decoded = String.fromCharCodes(decodedBytes);
        if (decoded.isNotEmpty && !_looksLikeEncrypted(decoded)) {
          return decoded;
        }
      } catch (e) {
        // Не base64
      }
    } catch (e) {
      // Игнорируем ошибки декодирования
    }

    return encryptedText;
  }

  bool _isValidHex(String str) {
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(str);
  }

  Uint8List _hexStringToBytes(String hexString) {
    hexString = hexString.replaceAll(':', '');
    if (hexString.length % 2 != 0) {
      hexString = '0$hexString';
    }

    final length = hexString.length;
    final bytes = Uint8List(length ~/ 2);
    for (var i = 0; i < length; i += 2) {
      final hex = hexString.substring(i, i + 2);
      final byte = int.tryParse(hex, radix: 16);
      if (byte != null) {
        bytes[i ~/ 2] = byte;
      }
    }
    return bytes;
  }

  Future<void> _pinMessage(Message message) async {
    if (widget.chatId <= 0) return;

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final response = await dio.post(
        '${widget.baseUrl}/api/chats/${widget.chatId}/pinned-messages',
        data: {'message_id': message.id},
      );

      if (response.statusCode == 200) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = message.copyWith(isPinned: true);
          }
        });

        await _loadPinnedMessages();
      }
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.failedToPinMessage);
    }
  }

  Future<void> _unpinMessage(Message message) async {
    if (widget.chatId <= 0) return;

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
      };

      final response = await dio.delete(
        '${widget.baseUrl}/api/chats/${widget.chatId}/pinned-messages/${message.id}',
      );

      if (response.statusCode == 200) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = message.copyWith(isPinned: false);
          }
        });

        await _loadPinnedMessages();
      }
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.failedToUnpinMessage);
    }
  }

  void _showMessageContextMenu(
      Message message, TapDownDetails details, BuildContext messageContext) {
    try {
      if (kIsWeb) {
        _selectedMessageForContextMenu = message;
        _showMessageContextMenuAtPosition(message, details.globalPosition);
      } else {
        final RenderBox renderBox =
            messageContext.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(details.localPosition);
        _selectedMessageForContextMenu = message;
        _showMessageContextMenuAtPosition(message, offset);
      }
    } catch (e) {
      _selectedMessageForContextMenu = message;
      _showMessageContextMenuAtPosition(message, details.globalPosition);
    }
  }

  void _showMessageContextMenuAtPosition(Message message, Offset position) {
    _closeContextMenu();

    _selectedMessageForContextMenu = message;
    _contextMenuPosition = position;

    final screenSize = MediaQuery.of(context).size;
    const double menuWidth = 220.0;
    const double menuHeight = 300.0;

    double adjustedX = position.dx;
    double adjustedY = position.dy;

    if (adjustedX + menuWidth > screenSize.width) {
      adjustedX = screenSize.width - menuWidth - 10;
    }

    if (adjustedY + menuHeight > screenSize.height) {
      adjustedY = screenSize.height - menuHeight - 10;
    }

    if (adjustedX < 10) {
      adjustedX = 10;
    }

    if (adjustedY < 10) {
      adjustedY = 10;
    }

    _contextMenuPosition = Offset(adjustedX, adjustedY);

    _contextMenuOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeContextMenu,
                onSecondaryTapDown: (_) => _closeContextMenu(),
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            Positioned(
              top: _contextMenuPosition.dy,
              left: _contextMenuPosition.dx,
              child: MouseRegion(
                onEnter: (_) => _contextMenuOpen = true,
                onExit: (_) {
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted && !_contextMenuOpen) {
                      _closeContextMenu();
                    }
                  });
                },
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(MessengerTheme.radiusMD),
                  color: Theme.of(context).colorScheme.surface,
                  child: Container(
                    width: 220,
                    constraints: const BoxConstraints(
                      maxHeight: 300,
                    ),
                    child: _buildContextMenuContent(message),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_contextMenuOverlay!);
    _contextMenuOpen = true;
  }

  Widget _buildContextMenuContent(Message message) {
    final favoritesProvider =
        Provider.of<FavoritesProvider>(context, listen: false);
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isFavorite = favoritesProvider.isMessageFavorite(message.id);
    final isMyMessage = message.userId == widget.myUserId;

    final isPinned = _pinnedMessages.any((pinned) => pinned.id == message.id);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem(
            icon: isFavorite ? Icons.star : Icons.star_border,
            text: isFavorite
                ? AppLocalizations.of(context)!.removeFromFavorites
                : AppLocalizations.of(context)!.addToFavorites,
            color: isFavorite
                ? Colors.amber
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            onTap: () {
              _closeContextMenu();
              if (isFavorite) {
                _removeFromFavorites(message);
              } else {
                _addToFavorites(message);
              }
            },
          ),
          _buildContextMenuItem(
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            text: isPinned
                ? AppLocalizations.of(context)!.unpinMessage
                : AppLocalizations.of(context)!.pinMessage,
            color: isPinned
                ? MessengerTheme.lightAccent
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            onTap: () {
              _closeContextMenu();
              if (isPinned) {
                _unpinMessage(message);
              } else {
                _pinMessage(message);
              }
            },
          ),
          _buildContextMenuItem(
            icon: Icons.reply,
            text: AppLocalizations.of(context)!.forward,
            color: MessengerTheme.lightAccent,
            onTap: () {
              _closeContextMenu();
              _forwardMessage(message);
            },
          ),
          _buildContextMenuItem(
            icon: Icons.copy,
            text: AppLocalizations.of(context)!.copyText,
            color: MessengerTheme.lightAccent,
            onTap: () {
              _closeContextMenu();
              _copyToClipboard(message.text);
            },
          ),
          if (isMyMessage)
            _buildContextMenuItem(
              icon: Icons.delete,
              text: AppLocalizations.of(context)!.delete,
              color: MessengerTheme.darkError,
              onTap: () {
                _closeContextMenu();
                _deleteMessage(message);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContextMenuItem({
    required IconData icon,
    required String text,
    Color? color,
    required VoidCallback onTap,
  }) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onHover: (hovering) {},
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 20 * fontSizeScale,
                  color: color ??
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14 * fontSizeScale,
                    color: color ??
                        Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _closeContextMenu() {
    if (_contextMenuOverlay != null) {
      _contextMenuOverlay!.remove();
      _contextMenuOverlay = null;
    }
    _selectedMessageForContextMenu = null;
    _contextMenuOpen = false;
  }

  void _addToFavorites(Message message) {
    final favoritesProvider =
        Provider.of<FavoritesProvider>(context, listen: false);

    favoritesProvider.addFavoriteMessage(
      originalMessageId: message.id,
      chatId: widget.chatId,
      chatTitle: widget.chatTitle,
      text: message.text,
      createdAt: message.createdAt,
      fileUrl: message.fileUrl,
      typeId: message.typeId,
      duration: message.duration,
      originalUserId: message.userId,
    );
  }

  void _removeFromFavorites(Message message) {
    final favoritesProvider =
        Provider.of<FavoritesProvider>(context, listen: false);

    try {
      final favMessage = favoritesProvider.favoriteMessages.firstWhere(
        (fav) => fav.originalMessageId == message.id,
      );

      favoritesProvider.removeFavoriteMessage(favMessage.id);
    } catch (e) {
      // Игнорируем
    }
  }

  Future<void> _sendForwardedMessage(Message message) async {
    if (_isChatBlocked) {
      _showErrorDialog(AppLocalizations.of(context)!.chatIsBlockedCannotSend);
      return;
    }

    try {
      final dio = Dio();

      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final forwardData = {
        'text': message.text,
        'chat_id': widget.chatId,
        'forwarded_message_id': message.id,
        'forwarded_from_chat_id': widget.chatId,
        'type_id': message.typeId,
      };

      if (message.fileUrl != null && message.fileUrl!.isNotEmpty) {
        try {
          final formData = FormData();

          String fileField = 'file';
          if (message.typeId == 4) fileField = 'voice_file';

          final response = await dio.get(
            message.fileUrl!,
            options: Options(responseType: ResponseType.bytes),
          );

          if (response.statusCode == 200) {
            final bytes = response.data as List<int>;
            final filename = message.fileUrl!.split('/').last;

            formData.files.add(MapEntry(
              fileField,
              MultipartFile.fromBytes(bytes, filename: filename),
            ));
            formData.fields.add(MapEntry('chat_id', widget.chatId.toString()));
            formData.fields.add(MapEntry('text', message.text));

            if (message.duration != null) {
              formData.fields
                  .add(MapEntry('duration', message.duration.toString()));
            }

            final uploadResponse = await dio.post(
              '${widget.baseUrl}/api/upload',
              data: formData,
            );

            if (uploadResponse.statusCode == 200) {
              final data = uploadResponse.data;

              final tempMsg = Message(
                id: const Uuid().v4().hashCode,
                userId: widget.myUserId,
                text: message.text,
                createdAt: DateTime.now(),
                fileUrl: data['file_url'],
                typeId: message.typeId,
                duration: message.duration,
                isForwarded: true,
                forwardedFrom: widget.chatTitle,
              );

              setState(() {
                _messages.add(tempMsg);
              });
              _scrollToBottom();

              final sendResponse = await dio.post(
                '${widget.baseUrl}/api/send-message',
                data: {
                  'text': message.text,
                  'chat_id': widget.chatId,
                  'file_url': data['file_url'],
                  'type_id': message.typeId,
                  'duration': message.duration,
                  'is_forwarded': true,
                  'forwarded_from': widget.chatTitle,
                },
              );

              if (sendResponse.statusCode == 200) {
                final sendData = sendResponse.data;
                setState(() {
                  final index = _messages.indexOf(tempMsg);
                  if (index != -1) {
                    _messages[index] = Message(
                      id: sendData['message_id'] ??
                          sendData['id'] ??
                          tempMsg.id,
                      userId: widget.myUserId,
                      text: message.text,
                      createdAt: DateTime.now(),
                      fileUrl: data['file_url'],
                      typeId: message.typeId,
                      duration: message.duration,
                      isForwarded: true,
                      forwardedFrom: widget.chatTitle,
                    );
                  }
                });

                _markChatAsRead();
              }
            }
          }
        } catch (e) {
          _showErrorDialog(AppLocalizations.of(context)!.failedToForwardFile);
        }
      } else {
        final tempMsg = Message(
          id: const Uuid().v4().hashCode,
          userId: widget.myUserId,
          text: message.text,
          createdAt: DateTime.now(),
          fileUrl: null,
          typeId: message.typeId,
          duration: message.duration,
          isForwarded: true,
          forwardedFrom: widget.chatTitle,
        );

        setState(() {
          _messages.add(tempMsg);
        });
        _scrollToBottom();

        final response = await dio.post(
          '${widget.baseUrl}/api/send-message',
          data: forwardData,
        );

        if (response.statusCode == 200) {
          final data = response.data;
          setState(() {
            final index = _messages.indexOf(tempMsg);
            if (index != -1) {
              _messages[index] = Message(
                id: data['message_id'] ?? data['id'] ?? tempMsg.id,
                userId: widget.myUserId,
                text: message.text,
                createdAt: DateTime.now(),
                fileUrl: null,
                typeId: message.typeId,
                duration: message.duration,
                isForwarded: true,
                forwardedFrom: widget.chatTitle,
              );
            }
          });

          _markChatAsRead();
        }
      }
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.errorForwardingMessage);
    }

    focusNode.requestFocus();
  }

  void _forwardMessage(Message message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ForwardMessagePage(
          message: message,
          myUserId: widget.myUserId,
          token: widget.token,
          baseUrl: widget.baseUrl,
        ),
      ),
    ).then((_) {
      focusNode.requestFocus();
    });
  }

  void _deleteMessage(Message message) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.deleteMessage,
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: Text(
          AppLocalizations.of(context)!.actionCannotBeUndone,
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _messages.remove(message);
              });
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.delete,
                style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: MessengerTheme.darkError)),
          ),
        ],
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        _searchResults.clear();
        _currentSearchIndex = -1;
        focusNode.requestFocus();
      }
    });
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
        _currentSearchIndex = -1;
      });
      return;
    }

    final results = _messages.where((message) {
      return message.text.toLowerCase().contains(query.toLowerCase());
    }).toList();

    setState(() {
      _searchResults = results;
      _currentSearchIndex = results.isNotEmpty ? 0 : -1;
    });
  }

  void _navigateToSearchResult(int direction) {
    if (_searchResults.isEmpty) return;

    setState(() {
      _currentSearchIndex =
          (_currentSearchIndex + direction) % _searchResults.length;
      if (_currentSearchIndex < 0)
        _currentSearchIndex = _searchResults.length - 1;
    });

    _scrollToMessage(_searchResults[_currentSearchIndex]);
  }

  void _scrollToMessage(Message? message) {
    if (message == null) return;

    final index = _messages.indexWhere((msg) => msg.id == message.id);
    if (index != -1 && _scrollController.hasClients) {
      _scrollController.animateTo(
        index * 100.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );

      setState(() {
        _showPinnedMessages = false;
      });

      _highlightMessage(message.id);
    }
  }

  void _highlightMessage(int messageId) {
    _highlightTimer?.cancel();

    setState(() {
      _highlightedMessageId = messageId;
    });

    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  Widget _buildNotificationStatusIndicator() {
    if (_notificationsEnabled) return const SizedBox.shrink();

    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    return Container(
      margin: EdgeInsets.only(right: 8 * fontSizeScale),
      child: Icon(
        Icons.notifications_off,
        size: 20 * fontSizeScale,
        color: Colors.white,
      ),
    );
  }

  Widget _buildPinnedMessagesAppBarButton() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    if (_pinnedMessages.isEmpty || _showSearch) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _showPinnedMessages = !_showPinnedMessages;
        });
      },
      child: Stack(
        children: [
          Container(
            padding: EdgeInsets.all(8 * fontSizeScale),
            child: Icon(
              Icons.push_pin,
              color: Colors.white,
              size: 24 * fontSizeScale,
            ),
          ),
          if (_pinnedMessages.isNotEmpty)
            Positioned(
              top: 4 * fontSizeScale,
              right: 4 * fontSizeScale,
              child: Container(
                padding: EdgeInsets.all(4 * fontSizeScale),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: BoxConstraints(
                  minWidth: 16 * fontSizeScale,
                  minHeight: 16 * fontSizeScale,
                ),
                child: Text(
                  _pinnedMessages.length.toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10 * fontSizeScale,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPinnedMessagesList() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    if (!_showPinnedMessages || _pinnedMessages.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    double listWidth;

    if (kIsWeb && screenWidth > 768) {
      listWidth = screenWidth / 2;
    } else {
      listWidth = screenWidth * 0.9;
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight,
      right: kIsWeb && screenWidth > 768 ? 0 : null,
      left: kIsWeb && screenWidth > 768 ? null : (screenWidth - listWidth) / 2,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showPinnedMessages = false;
          });
        },
        child: Container(
          width: listWidth,
          margin: EdgeInsets.symmetric(
            horizontal: kIsWeb && screenWidth > 768 ? 16 : 0,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(MessengerTheme.radiusMD),
            boxShadow: kIsWeb
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          constraints: BoxConstraints(
            maxHeight: 400 * fontSizeScale,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount: _pinnedMessages.length,
            itemBuilder: (context, index) {
              final message = _pinnedMessages[index];
              return _buildPinnedMessageItem(message, index);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedMessageItem(Message message, int index) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    if (message.text == null) {
      return const SizedBox.shrink();
    }

    final text = message.text.isNotEmpty ? message.text : '[Медиа-сообщение]';
    final shouldTruncate = _shouldTruncateText(text, fontSizeScale);
    final displayText = shouldTruncate ? _truncateText(text, 2) : text;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _showPinnedMessages = false;
          });
          _scrollToMessage(message);

          _markChatAsRead();
        },
        child: Container(
          padding: EdgeInsets.all(12 * fontSizeScale),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.push_pin,
                size: 16 * fontSizeScale,
                color: MessengerTheme.lightAccent,
              ),
              SizedBox(width: 8 * fontSizeScale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText,
                      style: TextStyle(
                        fontSize: 14 * fontSizeScale,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: shouldTruncate ? 2 : null,
                      overflow: shouldTruncate
                          ? TextOverflow.ellipsis
                          : TextOverflow.visible,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldTruncateText(String text, double fontSizeScale) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 14 * fontSizeScale,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    );

    final maxWidth =
        (MediaQuery.of(context).size.width * 0.9) - (40 * fontSizeScale);
    textPainter.layout(maxWidth: maxWidth);

    return textPainter.didExceedMaxLines;
  }

  String _truncateText(String text, int maxLines) {
    if (text.isEmpty) return text;

    final lines = text.split('\n');

    if (lines.length <= maxLines) {
      return text;
    }

    final truncatedLines = lines.take(maxLines).toList();

    return '${truncatedLines.join('\n')}...';
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else {
      return "${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year}";
    }
  }

  String _getMediaTypeText(Message message) {
    if (message.isImage) return AppLocalizations.of(context)!.photo;
    if (message.isVideo) return AppLocalizations.of(context)!.video;
    if (message.isVoice) return AppLocalizations.of(context)!.voiceMessage;
    if (message.isFile) return AppLocalizations.of(context)!.file;
    return AppLocalizations.of(context)!.message;
  }

  void _showContactMenu() {
    showDialog(
      context: context,
      builder: (context) => _buildContactMenu(),
    );
  }

  Widget _buildContactMenu() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    double modalWidth;
    double modalHeight;

    if (screenWidth > 1200) {
      modalWidth = 500;
      modalHeight = screenHeight * 0.7;
    } else if (screenWidth > 800) {
      modalWidth = 480;
      modalHeight = screenHeight * 0.75;
    } else if (screenWidth > 600) {
      modalWidth = screenWidth * 0.75;
      modalHeight = screenHeight * 0.8;
    } else {
      modalWidth = screenWidth * 0.9;
      modalHeight = screenHeight * 0.85;
    }

    return StatefulBuilder(
      builder: (context, setModalState) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: modalWidth,
            height: modalHeight,
            constraints: BoxConstraints(
              maxWidth: modalWidth,
              maxHeight: modalHeight,
            ),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFA000),
                        Color(0xFFFF5722),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 60 * fontSizeScale,
                        height: 60 * fontSizeScale,
                        decoration: BoxDecoration(
                          gradient:
                              MessengerTheme.getAvatarGradient(widget.chatId),
                          shape: BoxShape.circle,
                        ),
                        child: _contactInfo['photoUrl'] != null
                            ? ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(30 * fontSizeScale),
                                child: Image.network(
                                  _contactInfo['photoUrl'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(Icons.person,
                                        size: 30 * fontSizeScale,
                                        color: Colors.white);
                                  },
                                ),
                              )
                            : Icon(Icons.person,
                                size: 30 * fontSizeScale, color: Colors.white),
                      ),
                      SizedBox(width: 16 * fontSizeScale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _contactInfo['name'].isNotEmpty
                                  ? _contactInfo['name']
                                  : widget.chatTitle,
                              style: TextStyle(
                                fontSize: 22 * fontSizeScale,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            size: 28 * fontSizeScale, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                if (_showCallHistory)
                  _buildCallHistoryContent(setModalState)
                else
                  _buildMainMenuContent(setModalState),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainMenuContent(Function(void Function()) setModalState) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;

    return Expanded(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_contactInfo['nickname'].isNotEmpty) ...[
            ListTile(
              leading: Icon(Icons.alternate_email,
                  color: MessengerTheme.lightAccent, size: 24 * fontSizeScale),
              title: Text(
                AppLocalizations.of(context)!.nickname,
                style: TextStyle(fontSize: 16 * fontSizeScale),
              ),
              subtitle: Text(
                '@${_contactInfo['nickname']}',
                style: TextStyle(
                  fontSize: 14 * fontSizeScale,
                  color: MessengerTheme.lightAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Divider(color: isDarkMode ? Colors.white24 : Colors.black12),
          ],
          ListTile(
            leading: Icon(Icons.cake,
                color: MessengerTheme.lightAccent, size: 24 * fontSizeScale),
            title: Text(
              AppLocalizations.of(context)!.birthday,
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
            subtitle: Text(
              _contactInfo['birthday'],
              style: TextStyle(fontSize: 14 * fontSizeScale),
            ),
          ),
          Divider(color: isDarkMode ? Colors.white24 : Colors.black12),
          _buildMenuButton(
            icon: _contactInfo['isContact'] ? Icons.person : Icons.person_add,
            text: _contactInfo['isContact']
                ? AppLocalizations.of(context)!.editContact
                : AppLocalizations.of(context)!.addContact,
            onTap:
                _contactInfo['isContact'] ? _editContact : _showAddContactModal,
          ),
          _buildMenuButton(
            icon: Icons.history,
            text: AppLocalizations.of(context)!.callHistory,
            onTap: () {
              setModalState(() {
                _showCallHistory = true;
              });
              _loadCallHistory();
            },
          ),
          _buildMenuButton(
            icon: _isChatBlocked ? Icons.lock_open : Icons.block,
            text: _isChatBlocked
                ? AppLocalizations.of(context)!.unblockChat
                : AppLocalizations.of(context)!.blockChat,
            onTap: () {
              Navigator.pop(context);
              _showBlockDialog();
            },
            color: _isChatBlocked
                ? MessengerTheme.darkSuccess
                : MessengerTheme.darkError,
          ),
          if (_contactInfo['isContact'])
            _buildMenuButton(
              icon: Icons.delete,
              text: AppLocalizations.of(context)!.deleteContact,
              onTap: _deleteContact,
              color: MessengerTheme.darkError,
            ),
          Divider(color: isDarkMode ? Colors.white24 : Colors.black12),
          if (widget.chatId > 0)
            _buildMenuButton(
              icon: Icons.photo_library,
              text: AppLocalizations.of(context)!.media,
              onTap: _showMediaGallery,
            ),
          StatefulBuilder(
            builder: (context, innerSetState) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMenuButton(
                    icon: _notificationsEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                    text: _notificationsEnabled
                        ? AppLocalizations.of(context)!.disableNotifications
                        : AppLocalizations.of(context)!.enableNotifications,
                    onTap: () {
                      if (_notificationsEnabled) {
                        innerSetState(() {
                          _showMuteOptions = !_showMuteOptions;
                        });
                      } else {
                        _enableNotifications(innerSetState);
                      }
                    },
                    color: _notificationsEnabled ? null : Colors.grey,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _showMuteOptions && _notificationsEnabled
                        ? Container(
                            padding: EdgeInsets.only(
                                left: 56 * fontSizeScale,
                                right: 16 * fontSizeScale,
                                bottom: 8 * fontSizeScale),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildMuteOptionItem(
                                  title: AppLocalizations.of(context)!.forever,
                                  value: 0,
                                  setModalState: innerSetState,
                                ),
                                _buildMuteOptionItem(
                                  title:
                                      AppLocalizations.of(context)!.sevenDays,
                                  value: 10080,
                                  setModalState: innerSetState,
                                ),
                                _buildMuteOptionItem(
                                  title: AppLocalizations.of(context)!
                                      .twentyFourHours,
                                  value: 1440,
                                  setModalState: innerSetState,
                                ),
                                _buildMuteOptionItem(
                                  title:
                                      AppLocalizations.of(context)!.twelveHours,
                                  value: 720,
                                  setModalState: innerSetState,
                                ),
                                _buildMuteOptionItem(
                                  title:
                                      AppLocalizations.of(context)!.threeHours,
                                  value: 180,
                                  setModalState: innerSetState,
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
          if (widget.chatId > 0)
            _buildMenuButton(
              icon: Icons.delete_outline,
              text: AppLocalizations.of(context)!.clearHistory,
              onTap: _clearChatHistory,
            ),
        ],
      ),
    );
  }

  Widget _buildCallHistoryContent(Function(void Function()) setModalState) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    return Expanded(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16 * fontSizeScale),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, size: 24 * fontSizeScale),
                  onPressed: () {
                    setModalState(() {
                      _showCallHistory = false;
                    });
                  },
                ),
                SizedBox(width: 8 * fontSizeScale),
                Text(
                  AppLocalizations.of(context)!.callHistory,
                  style: TextStyle(
                    fontSize: 18 * fontSizeScale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_callHistory.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.delete,
                        color: MessengerTheme.darkError,
                        size: 24 * fontSizeScale),
                    onPressed: _showClearCallHistoryConfirmation,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoadingCallHistory
                ? Center(
                    child: CircularProgressIndicator(
                      color: MessengerTheme.lightAccent,
                    ),
                  )
                : _callHistory.isEmpty
                    ? Center(
                        child: Text(
                          AppLocalizations.of(context)!.noCallHistory,
                          style: TextStyle(
                            fontSize: 16 * fontSizeScale,
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _callHistory.length,
                        itemBuilder: (context, index) {
                          final call = _callHistory[index];
                          return _buildCallHistoryItem(call, index);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallHistoryItem(CallHistory call, int index) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isIncoming = call.callerId != widget.myUserId;
    final isMissed = call.status == 'missed';
    final isOutgoing = !isIncoming && !isMissed;

    Color statusColor = MessengerTheme.darkSuccess;
    IconData statusIcon = Icons.phone_callback;
    String statusText = '';

    if (isMissed) {
      statusColor = MessengerTheme.darkError;
      statusIcon = Icons.phone_missed;
      statusText = AppLocalizations.of(context)!.missed;
    } else if (isOutgoing) {
      statusColor = MessengerTheme.lightAccent;
      statusIcon = Icons.call_made;
      statusText = AppLocalizations.of(context)!.outgoing;
    } else {
      statusText = AppLocalizations.of(context)!.incoming;
    }

    return ListTile(
      leading: Container(
        width: 40 * fontSizeScale,
        height: 40 * fontSizeScale,
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20 * fontSizeScale),
        ),
        child: Icon(statusIcon, color: statusColor, size: 20 * fontSizeScale),
      ),
      title: Row(
        children: [
          Text(
            isIncoming ? widget.chatTitle : AppLocalizations.of(context)!.you,
            style: TextStyle(
              fontSize: 16 * fontSizeScale,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 8 * fontSizeScale),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: 6 * fontSizeScale, vertical: 2 * fontSizeScale),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4 * fontSizeScale),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 10 * fontSizeScale,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatCallDateTime(call.startTime),
            style: TextStyle(
              fontSize: 12 * fontSizeScale,
              color: Colors.grey,
            ),
          ),
          if (call.duration != null && call.duration! > 0)
            Text(
              '${AppLocalizations.of(context)!.duration}: ${_formatDuration(call.duration!)}',
              style: TextStyle(
                fontSize: 12 * fontSizeScale,
                color: Colors.grey,
              ),
            ),
        ],
      ),
      trailing: Text(
        _formatCallTime(call.startTime),
        style: TextStyle(
          fontSize: 14 * fontSizeScale,
          color: Colors.grey,
        ),
      ),
    );
  }

  String _formatCallDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final callDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (callDate == today) {
      return AppLocalizations.of(context)!.today;
    } else if (callDate == yesterday) {
      return AppLocalizations.of(context)!.yesterday;
    } else {
      return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year}';
    }
  }

  String _formatCallTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _loadCallHistory() async {
    if (widget.chatId <= 0) return;

    setState(() {
      _isLoadingCallHistory = true;
    });

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/calls/history/${widget.chatId}',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> historyData = data['calls'] ?? [];

        final history = historyData.map<CallHistory>((item) {
          return CallHistory(
            id: item['id'],
            chatId: item['chat_id'],
            callerId: item['caller_id'],
            recipientId: item['recipient_id'],
            startTime: DateTime.parse(item['created_at']),
            endTime: item['ended_at'] != null
                ? DateTime.parse(item['ended_at'])
                : null,
            duration: item['duration'],
            status: item['status'],
            callType: item['call_type'] ??
                (item['is_video_call'] == true ? 'video' : 'audio'),
          );
        }).toList();

        history.sort((a, b) => b.startTime.compareTo(a.startTime));

        setState(() {
          _callHistory = history;
          _isLoadingCallHistory = false;
        });
      } else {
        setState(() {
          _callHistory = [];
          _isLoadingCallHistory = false;
        });
      }
    } catch (e) {
      setState(() {
        _callHistory = [];
        _isLoadingCallHistory = false;
      });
    }
  }

  void _showClearCallHistoryConfirmation() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.clearCallHistory,
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: Text(
          AppLocalizations.of(context)!.areYouSureDeleteCallHistory,
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearCallHistory();
            },
            child: Text(
              AppLocalizations.of(context)!.delete,
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: MessengerTheme.darkError,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCallHistory() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final response = await dio.delete(
        '${widget.baseUrl}/api/calls/history/${widget.chatId}/clear',
      );

      if (response.statusCode == 200) {
        setState(() {
          _callHistory.clear();
        });
        _showTooltip(AppLocalizations.of(context)!.callHistoryCleared);
      } else {
        _showErrorDialog(
            AppLocalizations.of(context)!.failedToClearCallHistory);
      }
    } catch (e) {
      _showErrorDialog(
          '${AppLocalizations.of(context)!.errorClearingCallHistory}: $e');
    }
  }

  Widget _buildMuteOptionItem({
    required String title,
    required int value,
    required Function(void Function()) setModalState,
  }) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isSelected = _muteDuration == value && !_notificationsEnabled;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _muteNotifications(value, setModalState);
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12 * fontSizeScale),
          child: Row(
            children: [
              Radio<int>(
                value: value,
                groupValue: _muteDuration,
                onChanged: (int? value) {
                  if (value != null) {
                    _muteNotifications(value, setModalState);
                  }
                },
                activeColor: MessengerTheme.lightAccent,
              ),
              SizedBox(width: 8 * fontSizeScale),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14 * fontSizeScale,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    Color? color,
  }) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              vertical: 12 * fontSizeScale, horizontal: 16 * fontSizeScale),
          child: Row(
            children: [
              Icon(icon,
                  color: color ?? MessengerTheme.lightAccent,
                  size: 24 * fontSizeScale),
              SizedBox(width: 16 * fontSizeScale),
              Text(text,
                  style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: color ?? Theme.of(context).colorScheme.onSurface,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddContactModal() {
    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (context) => _buildAddContactDialog(),
    ).then((result) {
      if (result == true) {
        _refreshContactInfo();
      }
    });
  }

  Widget _buildAddContactDialog() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    TextEditingController nameController = TextEditingController(
        text: _contactInfo['name'].isNotEmpty
            ? _contactInfo['name']
            : widget.chatTitle);
    TextEditingController emailController = TextEditingController();
    TextEditingController noteController = TextEditingController();

    bool isLoading = false;
    String? emailError;

    nameController.text = widget.chatTitle;

    return StatefulBuilder(
      builder: (context, setState) {
        void validateEmail() {
          final email = emailController.text.trim();
          if (email.isEmpty) {
            setState(() {
              emailError = null;
            });
            return;
          }

          final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
          setState(() {
            emailError = emailRegex.hasMatch(email)
                ? null
                : AppLocalizations.of(context)!.enterValidEmail;
          });
        }

        Future<void> createContact() async {
          final name = nameController.text.trim();
          final email = emailController.text.trim();
          final note = noteController.text.trim();

          if (name.isEmpty) {
            _showTooltip(AppLocalizations.of(context)!.contactNameRequired);
            return;
          }

          if (email.isEmpty) {
            _showTooltip(AppLocalizations.of(context)!.contactEmailRequired);
            return;
          }

          if (emailError != null) {
            _showTooltip(AppLocalizations.of(context)!.enterValidEmail);
            return;
          }

          setState(() {
            isLoading = true;
          });

          try {
            final dio = Dio();
            dio.options.headers = {
              'Authorization': 'Bearer ${widget.token}',
              'Content-Type': 'application/json',
            };

            final response = await dio.post(
              '${widget.baseUrl}/api/contacts',
              data: {
                'contact_name': name,
                'contact_email': email,
                'note': note.isNotEmpty ? note : null,
              },
            );

            if (response.statusCode == 201) {
              await _refreshContactInfo();

              Navigator.pop(context, true);
              _showTooltip('Контакт "$name" успешно добавлен');
            } else {
              final errorData = response.data;
              _showTooltip(errorData['error'] ?? 'Не удалось добавить контакт');
            }
          } catch (e) {
            _showTooltip('Ошибка при добавлении контакта: $e');
          } finally {
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          }
        }

        emailController.addListener(validateEmail);

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxWidth: 500,
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(16 * fontSizeScale),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFA000),
                        Color(0xFFFF5722),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Добавить контакт',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20 * fontSizeScale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: Colors.white, size: 22 * fontSizeScale),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16 * fontSizeScale),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Имя контакта',
                          style: TextStyle(
                            fontSize: 16 * fontSizeScale,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameController,
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black87,
                            fontSize: 16 * fontSizeScale,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDarkMode
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(10 * fontSizeScale),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 14 * fontSizeScale,
                                vertical: 10 * fontSizeScale),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Email контакта',
                          style: TextStyle(
                            fontSize: 16 * fontSizeScale,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black87,
                            fontSize: 16 * fontSizeScale,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDarkMode
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(10 * fontSizeScale),
                              borderSide: BorderSide(
                                color: emailError != null
                                    ? Colors.red
                                    : Colors.transparent,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(10 * fontSizeScale),
                              borderSide: BorderSide(
                                color: emailError != null
                                    ? Colors.red
                                    : Colors.transparent,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(10 * fontSizeScale),
                              borderSide: BorderSide(
                                color: emailError != null
                                    ? Colors.red
                                    : const Color(0xFFFF9800),
                                width: 2,
                              ),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 14 * fontSizeScale,
                                vertical: 10 * fontSizeScale),
                          ),
                        ),
                        if (emailError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            emailError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Заметка',
                          style: TextStyle(
                            fontSize: 16 * fontSizeScale,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: noteController,
                          maxLines: 2,
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black87,
                            fontSize: 16 * fontSizeScale,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDarkMode
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(10 * fontSizeScale),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.all(12 * fontSizeScale),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isLoading
                                    ? null
                                    : () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 14 * fontSizeScale),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        10 * fontSizeScale),
                                  ),
                                  side: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white24
                                        : Colors.black12,
                                  ),
                                ),
                                child: Text(
                                  'Отмена',
                                  style: TextStyle(
                                    fontSize: 16 * fontSizeScale,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12 * fontSizeScale),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isLoading ? null : createContact,
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 14 * fontSizeScale),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        10 * fontSizeScale),
                                  ),
                                  backgroundColor: const Color(0xFFFF9800),
                                ),
                                child: isLoading
                                    ? SizedBox(
                                        width: 20 * fontSizeScale,
                                        height: 20 * fontSizeScale,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Text(
                                        'Добавить',
                                        style: TextStyle(
                                          fontSize: 16 * fontSizeScale,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addContact() async {
    Navigator.pop(context);

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final checkResponse = await dio.get(
        '${widget.baseUrl}/api/contacts',
      );

      if (checkResponse.statusCode == 200) {
        final data = checkResponse.data;
        if (data['success'] == true && data['contacts'] != null) {
          final contacts = List<Map<String, dynamic>>.from(data['contacts']);
          final existingContact = contacts.firstWhere(
            (c) => c['contact_user_id'] == widget.recipientUserId,
            orElse: () => <String, dynamic>{},
          );

          if (existingContact.isNotEmpty) {
            setState(() {
              _contactInfo['isContact'] = true;
            });
            _showTooltip('Контакт уже существует');
            return;
          }
        }
      }

      final response = await dio.post(
        '${widget.baseUrl}/api/contacts',
        data: {
          'contact_user_id': widget.recipientUserId,
          'contact_name': widget.chatTitle,
          'note': '',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _refreshContactInfo();
        _showTooltip('Контакт "${widget.chatTitle}" успешно добавлен');
      } else {
        _showErrorDialog('Не удалось добавить контакт');
      }
    } catch (e) {
      _showErrorDialog('Ошибка при добавлении контакта: $e');
    }
  }

  Future<void> _editContact() async {
    Navigator.pop(context);

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/contacts',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true && data['contacts'] != null) {
          final contacts = List<Map<String, dynamic>>.from(data['contacts']);

          final contact = contacts.firstWhere(
            (c) => c['contact_user_id'] == widget.recipientUserId,
            orElse: () => <String, dynamic>{},
          );

          if (contact.isNotEmpty) {
            final contactId = contact['id'];
            final currentName = contact['contact_name'] ?? widget.chatTitle;
            final currentNote = contact['note'] ?? '';

            // Показываем диалог редактирования
            _showEditContactDialog(contactId, currentName, currentNote);
          } else {
            _showErrorDialog('Контакт не найден');
          }
        }
      }
    } catch (e) {
      _showErrorDialog('Ошибка при загрузке контакта: $e');
    }
  }

  void _showEditContactDialog(
      int contactId, String currentName, String currentNote) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    TextEditingController nameController =
        TextEditingController(text: currentName);
    TextEditingController noteController =
        TextEditingController(text: currentNote);
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> updateContact() async {
              final name = nameController.text.trim();

              if (name.isEmpty) {
                _showTooltip('Имя контакта обязательно');
                return;
              }

              setState(() => isLoading = true);

              try {
                final dio = Dio();
                dio.options.headers = {
                  'Authorization': 'Bearer ${widget.token}',
                  'Content-Type': 'application/json',
                };

                final response = await dio.put(
                  '${widget.baseUrl}/api/contacts/$contactId',
                  data: {
                    'contact_name': name,
                    'note': noteController.text.trim(),
                  },
                );

                if (response.statusCode == 200) {
                  await _refreshContactInfo();
                  Navigator.pop(context);
                  _showTooltip('Контакт обновлен');
                } else {
                  _showTooltip('Не удалось обновить контакт');
                }
              } catch (e) {
                _showTooltip('Ошибка при обновлении контакта: $e');
              } finally {
                setState(() => isLoading = false);
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                constraints: const BoxConstraints(maxWidth: 500),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(16 * fontSizeScale),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFFA000),
                            Color(0xFFFF5722),
                          ],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Редактировать контакт',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20 * fontSizeScale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                color: Colors.white, size: 22 * fontSizeScale),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(16 * fontSizeScale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Имя контакта',
                            style: TextStyle(
                              fontSize: 16 * fontSizeScale,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: nameController,
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black87,
                              fontSize: 16 * fontSizeScale,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: isDarkMode
                                  ? const Color(0xFF2A2A2A)
                                  : const Color(0xFFF5F5F5),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(10 * fontSizeScale),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14 * fontSizeScale,
                                  vertical: 10 * fontSizeScale),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Заметка',
                            style: TextStyle(
                              fontSize: 16 * fontSizeScale,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: noteController,
                            maxLines: 3,
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black87,
                              fontSize: 16 * fontSizeScale,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: isDarkMode
                                  ? const Color(0xFF2A2A2A)
                                  : const Color(0xFFF5F5F5),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(10 * fontSizeScale),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  EdgeInsets.all(12 * fontSizeScale),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: isLoading
                                      ? null
                                      : () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                        vertical: 14 * fontSizeScale),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          10 * fontSizeScale),
                                    ),
                                  ),
                                  child: Text(
                                    'Отмена',
                                    style: TextStyle(
                                      fontSize: 16 * fontSizeScale,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12 * fontSizeScale),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : updateContact,
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                        vertical: 14 * fontSizeScale),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          10 * fontSizeScale),
                                    ),
                                    backgroundColor: const Color(0xFFFF9800),
                                  ),
                                  child: isLoading
                                      ? SizedBox(
                                          width: 20 * fontSizeScale,
                                          height: 20 * fontSizeScale,
                                          child:
                                              const CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        )
                                      : Text(
                                          'Сохранить',
                                          style: TextStyle(
                                            fontSize: 16 * fontSizeScale,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _refreshContactInfo();
    });
  }

  Future<void> _deleteContact() async {
    Navigator.pop(context);

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/contacts',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true && data['contacts'] != null) {
          final contacts = List<Map<String, dynamic>>.from(data['contacts']);

          final contact = contacts.firstWhere(
            (c) => c['contact_user_id'] == widget.recipientUserId,
            orElse: () => <String, dynamic>{},
          );

          if (contact.isNotEmpty) {
            final contactId = contact['id'];

            final fontSizeScale =
                Provider.of<FontScaleProvider>(context, listen: false)
                    .fontSizeScale;

            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(
                  'Удалить контакт?',
                  style: TextStyle(fontSize: 18 * fontSizeScale),
                ),
                content: Text(
                  'Вы уверены, что хотите удалить этот контакт?',
                  style: TextStyle(fontSize: 16 * fontSizeScale),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Отмена',
                      style: TextStyle(fontSize: 16 * fontSizeScale),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);

                      final deleteResponse = await dio.delete(
                        '${widget.baseUrl}/api/contacts/$contactId',
                      );

                      if (deleteResponse.statusCode == 200) {
                        await _refreshContactInfo();
                        _showTooltip('Контакт "${widget.chatTitle}" удален');
                      } else {
                        _showErrorDialog('Не удалось удалить контакт');
                      }
                    },
                    child: Text(
                      'Удалить',
                      style: TextStyle(
                          fontSize: 16 * fontSizeScale,
                          color: MessengerTheme.darkError),
                    ),
                  ),
                ],
              ),
            );
          } else {
            _showErrorDialog('Контакт не найден');
          }
        }
      }
    } catch (e) {
      _showErrorDialog('Ошибка при удалении контакта: $e');
    }
  }

  void _showMediaGallery() {
    if (widget.chatId <= 0) {
      _showErrorDialog('Нельзя открыть медиа для нового чата');
      return;
    }

    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (context) => MediaGalleryModal(
        chatId: widget.chatId,
        baseUrl: widget.baseUrl,
        token: widget.token,
      ),
    );
  }

  void _muteNotifications(int durationMinutes,
      [Function(void Function())? setModalState]) async {
    if (!mounted) return;

    final updateState = () {
      setState(() {
        _notificationsEnabled = false;
        _muteDuration = durationMinutes;
        _showMuteOptions = false;

        if (durationMinutes == 0) {
          _muteUntil = null;
        } else {
          _muteUntil = DateTime.now().add(Duration(minutes: durationMinutes));
        }
      });
    };

    if (setModalState != null) {
      setModalState(() {
        updateState();
      });
    } else {
      updateState();
    }

    await _updateNotificationSettingsOnServer(false, durationMinutes);

    final durationText = _getMuteDurationForTooltip(durationMinutes);
    final message = durationMinutes == 0
        ? 'Уведомления отключены навсегда'
        : 'Уведомления отключены на $durationText';

    _showTooltip(message);
  }

  void _enableNotifications([Function(void Function())? setModalState]) async {
    if (!mounted) return;

    final updateState = () {
      setState(() {
        _notificationsEnabled = true;
        _muteDuration = null;
        _muteUntil = null;
        _showMuteOptions = false;
      });
    };

    if (setModalState != null) {
      setModalState(() {
        updateState();
      });
    } else {
      updateState();
    }

    await _updateNotificationSettingsOnServer(true, null);

    _showTooltip('Уведомления включены');
  }

  void _clearChatHistory() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Очистить историю',
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: Text(
          'Вся история чата будет удалена',
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Отмена',
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _messages.clear();
              });
            },
            child: Text('Очистить',
                style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: MessengerTheme.darkError)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkIfChatBlocked() async {
    if (widget.recipientUserId == null) {
      setState(() => _isChatBlocked = false);
      return;
    }

    final blockedUsersProvider =
        Provider.of<BlockedUsersProvider>(context, listen: false);
    final isBlocked =
        blockedUsersProvider.isUserBlocked(widget.recipientUserId!);
    setState(() => _isChatBlocked = isBlocked);
    _otherParticipantId = widget.recipientUserId;
  }

  Future<void> _loadNotificationSettings() async {
    if (widget.chatId <= 0) {
      setState(() {
        _notificationsEnabled = true;
        _muteDuration = null;
        _muteUntil = null;
      });
      return;
    }

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/chats/${widget.chatId}/notification-settings',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _notificationsEnabled = data['notifications_enabled'] ?? true;
          _muteDuration = data['mute_duration'];

          if (data['muted_until'] != null) {
            try {
              _muteUntil = DateTime.parse(data['muted_until']);
            } catch (e) {
              _muteUntil = null;
            }
          }

          if (_muteUntil != null && _muteUntil!.isBefore(DateTime.now())) {
            _notificationsEnabled = true;
            _muteDuration = null;
            _muteUntil = null;
            _updateNotificationSettingsOnServer(true, null);
          }
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _notificationsEnabled = true;
          _muteDuration = null;
          _muteUntil = null;
        });
      } else {
        setState(() {
          _notificationsEnabled = true;
          _muteDuration = null;
          _muteUntil = null;
        });
      }
    } catch (e) {
      setState(() {
        _notificationsEnabled = true;
        _muteDuration = null;
        _muteUntil = null;
      });
    }
  }

  void _startNotificationCheckTimer() {
    _notificationCheckTimer =
        Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_muteUntil != null && _muteUntil!.isBefore(DateTime.now())) {
        if (mounted) {
          setState(() {
            _notificationsEnabled = true;
            _muteDuration = null;
            _muteUntil = null;
          });
          _updateNotificationSettingsOnServer(true, null);
        }
      }
    });
  }

  Future<void> _updateNotificationSettingsOnServer(
      bool enabled, int? durationMinutes) async {
    if (widget.chatId <= 0) return;

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final Map<String, dynamic> data = {
        'notifications_enabled': enabled,
      };

      if (!enabled && durationMinutes != null) {
        data['mute_duration'] = durationMinutes;
        if (durationMinutes > 0) {
          final muteUntil =
              DateTime.now().add(Duration(minutes: durationMinutes));
          data['muted_until'] = muteUntil.toIso8601String();
        } else {
          data['muted_until'] = null;
        }
      } else {
        data['mute_duration'] = null;
        data['muted_until'] = null;
      }

      final response = await dio.put(
        '${widget.baseUrl}/api/chats/${widget.chatId}/notification-settings',
        data: data,
      );

      if (response.statusCode != 200 && response.statusCode != 404) {
        print('Error updating notification settings: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating notification settings: $e');
    }
  }

  String _getMuteDurationForTooltip(int durationMinutes) {
    if (durationMinutes == 0) return 'навсегда';
    if (durationMinutes == 180) return '3 часа';
    if (durationMinutes == 720) return '12 часов';
    if (durationMinutes == 1440) return '24 часа';
    if (durationMinutes == 10080) return '7 дней';

    final days = durationMinutes ~/ 1440;
    if (days > 0) {
      return '$days дн';
    }

    final hours = durationMinutes ~/ 60;
    if (hours > 0) {
      return '$hours ч';
    }

    return '$durationMinutes мин';
  }

  void _showTooltip(String message) {
    _tooltipTimer?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(10,
            kToolbarHeight + MediaQuery.of(context).padding.top + 10, 10, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 6,
      ),
    );

    _tooltipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  Future<void> _markChatAsRead() async {
    if (widget.chatId <= 0 || _hasMarkedAsRead) return;

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final response = await dio.post(
        '${widget.baseUrl}/api/chats/${widget.chatId}/mark-read',
      );

      if (response.statusCode == 200) {
        _hasMarkedAsRead = true;
        print('✅ Chat marked as read: ${widget.chatId}');
      } else {
        print('⚠️ Failed to mark chat as read: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error marking chat as read: $e');
    }
  }

  Future<void> _startCall({CallType callType = CallType.audio}) async {
    if (_isChatBlocked) {
      _showErrorDialog('Чат заблокирован, нельзя совершить звонок');
      return;
    }

    if (widget.recipientUserId == null) {
      _showErrorDialog('Нельзя совершить звонок этому пользователю');
      return;
    }

    try {
      await _callService.startCall(
        token: widget.token,
        baseUrl: widget.baseUrl,
        myUserId: widget.myUserId,
        recipientId: widget.recipientUserId!,
        chatId: widget.chatId,
        recipientName: widget.chatTitle,
        recipientAvatar: _contactInfo['photoUrl'],
        context: context,
        callType: callType,
      );
    } catch (e) {
      _showErrorDialog('Не удалось начать звонок: $e');
    }
  }

  void _scrollListener() {
    if (_scrollController.offset <
        _scrollController.position.maxScrollExtent - 300) {
      if (!_showScrollDownButton) setState(() => _showScrollDownButton = true);
    } else {
      if (_showScrollDownButton) setState(() => _showScrollDownButton = false);
    }

    if (_scrollController.offset <=
        _scrollController.position.minScrollExtent + 100) {
      _loadMoreMessages();
    }

    if (_scrollController.offset >=
        _scrollController.position.maxScrollExtent - 100) {
      _markChatAsRead();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && mounted) {
        try {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );

          _markChatAsRead();
        } catch (e) {
          try {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
            _markChatAsRead();
          } catch (e) {
            // Игнорируем
          }
        }
      }
    });
  }

  Future<void> _loadMessages({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      Map<String, dynamic> queryParams = {
        'chat_id': widget.chatId,
        'page': _currentPage,
        'limit': 20,
      };

      if (widget.chatId == 0 && widget.recipientUserId != null) {
        queryParams['user_id'] = widget.recipientUserId;
      }

      final response = await dio.get(
        '${widget.baseUrl}/api/chat-messages',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> messagesData = data['messages'] ?? [];

        final List<Message> loadedMessages = messagesData.map((messageJson) {
          String? fileUrl = messageJson['fileUrl'] ?? messageJson['file_url'];
          if (fileUrl != null && !fileUrl.startsWith('http')) {
            fileUrl =
                '${widget.baseUrl}${fileUrl.startsWith('/') ? '' : '/'}$fileUrl';
          }

          DateTime createdAt;
          try {
            final utcTime = DateTime.parse(
                messageJson['createdAt'] ?? messageJson['created_at']);
            createdAt = utcTime.toLocal();
          } catch (e) {
            createdAt = DateTime.now();
          }

          String text = messageJson['text'] ?? '';
          if (text.isNotEmpty && _looksLikeEncrypted(text)) {
            try {
              text = _decodeMessageText(text);
            } catch (e) {
              // Игнорируем
            }
          }

          int typeId = messageJson['typeId'] ?? messageJson['type_id'] ?? 1;

          return Message(
            id: messageJson['id'],
            userId: messageJson['userId'] ?? messageJson['user_id'],
            text: text,
            createdAt: createdAt,
            fileUrl: fileUrl,
            typeId: typeId,
            duration: messageJson['duration'],
            isForwarded: messageJson['isForwarded'] ??
                messageJson['is_forwarded'] ??
                false,
            forwardedFrom:
                messageJson['forwardedFrom'] ?? messageJson['forwarded_from'],
          );
        }).toList();

        setState(() {
          if (loadMore) {
            _messages.insertAll(0, loadedMessages);
          } else {
            _messages.clear();
            _messages.addAll(loadedMessages);
          }
          _isLoading = false;

          final pagination = data['pagination'];
          if (pagination != null) {
            _hasMoreMessages =
                pagination['hasMore'] ?? (loadedMessages.length == 20);
          } else {
            _hasMoreMessages = loadedMessages.length == 20;
          }
        });

        if (!loadMore) {
          _scrollToBottom();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            focusNode.requestFocus();
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          _showErrorDialog('Чат не найден или еще не создан');
        } else {
          _showErrorDialog('Ошибка загрузки сообщений: ${e.message}');
        }
      } else {
        _showErrorDialog('Ошибка загрузки сообщений: $e');
      }
    }
  }

  int _getTypeIdFromType(String type) {
    switch (type) {
      case 'text':
        return 1;
      case 'image':
        return 2;
      case 'video':
        return 3;
      case 'audio':
      case 'voice':
        return 4;
      case 'file':
        return 5;
      case 'gif':
        return 6;
      default:
        return 1;
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoading || !_hasMoreMessages) return;

    setState(() {
      _currentPage++;
    });

    await _loadMessages(loadMore: true);
  }

  Future<void> _startRecording() async {
    if (_isChatBlocked) {
      _showErrorDialog('Чат заблокирован, нельзя отправить сообщение');
      return;
    }

    if (!_audioInitialized) {
      _showErrorDialog('Аудио сервис не инициализирован');
      return;
    }

    if (!_microphonePermissionGranted) {
      _showErrorDialog('Нет разрешения на использование микрофона');
      return;
    }

    try {
      await _voiceService.startRecording();
    } catch (e) {
      String errorMessage = 'Не удалось начать запись';

      if (kIsWeb) {
        errorMessage += '. Для веба требуется HTTPS и разрешение на микрофон';
      } else {
        errorMessage +=
            '. Проверьте разрешения на микрофон в настройках приложения';
      }

      _showErrorDialog(errorMessage);
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _voiceService.stopRecording();
    } catch (e) {
      _showErrorDialog('Ошибка при остановке записи');
    }
  }

  Future<void> _deleteRecording() async {
    try {
      await _voiceService.deleteRecording();
    } catch (e) {
      _showErrorDialog('Ошибка при удалении записи');
    }
  }

  Future<void> _sendVoiceMessage() async {
    if (_isChatBlocked) {
      _showErrorDialog('Чат заблокирован, нельзя отправить сообщение');
      return;
    }

    final hasVoiceMessage = await _voiceService.hasVoiceMessage;
    if (!hasVoiceMessage) {
      _showErrorDialog('Сначала запишите голосовое сообщение');
      return;
    }

    final duration = Duration(seconds: _voiceService.recordingSeconds);

    final tempMsg = Message(
      id: const Uuid().v4().hashCode,
      userId: widget.myUserId,
      text: 'Голосовое сообщение',
      createdAt: DateTime.now(),
      fileUrl: null,
      typeId: 4,
      duration: duration.inSeconds,
    );

    setState(() {
      _messages.add(tempMsg);
    });
    _scrollToBottom();

    try {
      final uploadedMessage = await _voiceService.uploadVoiceMessage(
        token: widget.token,
        baseUrl: widget.baseUrl,
        chatId: widget.chatId,
        myUserId: widget.myUserId,
        duration: duration,
      );

      setState(() {
        final index = _messages.indexOf(tempMsg);
        if (index != -1) {
          _messages[index] = Message(
            id: uploadedMessage.id,
            userId: uploadedMessage.userId,
            text: uploadedMessage.text,
            createdAt: DateTime.now(),
            fileUrl: uploadedMessage.fileUrl,
            typeId: uploadedMessage.typeId,
            duration: uploadedMessage.duration,
          );
        }
      });

      focusNode.requestFocus();

      _markChatAsRead();
    } catch (e) {
      _showErrorDialog('Ошибка при отправке голосового сообщения');

      setState(() {
        _messages.removeWhere((msg) => msg.id == tempMsg.id);
      });

      focusNode.requestFocus();
    }
  }

  Future<void> _playVoiceMessage(Message message) async {
    if (!_audioInitialized) {
      _showErrorDialog('Аудио сервис не инициализирован');
      return;
    }

    try {
      if (_isPlaying && _playingMessageId == message.id) {
        await _voiceService.pausePlaying();
      } else {
        await _voiceService.playVoiceMessage(message, message.id);
      }
    } catch (e) {
      _showErrorDialog('Не удалось воспроизвести голосовое сообщение');

      _voiceService.onPlayingStateChanged?.call(false);
      _voiceService.onPlayingMessageIdChanged?.call(null);
    }
  }

  Future<void> _attachAnyFile() async {
    try {
      final file = await _mediaService.pickAnyFile();
      if (file == null) return;

      setState(() {
        _attachedFiles.add(file);
        _hasAttachments = true;
      });

      focusNode.requestFocus();
    } catch (e) {
      _showErrorDialog('Ошибка при выборе файла');
    }
  }

  Future<void> _attachFile() async {
    try {
      final fontSizeScale =
          Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Выберите тип файла',
            style: TextStyle(fontSize: 18 * fontSizeScale),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.image, color: MessengerTheme.lightAccent),
                title: const Text('Изображения'),
                onTap: () async {
                  Navigator.pop(context);
                  final files = await _mediaService.pickMultipleImages();
                  if (files.isNotEmpty) {
                    setState(() {
                      _attachedFiles.addAll(files);
                      _hasAttachments = true;
                    });
                  }
                  focusNode.requestFocus();
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.attach_file, color: MessengerTheme.lightAccent),
                title: const Text('Любой файл'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _mediaService.pickAnyFile();
                  if (file != null) {
                    setState(() {
                      _attachedFiles.add(file);
                      _hasAttachments = true;
                    });
                  }
                  focusNode.requestFocus();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Ошибка при выборе файла');
    }
  }

  void _removeAttachedFile(int index) {
    setState(() {
      _attachedFiles.removeAt(index);
      _hasAttachments = _attachedFiles.isNotEmpty;
    });
  }

  Future<void> _sendMessage() async {
    if (_isChatBlocked) {
      _showErrorDialog('Чат заблокирован, нельзя отправить сообщение');
      return;
    }

    final text = _controller.text.trim();

    final hasVoiceMessage = await _voiceService.hasVoiceMessage;
    if (hasVoiceMessage) {
      await _sendVoiceMessage();
      return;
    }

    if (_attachedFiles.isNotEmpty) {
      await _sendMessageWithFiles(text);
      return;
    }

    if (text.isNotEmpty) {
      await sendTextOnly(text);
    }
  }

  Future<void> sendTextOnly(String text) async {
    final tempMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      userId: widget.myUserId,
      text: text,
      createdAt: DateTime.now(),
      typeId: 1,
    );

    setState(() {
      _messages.add(tempMsg);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final Map<String, dynamic> data = {
        'text': text,
        'chat_id': widget.chatId,
        'type_id': 1,
      };

      if (widget.chatId == 0 && widget.recipientUserId != null) {
        data['user_id'] = widget.recipientUserId!;
      }

      final response = await dio.post(
        '${widget.baseUrl}/api/send-message',
        data: data,
      );

      if (response.statusCode == 200) {
        final responseData = response.data;

        final newMessageId = responseData['message_id'];
        final newChatId = responseData['chat_id'];

        setState(() {
          final index = _messages.indexWhere((msg) => msg.id == tempMsg.id);
          if (index != -1) {
            _messages[index] = Message(
              id: newMessageId ?? tempMsg.id,
              userId: widget.myUserId,
              text: text,
              createdAt: DateTime.parse(responseData['created_at'] ??
                  DateTime.now().toIso8601String()),
              typeId: 1,
            );
          }
        });

        _markChatAsRead();
      } else {
        setState(() {
          _messages.removeWhere((msg) => msg.id == tempMsg.id);
        });

        _showErrorDialog(
            'Ошибка ${response.statusCode}: ${response.data['error'] ?? 'Неизвестная ошибка'}');
      }
    } catch (e) {
      setState(() {
        _messages.removeWhere((msg) => msg.id == tempMsg.id);
      });

      if (e is DioException) {
        _showErrorDialog('Ошибка сети: ${e.message}');
      } else {
        _showErrorDialog('Ошибка отправки сообщения: $e');
      }
    }

    _clearInputs();
  }

  Future<void> _sendMessageWithFiles(String text) async {
    if (_attachedFiles.isEmpty) return;

    setState(() {
      _isSendingFiles = true;
    });

    try {
      for (var file in _attachedFiles) {
        final tempId = const Uuid().v4().hashCode;

        final tempTypeId = _mediaService.getTypeIdFromFilename(file.name);

        final tempMsg = Message(
          id: tempId,
          userId: widget.myUserId,
          text: text,
          createdAt: DateTime.now(),
          fileUrl: file.path,
          typeId: tempTypeId,
        );

        setState(() {
          _messages.add(tempMsg);
        });

        _scrollToBottom();
        await Future.delayed(const Duration(milliseconds: 100));

        final formData = FormData();

        if (kIsWeb) {
          final bytes = await file.readAsBytes();
          formData.files.add(MapEntry(
            'file',
            MultipartFile.fromBytes(bytes, filename: file.name),
          ));
        } else {
          formData.files.add(MapEntry(
            'file',
            await MultipartFile.fromFile(file.path!, filename: file.name),
          ));
        }

        if (text.isNotEmpty) {
          formData.fields.add(MapEntry('text', text));
        }
        formData.fields.add(MapEntry('chat_id', widget.chatId.toString()));

        final dio = Dio();
        dio.options.headers = {
          'Authorization': 'Bearer ${widget.token}',
        };

        print('📤 Отправка файла: ${file.name}');

        final response = await dio.post(
          '${widget.baseUrl}/api/upload',
          data: formData,
        );

        print('📥 Ответ сервера: ${response.statusCode}');
        print('📦 Данные: ${response.data}');

        if (response.statusCode == 200 && mounted) {
          final data = response.data;

          setState(() {
            _messages.removeWhere((msg) => msg.id == tempId);

            DateTime createdAt;
            try {
              createdAt =
                  DateTime.parse(data['created_at'] ?? data['createdAt']);
            } catch (e) {
              createdAt = DateTime.now();
            }

            final serverTypeId = data['type_id'] ?? data['typeId'];

            print('📊 Тип файла от сервера: $serverTypeId');

            final newMessage = Message(
              id: data['message_id'] ?? data['id'],
              userId: widget.myUserId,
              text: text.isNotEmpty ? text : '',
              createdAt: createdAt,
              fileUrl: data['file_url'] ?? data['fileUrl'],
              typeId: serverTypeId is int ? serverTypeId : 5,
            );

            _messages.add(newMessage);
          });

          _scrollToBottom();
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          throw Exception('Ошибка загрузки файла: ${response.statusCode}');
        }
      }

      _markChatAsRead();
    } catch (e) {
      print('❌ Ошибка отправки файла: $e');
      _showErrorDialog('Ошибка при отправке файлов: $e');
    } finally {
      setState(() {
        _isSendingFiles = false;
      });
      _clearInputs();
    }
  }

  void _clearInputs() {
    setState(() {
      _controller.clear();
      _attachedFiles.clear();
      _hasAttachments = false;
      _showEmojiPicker = false;
    });

    focusNode.requestFocus();
  }

  void _addEmoji(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, emoji);
    _controller.text = newText;
    _controller.selection = selection.copyWith(
      baseOffset: selection.start + emoji.length,
      extentOffset: selection.start + emoji.length,
    );
    focusNode.requestFocus();
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
    if (!_showEmojiPicker) {
      focusNode.requestFocus();
    }
  }

  Future<void> _openVideo(String videoUrl) async {
    try {
      setState(() {
        _currentVideoUrl = videoUrl;
        _showVideoModal = true;
      });

      _videoPlayerController = VideoPlayerController.network(videoUrl);
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: MessengerTheme.lightAccent,
          handleColor: MessengerTheme.lightAccent,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.grey[300]!,
        ),
        placeholder: Container(
          color: Colors.grey[900],
          child: Center(
            child: CircularProgressIndicator(color: MessengerTheme.lightAccent),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Container(
            color: Colors.grey[900],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 50),
                  const SizedBox(height: 16),
                  Text(
                    'Ошибка загрузки видео',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      );

      setState(() {});
    } catch (e) {
      _showVideoErrorDialog(videoUrl);
      _closeVideoModal();
    }
  }

  void _closeVideoModal() {
    setState(() {
      _showVideoModal = false;
      _currentVideoUrl = null;
    });
    _chewieController?.dispose();
    _chewieController = null;
    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    focusNode.requestFocus();
  }

  void _showVideoErrorDialog(String videoUrl) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error,
                color: MessengerTheme.darkError, size: 24 * fontSizeScale),
            SizedBox(width: 8 * fontSizeScale),
            Text(
              'Ошибка',
              style: TextStyle(fontSize: 18 * fontSizeScale),
            ),
          ],
        ),
        content: Text(
          'Не удалось загрузить видео. Попробуйте открыть в браузере',
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Закрыть',
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _copyToClipboard(videoUrl);
            },
            child: Text(
              'Скопировать ссылку',
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: MessengerTheme.lightAccent,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await PlatformUtils.copyToClipboard(text);
    _showTooltip('Скопировано в буфер обмена');
    focusNode.requestFocus();
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  focusNode.requestFocus();
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Ошибка',
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: Text(
          message,
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              focusNode.requestFocus();
            },
            child: Text('OK',
                style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: MessengerTheme.lightAccent)),
          ),
        ],
      ),
    );
  }

  String _formatShortDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildForwardedMessageHeader(Message msg) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    if (!msg.isForwarded ||
        msg.forwardedFrom == null ||
        msg.forwardedFrom!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.only(bottom: 4 * fontSizeScale),
      padding: EdgeInsets.symmetric(
          horizontal: 8 * fontSizeScale, vertical: 4 * fontSizeScale),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6 * fontSizeScale),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.reply,
              size: 12 * fontSizeScale,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          SizedBox(width: 4 * fontSizeScale),
          Text(
            'От: ${msg.forwardedFrom!}',
            style: TextStyle(
              fontSize: 10 * fontSizeScale,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedWarning() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    if (!_isChatBlocked) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(12 * fontSizeScale),
      color: MessengerTheme.darkError.withOpacity(0.05),
      child: Row(
        children: [
          Icon(Icons.block,
              color: MessengerTheme.darkError, size: 24 * fontSizeScale),
          SizedBox(width: 8 * fontSizeScale),
          Expanded(
            child: Text(
              'Чат заблокирован. Вы не можете отправлять сообщения',
              style: TextStyle(
                fontSize: 14 * fontSizeScale,
                color: MessengerTheme.darkError.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog() {
    final blockedUsersProvider =
        Provider.of<BlockedUsersProvider>(context, listen: false);
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    if (_otherParticipantId == null) {
      _showErrorDialog('Нельзя заблокировать этот чат');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isChatBlocked
                  ? 'Вы уверены, что хотите разблокировать чат?'
                  : 'Вы уверены, что хотите заблокировать чат?',
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
            const SizedBox(height: 8),
            if (!_isChatBlocked)
              Text(
                'Заблокированный пользователь не сможет писать вам, а вы - ему',
                style: TextStyle(
                  fontSize: 12 * fontSizeScale,
                  color: MessengerTheme.darkError,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Отмена',
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          TextButton(
            onPressed: () {
              if (_isChatBlocked) {
                blockedUsersProvider.unblockUser(_otherParticipantId!);
                setState(() {
                  _isChatBlocked = false;
                });
              } else {
                blockedUsersProvider.blockUser(
                    _otherParticipantId!, widget.chatTitle);
                setState(() {
                  _isChatBlocked = true;
                });
              }

              Navigator.pop(context);
            },
            child: Text(
              _isChatBlocked ? 'Разблокировать' : 'Заблокировать',
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: _isChatBlocked
                    ? MessengerTheme.darkSuccess
                    : MessengerTheme.darkError,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceMessage(Message msg, bool isMe) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isPlaying = _isPlaying && _playingMessageId == msg.id;
    final duration = msg.duration ?? 0;

    return Container(
      constraints: BoxConstraints(maxWidth: 280 * fontSizeScale),
      padding: EdgeInsets.all(12 * fontSizeScale),
      decoration: BoxDecoration(
        color: isMe
            ? MessengerTheme.lightAccent
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16 * fontSizeScale),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: isMe ? Colors.white : MessengerTheme.lightAccent,
                  size: 28 * fontSizeScale,
                ),
                onPressed: () => _playVoiceMessage(msg),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                    minWidth: 40 * fontSizeScale,
                    minHeight: 40 * fontSizeScale),
              ),
              SizedBox(width: 8 * fontSizeScale),
              _buildAudioVisualization(msg, isMe, isPlaying),
              SizedBox(width: 12 * fontSizeScale),
              Text(
                _formatShortDuration(duration),
                style: TextStyle(
                  fontSize: 14 * fontSizeScale,
                  color: isMe
                      ? Colors.white70
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (isPlaying && duration > 0) ...[
            SizedBox(height: 8 * fontSizeScale),
            _buildAudioProgressBar(msg),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioProgressBar(Message msg) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    return StreamBuilder<Duration>(
      stream: _voiceService.positionStream,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        final duration = Duration(seconds: msg.duration ?? 1);
        final progress = duration.inSeconds > 0
            ? position.inSeconds / duration.inSeconds
            : 0.0;

        return Container(
          height: 4 * fontSizeScale,
          width: 200 * fontSizeScale,
          decoration: BoxDecoration(
            color: Colors.grey[300]!.withOpacity(0.5),
            borderRadius: BorderRadius.circular(2 * fontSizeScale),
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300]!.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2 * fontSizeScale),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0).toDouble(),
                child: Container(
                  decoration: BoxDecoration(
                    color: MessengerTheme.lightAccent,
                    borderRadius: BorderRadius.circular(2 * fontSizeScale),
                  ),
                ),
              ),
              if (position.inSeconds > 0)
                Positioned(
                  left: (progress.clamp(0.0, 1.0).toDouble() *
                          200 *
                          fontSizeScale) -
                      15 * fontSizeScale,
                  top: -20 * fontSizeScale,
                  child: Text(
                    _formatShortDuration(position.inSeconds),
                    style: TextStyle(
                      fontSize: 10 * fontSizeScale,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAudioVisualization(Message msg, bool isMe, bool isPlaying) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    return Container(
      height: 30 * fontSizeScale,
      width: 80 * fontSizeScale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (index) {
          final baseHeight = (index + 1) * 3.0 * fontSizeScale;
          final animatedHeight = isPlaying
              ? baseHeight +
                  (DateTime.now().millisecond % 10) * fontSizeScale / 10
              : baseHeight;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 6 * fontSizeScale,
            height: animatedHeight,
            decoration: BoxDecoration(
              color: isMe ? Colors.white : MessengerTheme.lightAccent,
              borderRadius: BorderRadius.circular(3 * fontSizeScale),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildImageMessage(Message msg, bool isMe) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final imageUrl = msg.fileUrl!;

    return GestureDetector(
      onTap: () => _showImageDialog(context, imageUrl),
      child: Container(
        constraints: BoxConstraints(
            maxWidth: 250 * fontSizeScale, maxHeight: 250 * fontSizeScale),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12 * fontSizeScale),
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [MessengerTheme.shadowMD],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12 * fontSizeScale),
          child: Image.network(
            imageUrl,
            width: 250 * fontSizeScale,
            height: 250 * fontSizeScale,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 250 * fontSizeScale,
                height: 250 * fontSizeScale,
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    color: MessengerTheme.lightAccent,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 250 * fontSizeScale,
                height: 250 * fontSizeScale,
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                        size: 50 * fontSizeScale),
                    const SizedBox(height: 8),
                    Text(
                      'Не удалось загрузить изображение',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12 * fontSizeScale,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVideoMessage(Message msg, bool isMe) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final videoUrl = msg.fileUrl!;

    return GestureDetector(
      onTap: () => _openVideo(videoUrl),
      child: Container(
        width: 250 * fontSizeScale,
        height: 180 * fontSizeScale,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12 * fontSizeScale),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [MessengerTheme.shadowMD],
        ),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12 * fontSizeScale),
                color: Colors.black.withOpacity(0.3),
              ),
            ),
            Center(
              child: Container(
                width: 60 * fontSizeScale,
                height: 60 * fontSizeScale,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [MessengerTheme.shadowMD],
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 36 * fontSizeScale,
                  color: MessengerTheme.lightAccent,
                ),
              ),
            ),
            Positioned(
              top: 8 * fontSizeScale,
              right: 8 * fontSizeScale,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 6 * fontSizeScale, vertical: 2 * fontSizeScale),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4 * fontSizeScale),
                ),
                child: Row(
                  children: [
                    Icon(Icons.videocam,
                        color: Colors.white, size: 12 * fontSizeScale),
                    const SizedBox(width: 2),
                    const Text(
                      'VIDEO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileMessage(Message msg, bool isMe) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final fileUrl = msg.fileUrl!;

    return GestureDetector(
      onTap: () {
        _showFileOptions(fileUrl, msg.text);
      },
      child: Container(
        width: 250 * fontSizeScale,
        padding: EdgeInsets.all(12 * fontSizeScale),
        decoration: BoxDecoration(
          color: isMe
              ? MessengerTheme.lightAccent
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12 * fontSizeScale),
          border: Border.all(
            color: isMe ? Colors.white24 : Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40 * fontSizeScale,
              height: 40 * fontSizeScale,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white
                    : MessengerTheme.lightAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8 * fontSizeScale),
              ),
              child: Icon(
                _getFileIcon(msg.fileUrl ?? ''),
                color: isMe
                    ? MessengerTheme.lightAccent
                    : MessengerTheme.lightAccent,
                size: 24 * fontSizeScale,
              ),
            ),
            SizedBox(width: 12 * fontSizeScale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getFileName(msg.fileUrl ?? ''),
                    style: TextStyle(
                      fontSize: 14 * fontSizeScale,
                      color: isMe
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Нажмите для скачивания',
                    style: TextStyle(
                      fontSize: 12 * fontSizeScale,
                      color: isMe
                          ? Colors.white70
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.download,
              color: isMe ? Colors.white70 : MessengerTheme.lightAccent,
              size: 20 * fontSizeScale,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileUrl) {
    final extension = fileUrl.split('.').last.toLowerCase();

    if (['pdf'].contains(extension)) return Icons.picture_as_pdf;
    if (['doc', 'docx'].contains(extension)) return Icons.description;
    if (['xls', 'xlsx'].contains(extension)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(extension)) return Icons.slideshow;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(extension))
      return Icons.archive;
    if (['txt', 'md', 'rtf'].contains(extension)) return Icons.text_snippet;
    if (['py', 'js', 'java', 'cpp', 'c', 'h', 'html', 'css', 'json']
        .contains(extension)) return Icons.code;

    return Icons.insert_drive_file;
  }

  String _getFileName(String fileUrl) {
    try {
      final uri = Uri.parse(fileUrl);
      final path = uri.path;
      return path.split('/').last;
    } catch (e) {
      return 'Файл';
    }
  }

  void _showFileOptions(String fileUrl, String fileName) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.download, color: MessengerTheme.lightAccent),
              title: Text(
                'Скачать файл',
                style: TextStyle(fontSize: 16 * fontSizeScale),
              ),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(fileUrl);
              },
            ),
            ListTile(
              leading: Icon(Icons.share, color: MessengerTheme.lightAccent),
              title: Text(
                'Поделиться',
                style: TextStyle(fontSize: 16 * fontSizeScale),
              ),
              onTap: () {
                Navigator.pop(context);
                _shareFile(fileUrl);
              },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: MessengerTheme.lightAccent),
              title: Text(
                'Скопировать ссылку',
                style: TextStyle(fontSize: 16 * fontSizeScale),
              ),
              onTap: () {
                Navigator.pop(context);
                _copyToClipboard(fileUrl);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _downloadFile(String fileUrl) {
    PlatformUtils.downloadFile(fileUrl).then((isDownloaded) {
      if (!isDownloaded && mounted) {
        _showTooltip('Ссылка скопирована в буфер обмена');
      }
    });
  }

  void _shareFile(String fileUrl) {
    PlatformUtils.openUrl(fileUrl);
    if (!kIsWeb && mounted) {
      _showTooltip('Ссылка скопирована в буфер обмена');
    }
  }

  Widget _buildRecordingControls() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isRecording =
        _voiceService.recordingState == RecordingState.recording;
    final isStopped = _voiceService.recordingState == RecordingState.stopped;
    final recordingSeconds = _voiceService.recordingSeconds;

    if (isRecording || isStopped) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: 16 * fontSizeScale, vertical: 8 * fontSizeScale),
            decoration: BoxDecoration(
              color: MessengerTheme.darkError.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16 * fontSizeScale),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fiber_manual_record,
                    color: MessengerTheme.darkError, size: 16 * fontSizeScale),
                SizedBox(width: 8 * fontSizeScale),
                Text(
                  _formatShortDuration(recordingSeconds),
                  style: TextStyle(
                    fontSize: 14 * fontSizeScale,
                    color: MessengerTheme.darkError,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.emoji_emotions_outlined,
            color: MessengerTheme.lightAccent,
            size: 28 * fontSizeScale,
          ),
          onPressed: _toggleEmojiPicker,
        ),
        IconButton(
          icon: Icon(
            Icons.attach_file,
            color: MessengerTheme.lightAccent,
            size: 28 * fontSizeScale,
          ),
          onPressed: _attachFile,
        ),
      ],
    );
  }

  Widget _buildRightButtons() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isRecording =
        _voiceService.recordingState == RecordingState.recording;
    final isStopped = _voiceService.recordingState == RecordingState.stopped;

    return FutureBuilder<bool>(
      future: _isSendButtonActive,
      builder: (context, snapshot) {
        final isActive = snapshot.data ?? false;

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_isSendingFiles)
              Padding(
                padding: EdgeInsets.only(right: 8 * fontSizeScale),
                child: SizedBox(
                  width: 24 * fontSizeScale,
                  height: 24 * fontSizeScale,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MessengerTheme.lightAccent,
                  ),
                ),
              ),
            if (isRecording || isStopped)
              IconButton(
                icon: Icon(Icons.delete,
                    color: MessengerTheme.darkError, size: 28 * fontSizeScale),
                onPressed: () async {
                  await _deleteRecording();
                  focusNode.requestFocus();
                },
              ),
            SizedBox(width: (isRecording || isStopped) ? 4 * fontSizeScale : 0),
            if (!isRecording && !isStopped)
              IconButton(
                icon: Icon(
                  Icons.mic,
                  color: _audioAvailable &&
                          _audioInitialized &&
                          _microphonePermissionGranted
                      ? MessengerTheme.lightAccent
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                  size: 28 * fontSizeScale,
                ),
                onPressed: _audioAvailable &&
                        _audioInitialized &&
                        _microphonePermissionGranted
                    ? _startRecording
                    : null,
              ),
            SizedBox(width: 4 * fontSizeScale),
            MouseRegion(
              cursor: isActive
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: IconButton(
                icon: Icon(
                  Icons.send,
                  color: isActive && !_isSendingFiles
                      ? MessengerTheme.lightAccent
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4),
                  size: 28 * fontSizeScale,
                ),
                onPressed: isActive && !_isSendingFiles
                    ? () async {
                        await _sendMessage();
                      }
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAttachedFiles() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    if (!_hasAttachments) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(8 * fontSizeScale),
      color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Прикрепленные файлы',
            style: TextStyle(
                fontSize: 12 * fontSizeScale,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8 * fontSizeScale,
            children: _attachedFiles.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;
              final fileName = file.name;
              return Chip(
                label: Text(
                  fileName.length > 15
                      ? '${fileName.substring(0, 15)}...'
                      : fileName,
                  style: TextStyle(fontSize: 12 * fontSizeScale),
                ),
                deleteIcon: Icon(Icons.close, size: 16 * fontSizeScale),
                onDeleted: () => _removeAttachedFile(index),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPicker() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    return Container(
      height: 250 * fontSizeScale,
      color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
      child: Column(
        children: [
          Container(
            height: 40 * fontSizeScale,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: MessengerTheme.lightAccent,
              unselectedLabelColor:
                  Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              indicatorColor: MessengerTheme.lightAccent,
              tabs: EmojiData.categories.keys.map((emoji) {
                return Tab(text: emoji);
              }).toList(),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: EmojiData.categories.values.map((emojis) {
                return GridView.builder(
                  padding: EdgeInsets.all(8 * fontSizeScale),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: emojis.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _addEmoji(emojis[index]),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(8 * fontSizeScale),
                          color: Colors.transparent,
                        ),
                        child: Center(
                          child: Text(
                            emojis[index],
                            style: TextStyle(fontSize: 18 * fontSizeScale),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoModal() {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    if (!_showVideoModal || _chewieController == null)
      return const SizedBox.shrink();

    return Stack(
      children: [
        GestureDetector(
          onTap: _closeVideoModal,
          child: Container(
            color: Colors.black.withOpacity(0.8),
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12 * fontSizeScale),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12 * fontSizeScale),
                    child: Chewie(controller: _chewieController!),
                  ),
                ),
                Positioned(
                  top: 10 * fontSizeScale,
                  right: 10 * fontSizeScale,
                  child: GestureDetector(
                    onTap: _closeVideoModal,
                    child: Container(
                      padding: EdgeInsets.all(6 * fontSizeScale),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final favoritesProvider = Provider.of<FavoritesProvider>(context);
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final appLocalizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFA000),
                Color(0xFFFF5722),
              ],
            ),
          ),
        ),
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16 * fontSizeScale,
                ),
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  hintStyle: TextStyle(
                    color: Colors.white70,
                    fontSize: 16 * fontSizeScale,
                  ),
                  border: InputBorder.none,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchResults.isNotEmpty) ...[
                        IconButton(
                          icon: Icon(Icons.arrow_upward,
                              size: 20 * fontSizeScale),
                          color: Colors.white,
                          onPressed: _currentSearchIndex > 0
                              ? () => _navigateToSearchResult(-1)
                              : null,
                        ),
                        Text(
                          '${_currentSearchIndex + 1}/${_searchResults.length}',
                          style: TextStyle(
                            fontSize: 12 * fontSizeScale,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_downward,
                              size: 20 * fontSizeScale),
                          color: Colors.white,
                          onPressed:
                              _currentSearchIndex < _searchResults.length - 1
                                  ? () => _navigateToSearchResult(1)
                                  : null,
                        ),
                      ],
                    ],
                  ),
                ),
                onChanged: _performSearch,
              )
            : GestureDetector(
                onTap: () {
                  focusNode.unfocus();
                  _showContactMenu();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chatTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16 * fontSizeScale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _isChatBlocked ? 'Заблокирован' : 'В сети',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12 * fontSizeScale,
                      ),
                    ),
                  ],
                ),
              ),
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(
          color: Colors.white,
          size: 24 * fontSizeScale,
        ),
        elevation: 4,
        actions: [
          if (widget.recipientUserId != null && !_isChatBlocked)
            IconButton(
              icon: Icon(
                Icons.phone,
                size: 24 * fontSizeScale,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    content: Container(
                      width: 300,
                      padding: EdgeInsets.all(20 * fontSizeScale),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dialogBackgroundColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.chatTitle,
                            style: TextStyle(
                              fontSize: 18 * fontSizeScale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                  _startCall(callType: CallType.audio);
                                },
                                child: Container(
                                  width: 70 * fontSizeScale,
                                  height: 70 * fontSizeScale,
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.green,
                                      width: 2 * fontSizeScale,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.phone,
                                    color: Colors.green,
                                    size: 32 * fontSizeScale,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                  _startCall(callType: CallType.video);
                                },
                                child: Container(
                                  width: 70 * fontSizeScale,
                                  height: 70 * fontSizeScale,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.blue,
                                      width: 2 * fontSizeScale,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.videocam,
                                    color: Colors.blue,
                                    size: 32 * fontSizeScale,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Отмена',
                              style: TextStyle(
                                fontSize: 16 * fontSizeScale,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          _buildNotificationStatusIndicator(),
          _buildPinnedMessagesAppBarButton(),
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              size: 24 * fontSizeScale,
            ),
            onPressed: () {
              focusNode.unfocus();
              _toggleSearch();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: _isLoading && _messages.isEmpty
                      ? Center(
                          child: CircularProgressIndicator(
                            color: MessengerTheme.lightAccent,
                          ),
                        )
                      : Stack(
                          children: [
                            ListView.builder(
                              key: ValueKey(_messages.length),
                              controller: _scrollController,
                              itemCount:
                                  _messages.length + (_hasMoreMessages ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == 0 && _hasMoreMessages) {
                                  return Center(
                                    child: Padding(
                                      padding:
                                          EdgeInsets.all(8.0 * fontSizeScale),
                                      child: CircularProgressIndicator(
                                        color: MessengerTheme.lightAccent,
                                      ),
                                    ),
                                  );
                                }

                                final msgIndex =
                                    _hasMoreMessages ? index - 1 : index;
                                final msg = _messages[msgIndex];
                                final isMe = msg.userId == widget.myUserId;
                                final timeString =
                                    "${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}";

                                final isSearchResult =
                                    _searchResults.contains(msg);
                                final isCurrentSearchResult = _searchResults
                                        .isNotEmpty &&
                                    _currentSearchIndex >= 0 &&
                                    _searchResults[_currentSearchIndex] == msg;

                                final isHighlighted =
                                    msg.id == _highlightedMessageId;

                                return GestureDetector(
                                  key: Key('message_${msg.id}'),
                                  onTapDown: (details) {
                                    if (!kIsWeb) {
                                      _showMessageContextMenu(
                                          msg, details, context);
                                    }
                                  },
                                  onSecondaryTapDown: (details) {
                                    _showMessageContextMenu(
                                        msg, details, context);
                                  },
                                  onLongPress: () {
                                    if (!kIsWeb) {
                                      final renderBox = context
                                          .findRenderObject() as RenderBox?;
                                      if (renderBox != null) {
                                        final offset = renderBox.localToGlobal(
                                            renderBox.size.center(Offset.zero));
                                        _showMessageContextMenuAtPosition(
                                            msg, offset);
                                      }
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isCurrentSearchResult
                                          ? Colors.yellow.withOpacity(0.3)
                                          : isSearchResult
                                              ? Colors.yellow.withOpacity(0.1)
                                              : Colors.transparent,
                                    ),
                                    child: Align(
                                      alignment: isMe
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        margin: EdgeInsets.symmetric(
                                            horizontal: 10 * fontSizeScale,
                                            vertical: 6 * fontSizeScale),
                                        padding:
                                            EdgeInsets.all(10 * fontSizeScale),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? MessengerTheme.lightAccent
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(isMe
                                                ? MessengerTheme.radiusLG *
                                                    fontSizeScale
                                                : MessengerTheme.radiusSM *
                                                    fontSizeScale),
                                            topRight: Radius.circular(isMe
                                                ? MessengerTheme.radiusSM *
                                                    fontSizeScale
                                                : MessengerTheme.radiusLG *
                                                    fontSizeScale),
                                            bottomLeft: Radius.circular(
                                                MessengerTheme.radiusLG *
                                                    fontSizeScale),
                                            bottomRight: Radius.circular(
                                                MessengerTheme.radiusLG *
                                                    fontSizeScale),
                                          ),
                                          boxShadow: isHighlighted
                                              ? [
                                                  BoxShadow(
                                                    color: MessengerTheme
                                                        .lightAccent
                                                        .withOpacity(0.8),
                                                    blurRadius: 20,
                                                    spreadRadius: 4,
                                                    offset: Offset.zero,
                                                  ),
                                                  BoxShadow(
                                                    color: Colors.white
                                                        .withOpacity(0.3),
                                                    blurRadius: 10,
                                                    spreadRadius: 2,
                                                    offset: Offset.zero,
                                                  )
                                                ]
                                              : null,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: isMe
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            _buildForwardedMessageHeader(msg),
                                            if (favoritesProvider
                                                .isMessageFavorite(msg.id))
                                              Align(
                                                alignment: Alignment.topRight,
                                                child: Icon(
                                                  Icons.star,
                                                  size: 14 * fontSizeScale,
                                                  color: Colors.amber,
                                                ),
                                              ),
                                            if (msg.typeId == 4)
                                              _buildVoiceMessage(msg, isMe)
                                            else if (msg.fileUrl != null &&
                                                msg.fileUrl!.isNotEmpty)
                                              if (msg.typeId == 2)
                                                _buildImageMessage(msg, isMe)
                                              else if (msg.typeId == 3)
                                                _buildVideoMessage(msg, isMe)
                                              else if (msg.typeId == 5)
                                                _buildFileMessage(msg, isMe)
                                              else if (msg.typeId == 6)
                                                _buildImageMessage(msg, isMe)
                                              else
                                                _buildFileMessage(msg, isMe),
                                            if (msg.text.isNotEmpty &&
                                                msg.typeId != 4 &&
                                                msg.text != 'Файл' &&
                                                !msg.text.startsWith('Файл:'))
                                              Padding(
                                                padding: EdgeInsets.only(
                                                    bottom: 4 * fontSizeScale),
                                                child: Text(
                                                  msg.text,
                                                  style: TextStyle(
                                                    fontSize:
                                                        16 * fontSizeScale,
                                                    color: isMe
                                                        ? Colors.white
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                  ),
                                                ),
                                              ),
                                            Text(
                                              timeString,
                                              style: TextStyle(
                                                fontSize: 11 * fontSizeScale,
                                                color: isMe
                                                    ? Colors.white70
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            _buildPinnedMessagesList(),
                          ],
                        ),
                ),
                if (_showEmojiPicker) _buildEmojiPicker(),
                _buildAttachedFiles(),
                if (!_isChatBlocked) ...[
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 8 * fontSizeScale,
                        vertical: 6 * fontSizeScale),
                    color: Theme.of(context).colorScheme.surface,
                    child: Row(
                      children: [
                        _buildRecordingControls(),
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.symmetric(
                                horizontal: 8 * fontSizeScale),
                            child: RawKeyboardListener(
                              focusNode: _rawKeyboardFocusNode,
                              onKey: (RawKeyEvent event) {
                                if (event is RawKeyDownEvent) {
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.shiftLeft ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.shiftRight) {
                                    _shiftPressed = true;
                                  }
                                } else if (event is RawKeyUpEvent) {
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.shiftLeft ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.shiftRight) {
                                    _shiftPressed = false;
                                  }
                                }
                              },
                              child: TextField(
                                controller: _controller,
                                focusNode: focusNode,
                                maxLines: null,
                                minLines: 1,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                enableInteractiveSelection: true,
                                style: TextStyle(fontSize: 16 * fontSizeScale),
                                decoration: InputDecoration(
                                  hintText: _hasAttachments
                                      ? 'Введите сообщение (с файлами)'
                                      : 'Введите сообщение',
                                  hintStyle:
                                      TextStyle(fontSize: 16 * fontSizeScale),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12 * fontSizeScale,
                                    vertical: 12 * fontSizeScale,
                                  ),
                                ),
                                onSubmitted: (text) {
                                  // Нажатие Enter отправляет сообщение, Shift+Enter делает новую строку
                                  if (!_shiftPressed) {
                                    _sendMessage();
                                  }
                                  // Если Shift нажат, то TextField сам добавит новую строку
                                  // и не будет отправлять сообщение
                                },
                              ),
                            ),
                          ),
                        ),
                        _buildRightButtons(),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: EdgeInsets.all(16 * fontSizeScale),
                    color:
                        Theme.of(context).colorScheme.surface.withOpacity(0.1),
                    child: Center(
                      child: Text(
                        'Чат заблокирован. Вы не можете отправлять сообщения',
                        style: TextStyle(
                          fontSize: 14 * fontSizeScale,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_showVideoModal) _buildVideoModal(),
        ],
      ),
      floatingActionButton: _showScrollDownButton
          ? FloatingActionButton.small(
              onPressed: _scrollToBottom,
              backgroundColor: MessengerTheme.lightAccent,
              child: Icon(
                Icons.arrow_downward,
                color: Colors.white,
                size: 20 * fontSizeScale,
              ),
            )
          : null,
    );
  }
}
