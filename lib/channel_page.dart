import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart';
import 'dart:async';
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
import 'services/media_service.dart';
import 'services/websocket_service.dart';
import 'services/notification_service_v2.dart';
import 'providers/font_scale_provider.dart';
import 'providers/favorites_provider.dart';
import 'forward_message_page.dart';
import 'providers/theme_provider.dart';
import 'services/invite_users_modal.dart';
import 'utils/platform_utils.dart';
import 'services/api_service.dart';

class ChannelPage extends StatefulWidget {
  final int myUserId;
  final String baseUrl;
  final String token;
  final int channelId;
  final String channelTitle;
  final Message? forwardedMessage;
  final WebSocketService? webSocketService;
  final ApiService? apiService;

  const ChannelPage({
    Key? key,
    required this.myUserId,
    required this.baseUrl,
    required this.token,
    required this.channelId,
    required this.channelTitle,
    this.forwardedMessage,
    this.webSocketService,
    this.apiService,
  }) : super(key: key);

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> with SingleTickerProviderStateMixin {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode focusNode = FocusNode();
  final MediaService _mediaService = MediaService();

  late WebSocketService _webSocketService;
  late NotificationService _notificationService;

  // UI state
  bool _showScrollDownButton = false;
  bool _showEmojiPicker = false;
  bool _isLoading = true;
  bool _isSendingMessage = false;
  bool _hasMoreMessages = true;
  int _currentPage = 1;
  late TabController _tabController;

  // Attached files
  List<Map<String, dynamic>> _attachedFiles = [];
  bool _hasAttachments = false;

  // Video player
  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;
  bool _showVideoModal = false;
  String? _currentVideoUrl;

  // Channel search
  bool _showSearch = false;
  List<Message> _searchResults = [];
  int _currentSearchIndex = -1;

  // Channel info
  Map<String, dynamic> _channelInfo = {
    'photoUrl': null,
    'description': '',
    'subscribersCount': 0,
    'avatarColor': null,
    'created_by': null,
    'is_subscribed': false,
  };

  // Shift key tracking
  bool _shiftPressed = false;

  // Context menu
  OverlayEntry? _contextMenuOverlay;
  Message? _selectedMessageForContextMenu;
  Offset _contextMenuPosition = Offset.zero;
  bool _contextMenuOpen = false;

  // Pinned messages
  List<int> _pinnedMessageIds = [];

  // Уведомления
  bool _notificationsEnabled = true;
  int? _muteDuration;
  DateTime? _muteUntil;
  bool _showMuteOptions = false;
  Timer? _notificationCheckTimer;
  Timer? _tooltipTimer;

  // Состояние подписки для быстрого обновления UI
  bool _isSubscribedOptimistic = false;
  bool _isTogglingSubscription = false;
  
  // WebSocket subscription
  StreamSubscription<Map<String, dynamic>>? _webSocketSubscription;

  @override
  void initState() {
    super.initState();
    
    _webSocketService = widget.webSocketService ?? WebSocketService();
    _notificationService = NotificationService();
    
    _scrollController.addListener(_scrollListener);
    _tabController = TabController(
      length: EmojiData.categories.length,
      vsync: this,
    );
    
    // Загружаем сообщения при инициализации
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChannelInfo().then((_) {
        // После загрузки информации о канале загружаем сообщения
        _loadMessages();
        // Устанавливаем оптимистичное состояние подписки
        _isSubscribedOptimistic = _channelInfo['is_subscribed'] ?? false;
      });
      _loadNotificationSettings();
      _initializeWebSocket();
    });

    if (kIsWeb) {
      _setupWebContextMenu();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
    });

    _controller.addListener(_updateSendButtonState);

    if (widget.forwardedMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleForwardedMessage();
      });
    }

    // Запускаем таймер для проверки уведомлений
    _startNotificationCheckTimer();
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
      
      // Подписываемся на сообщения этого канала
      _webSocketSubscription = _webSocketService.onMessage.listen((event) {
         _handleNewWebSocketMessage(event);
      });
      
      print('✅ WebSocket initialized for channel ${widget.channelId}');
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
        createdAt = DateTime.parse(messageData['createdAt'] ?? messageData['created_at']).toLocal();
      } catch (e) {
        createdAt = DateTime.now();
      }

      String text = messageData['text'] ?? '';
      
      final newMessage = Message(
        id: messageData['id'],
        userId: senderId,
        text: text,
        createdAt: createdAt,
        fileUrl: fileUrl,
        typeId: messageData['typeId'] ?? messageData['type_id'] ?? 1,
        duration: messageData['duration'],
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
      if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _markChannelAsRead();
      }
    }
  }

  void _updateSendButtonState() {
    setState(() {});
  }

  Future<void> _loadChannelInfo() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/channels/${widget.channelId}',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _channelInfo = {
            'photoUrl': data['channel']['avatar_url'],
            'description': data['channel']['description'] ?? '',
            'subscribersCount': data['channel']['subscribers_count'] ?? 0,
            'avatarColor': data['channel']['avatar_color'],
            'created_by': data['channel']['created_by'],
            'is_subscribed': data['channel']['is_subscribed'] ?? false,
          };
        });
      }
    } catch (e) {
      print('${AppLocalizations.of(context)?.error ?? "Error"}: $e');
    }
  }

  Future<void> _markChannelAsRead() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
      };
      
      await dio.post(
        '${widget.baseUrl}/api/channels/${widget.channelId}/mark-read',
      );
    } catch (e) {
      print('Error marking channel as read: $e');
    }
  }

  @override
  void dispose() {
    _webSocketSubscription?.cancel();
    _controller.removeListener(_updateSendButtonState);
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    focusNode.dispose();
    _tabController.dispose();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _closeContextMenu();
    _notificationCheckTimer?.cancel();
    _tooltipTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };
      
      final response = await dio.get(
        '${widget.baseUrl}/api/channels/${widget.channelId}/notification-settings',
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

  Future<void> _updateNotificationSettingsOnServer(bool enabled, int? durationMinutes) async {
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
          final muteUntil = DateTime.now().add(Duration(minutes: durationMinutes));
          data['muted_until'] = muteUntil.toIso8601String();
        } else {
          data['muted_until'] = null;
        }
      } else {
        data['mute_duration'] = null;
        data['muted_until'] = null;
      }
      
      final response = await dio.put(
        '${widget.baseUrl}/api/channels/${widget.channelId}/notification-settings',
        data: data,
      );
      
      if (response.statusCode != 200 && response.statusCode != 404) {
        print('Error updating notification settings: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating notification settings: $e');
    }
  }

  void _startNotificationCheckTimer() {
    _notificationCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
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

  String _getMuteDurationForTooltip(int durationMinutes) {
    final localizations = AppLocalizations.of(context)!;
    if (durationMinutes == 0) return localizations.forever.toLowerCase();
    if (durationMinutes == 180) return localizations.threeHours.toLowerCase();
    if (durationMinutes == 720) return localizations.twelveHours.toLowerCase();
    if (durationMinutes == 1440) return localizations.twentyFourHours.toLowerCase();
    if (durationMinutes == 10080) return localizations.sevenDays.toLowerCase();
    
    final days = durationMinutes ~/ 1440;
    if (days > 0) {
      return '$days ${localizations.days(days).toLowerCase()}';
    }
    
    final hours = durationMinutes ~/ 60;
    if (hours > 0) {
      return '$hours ${localizations.hours(hours).toLowerCase()}';
    }
    
    return '$durationMinutes ${localizations.minutes(durationMinutes).toLowerCase()}';
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
        margin: EdgeInsets.fromLTRB(10, kToolbarHeight + MediaQuery.of(context).padding.top + 10, 10, 0),
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

  void _muteNotifications(int durationMinutes, [Function(void Function())? setModalState]) async {
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
    final localizations = AppLocalizations.of(context)!;
    final message = durationMinutes == 0 
        ? localizations.notificationsDisabledForever
        : '${localizations.notificationsDisabledFor} $durationText';
    
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
    
    final localizations = AppLocalizations.of(context)!;
    _showTooltip(localizations.notificationsEnabled);
  }

  void _showMessageContextMenu(Message message, TapDownDetails? details, BuildContext messageContext) {
    PlatformUtils.preventDefaultContextMenu();

    _closeContextMenu();
    _selectedMessageForContextMenu = message;

    try {
      if (kIsWeb) {
        _selectedMessageForContextMenu = message;
        _showMessageContextMenuAtPosition(message, details?.globalPosition ?? Offset.zero);
      } else {
        final RenderBox renderBox = messageContext.findRenderObject() as RenderBox;
        final localPosition = details?.localPosition ?? Offset(renderBox.size.width / 2, renderBox.size.height / 2);
        final globalPosition = renderBox.localToGlobal(localPosition);
        _showMessageContextMenuAtPosition(message, globalPosition);
      }
    } catch (e) {
      _showMessageContextMenuAtPosition(message, details?.globalPosition ?? Offset.zero);
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
                behavior: HitTestBehavior.translucent,
                onTap: _closeContextMenu,
                onSecondaryTap: _closeContextMenu,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: _contextMenuPosition.dy,
              left: _contextMenuPosition.dx,
              child: MouseRegion(
                onEnter: (event) => _contextMenuOpen = true,
                onExit: (event) {
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted && !_contextMenuOpen) {
                      _closeContextMenu();
                    }
                  });
                },
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(MessengerTheme.radiusMD),
                    color: Theme.of(context).colorScheme.surface,
                    child: Container(
                      width: 220,
                      child: _buildContextMenuContent(message),
                    ),
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
    final localizations = AppLocalizations.of(context)!;
    final favoritesProvider = Provider.of<FavoritesProvider>(context, listen: false);
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isFavorite = favoritesProvider.isMessageFavorite(message.id);
    final isMyMessage = message.userId == widget.myUserId;
    final isPinned = _pinnedMessageIds.contains(message.id);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Delete post (author only)
          if (isMyMessage)
            _buildContextMenuItem(
              icon: Icons.delete,
              text: localizations.delete,
              color: MessengerTheme.darkError,
              onTap: () {
                _closeContextMenu();
                _deleteMessage(message);
              },
            ),

          // Forward
          _buildContextMenuItem(
            icon: Icons.forward,
            text: localizations.forward,
            color: MessengerTheme.lightAccent,
            onTap: () {
              _closeContextMenu();
              _forwardMessage(message);
            },
          ),

          // Comment
          _buildContextMenuItem(
            icon: Icons.comment,
            text: localizations.comment ?? 'Comment',
            color: MessengerTheme.lightAccent,
            onTap: () {
              _closeContextMenu();
              _commentOnMessage(message);
            },
          ),

          // Copy link
          _buildContextMenuItem(
            icon: Icons.link,
            text: localizations.copyLink,
            color: MessengerTheme.lightAccent,
            onTap: () {
              _closeContextMenu();
              _copyMessageLink(message);
            },
          ),

          // Edit (author only)
          if (isMyMessage)
            _buildContextMenuItem(
              icon: Icons.edit,
              text: localizations.edit ?? 'Edit',
              color: MessengerTheme.lightAccent,
              onTap: () {
                _closeContextMenu();
                _editMessage(message);
              },
            ),

          // Pin (admin/owner only)
          if (isMyMessage)
            _buildContextMenuItem(
              icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              text: isPinned ? localizations.unpin : localizations.pin,
              color: MessengerTheme.lightAccent,
              onTap: () {
                _closeContextMenu();
                _togglePinMessage(message);
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20 * fontSizeScale, color: color ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14 * fontSizeScale,
                    color: color ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
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

  // Context menu functions
  void _deleteMessage(Message message) {
    final localizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          localizations.deleteMessage,
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: Text(
          localizations.actionCannotBeUndone,
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              localizations.cancel,
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                final dio = Dio();
                dio.options.headers = {
                  'Authorization': 'Bearer ${widget.token}',
                };

                await dio.delete(
                  '${widget.baseUrl}/api/channels/${widget.channelId}/messages/${message.id}',
                );

                setState(() {
                  _messages.remove(message);
                });

                Navigator.pop(context);
                _showSnackBar(localizations.deleted);
              } catch (e) {
                print('${localizations.error}: $e');
                _showSnackBar(localizations.errorSendingMessage);
              }
            },
            child: Text(
              localizations.delete,
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

  void _commentOnMessage(Message message) {
    final localizations = AppLocalizations.of(context)!;
    // TODO: Implement comments functionality
    _showSnackBar(localizations.comingSoon ?? 'Coming soon');
  }

  void _copyMessageLink(Message message) {
    final localizations = AppLocalizations.of(context)!;
    final link = '${widget.baseUrl}/channels/${widget.channelId}/${message.id}';
    PlatformUtils.copyToClipboard(link);
    _showSnackBar(localizations.linkCopied ?? 'Link copied');
  }

  void _editMessage(Message message) {
    final localizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final editController = TextEditingController(text: message.text);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          localizations.edit ?? 'Edit post',
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: TextField(
          controller: editController,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: localizations.enterMessage,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              localizations.cancel,
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                final dio = Dio();
                dio.options.headers = {
                  'Authorization': 'Bearer ${widget.token}',
                  'Content-Type': 'application/json',
                };

                await dio.put(
                  '${widget.baseUrl}/api/channels/${widget.channelId}/messages/${message.id}',
                  data: {'text': editController.text.trim()},
                );

                setState(() {
                  final index = _messages.indexWhere((m) => m.id == message.id);
                  if (index != -1) {
                    _messages[index] = Message(
                      id: message.id,
                      userId: message.userId,
                      text: editController.text.trim(),
                      createdAt: message.createdAt,
                      fileUrl: message.fileUrl,
                      typeId: message.typeId,
                      duration: message.duration,
                    );
                  }
                });

                Navigator.pop(context);
                _showSnackBar(localizations.saved ?? 'Saved');
              } catch (e) {
                print('${localizations.error}: $e');
                _showSnackBar(localizations.errorSendingMessage);
              }
            },
            child: Text(
              localizations.save ?? 'Save',
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: MessengerTheme.lightAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _togglePinMessage(Message message) async {
    final localizations = AppLocalizations.of(context)!;

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final isPinned = _pinnedMessageIds.contains(message.id);

      if (isPinned) {
        await dio.delete(
          '${widget.baseUrl}/api/channels/${widget.channelId}/pinned-messages/${message.id}',
        );
        setState(() {
          _pinnedMessageIds.remove(message.id);
        });
        _showSnackBar(localizations.unpinned ?? 'Unpinned');
      } else {
        await dio.post(
          '${widget.baseUrl}/api/channels/${widget.channelId}/pinned-messages',
          data: {'message_id': message.id},
        );
        setState(() {
          _pinnedMessageIds.add(message.id);
        });
        _showSnackBar(localizations.pinned ?? 'Pinned');
      }
    } catch (e) {
      print('${localizations.error}: $e');
      _showSnackBar(localizations.errorSendingMessage);
    }
  }

  void _showSnackBar(String message) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: 14 * fontSizeScale),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }

  Future<void> _sendForwardedMessage(Message message) async {
    final localizations = AppLocalizations.of(context)!;

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final forwardData = {
        'text': message.text,
        'channel_id': widget.channelId,
        'forwarded_message_id': message.id,
        'type_id': message.typeId,
      };

      final response = await dio.post(
        '${widget.baseUrl}/api/channels/${widget.channelId}/messages',
        data: forwardData,
      );

      if (response.statusCode == 200) {
        await _loadMessages();
        _scrollToBottom();
      }
    } catch (e) {
      print('${localizations.error}: $e');
      _showSnackBar(localizations.errorForwardingMessage);
    }

    focusNode.requestFocus();
  }

  Future<void> _loadMessages({bool loadMore = false, bool showLoading = false}) async {
    final localizations = AppLocalizations.of(context)!;

    if (!loadMore || showLoading) {
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

      final response = await dio.get(
        '${widget.baseUrl}/api/channels/${widget.channelId}/messages',
        queryParameters: {
          'page': _currentPage,
          'limit': 20,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> messagesData = data['messages'] ?? [];

        final List<Message> loadedMessages = messagesData.map((messageJson) {
          String? fileUrl = messageJson['fileUrl'] ?? messageJson['file_url'];
          if (fileUrl != null && !fileUrl.startsWith('http')) {
            fileUrl = '${widget.baseUrl}$fileUrl';
          }

          return Message(
            id: messageJson['id'],
            userId: messageJson['user_id'] ?? messageJson['userId'],
            text: messageJson['text'] ?? '',
            createdAt: DateTime.parse(messageJson['created_at'] ?? messageJson['createdAt']).toLocal(),
            fileUrl: fileUrl,
            typeId: messageJson['type_id'] ?? messageJson['typeId'] ?? 1,
            duration: messageJson['duration'],
          );
        }).toList();

        setState(() {
          if (loadMore) {
            // При загрузке старых сообщений добавляем в начало
            _messages.insertAll(0, loadedMessages);
          } else {
            // При обычной загрузке заменяем все сообщения
            _messages.clear();
            _messages.addAll(loadedMessages);
          }
          _isLoading = false;
          _hasMoreMessages = loadedMessages.length >= 20;
        });

        // Прокручиваем к низу только при первой загрузке
        if (!loadMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scrollToBottom();
            }
          });
        }
      }
    } catch (e) {
      print('${localizations.error}: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshMessages() async {
    // Просто перезагружаем сообщения без показа лоадера
    await _loadMessages(showLoading: false);
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
      _currentSearchIndex = (_currentSearchIndex + direction) % _searchResults.length;
      if (_currentSearchIndex < 0) _currentSearchIndex = _searchResults.length - 1;
    });

    _scrollToMessage(_searchResults[_currentSearchIndex]);
  }

  void _scrollToMessage(Message message) {
    final index = _messages.indexOf(message);
    if (index != -1 && _scrollController.hasClients) {
      _scrollController.animateTo(
        index * 100.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollListener() {
    if (_scrollController.offset >= 300) {
      if (!_showScrollDownButton) {
        setState(() {
          _showScrollDownButton = true;
        });
      }
    } else {
      if (_showScrollDownButton) {
        setState(() {
          _showScrollDownButton = false;
        });
      }
    }

    if (_scrollController.position.pixels <= _scrollController.position.minScrollExtent + 100) {
      if (_hasMoreMessages && !_isLoading) {
        _currentPage++;
        _loadMessages(loadMore: true, showLoading: false);
      }
    }
    
    if (_scrollController.offset >= _scrollController.position.maxScrollExtent - 100) {
      _markChannelAsRead();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final localizations = AppLocalizations.of(context)!;
    final text = _controller.text.trim();

    if (text.isEmpty && !_hasAttachments) return;

    setState(() {
      _isSendingMessage = true;
    });

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
      };

      if (_hasAttachments && _attachedFiles.isNotEmpty) {
        // Send with files
        for (var file in _attachedFiles) {
          final formData = FormData();
          formData.fields.add(MapEntry('channel_id', widget.channelId.toString()));
          formData.fields.add(MapEntry('text', text));

          if (file['bytes'] != null) {
            String fieldName = 'file';
            if (file['type'] == 'image') fieldName = 'image';
            else if (file['type'] == 'video') fieldName = 'video';

            formData.files.add(MapEntry(
              fieldName,
              MultipartFile.fromBytes(
                file['bytes'],
                filename: file['name'] ?? 'file',
              ),
            ));
          }

          await dio.post('${widget.baseUrl}/api/upload', data: formData);
        }

        setState(() {
          _attachedFiles.clear();
          _hasAttachments = false;
        });
      } else {
        // Send text only
        await dio.post(
          '${widget.baseUrl}/api/channels/${widget.channelId}/messages',
          data: {
            'text': text,
            'channel_id': widget.channelId,
            'type_id': 1,
          },
        );
      }

      _controller.clear();
      
      // Обновляем сообщения без показа лоадера
      await _refreshMessages();
      _scrollToBottom();
      
    } catch (e) {
      print('${localizations.error}: $e');
      _showSnackBar(localizations.errorSendingMessage);
    } finally {
      setState(() {
        _isSendingMessage = false;
      });
    }

    focusNode.requestFocus();
  }

  Future<void> _toggleSubscription() async {
    if (_isTogglingSubscription) return;
    
    final localizations = AppLocalizations.of(context)!;
    
    // Оптимистичное обновление UI
    setState(() {
      _isTogglingSubscription = true;
      _isSubscribedOptimistic = !_isSubscribedOptimistic;
    });
    
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      if (_isSubscribedOptimistic) {
        // Подписаться
        await dio.post(
          '${widget.baseUrl}/api/channels/${widget.channelId}/subscribe',
        );
        _showSnackBar(localizations.subscribed ?? 'Subscribed');
      } else {
        // Отписаться
        await dio.delete(
          '${widget.baseUrl}/api/channels/${widget.channelId}/subscribe',
        );
        _showSnackBar(localizations.unsubscribed ?? 'Unsubscribed');
      }

      // Обновляем информацию о канале
      await _loadChannelInfo();
      
    } catch (e) {
      // Откатываем оптимистичное обновление при ошибке
      setState(() {
        _isSubscribedOptimistic = !_isSubscribedOptimistic;
      });
      print('${localizations.error}: $e');
      _showSnackBar(localizations.errorSendingMessage);
    } finally {
      setState(() {
        _isTogglingSubscription = false;
      });
    }
  }

  void _showChannelInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildChannelInfoMenu(),
    );
  }

  Widget _buildChannelInfoMenu() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final avatarColor = _channelInfo['avatarColor'] != null
        ? _parseColor(_channelInfo['avatarColor'])
        : MessengerTheme.getAvatarGradient(widget.channelId).colors.first;
    final isSubscribed = _channelInfo['is_subscribed'] ?? false;
    final isOwner = _channelInfo['created_by'] == widget.myUserId;
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
                    width: 50 * fontSizeScale,
                    height: 50 * fontSizeScale,
                    decoration: BoxDecoration(
                      gradient: MessengerTheme.getAvatarGradient(widget.channelId),
                      shape: BoxShape.circle,
                    ),
                    child: _channelInfo['photoUrl'] != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(25 * fontSizeScale),
                            child: Image.network(_channelInfo['photoUrl'], fit: BoxFit.cover),
                          )
                        : Icon(Icons.group, size: 30 * fontSizeScale, color: Colors.white),
                  ),
                  SizedBox(width: 12 * fontSizeScale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.channelTitle,
                          style: TextStyle(
                            fontSize: 18 * fontSizeScale,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          localizations.channel ?? 'Channel',
                          style: TextStyle(
                            fontSize: 14 * fontSizeScale,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 24 * fontSizeScale, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Кнопка подписки/отписки (только для не-владельцев)
                  if (!isOwner)
                    _buildMenuButton(
                      icon: isSubscribed ? Icons.remove_circle_outline : Icons.add_circle_outline,
                      text: isSubscribed 
                          ? (localizations.unsubscribe ?? 'Unsubscribe')
                          : (localizations.subscribe ?? 'Subscribe'),
                      onTap: () {
                        Navigator.pop(context);
                        _toggleSubscription();
                      },
                      color: isSubscribed ? Colors.grey : MessengerTheme.lightAccent,
                    ),
                  
                  if (!isOwner) const Divider(color: Colors.transparent),

                  // Кнопка уведомлений (только для подписчиков)
                  if (isSubscribed && !isOwner)
                    StatefulBuilder(
                      builder: (context, setModalState) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMenuButton(
                              icon: _notificationsEnabled ? Icons.notifications_active : Icons.notifications_off,
                              text: _notificationsEnabled 
                                  ? localizations.disableNotifications
                                  : localizations.enableNotifications,
                              onTap: () {
                                if (_notificationsEnabled) {
                                  // Показываем опции отключения
                                  setModalState(() {
                                    _showMuteOptions = !_showMuteOptions;
                                  });
                                } else {
                                  // Включаем уведомления
                                  _enableNotifications(setModalState);
                                }
                              },
                              color: _notificationsEnabled ? null : Colors.grey,
                            ),
                            
                            // ОПЦИИ ОТКЛЮЧЕНИЯ УВЕДОМЛЕНИЙ
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              alignment: Alignment.topCenter,
                              child: _showMuteOptions && _notificationsEnabled
                                  ? Container(
                                      padding: EdgeInsets.only(left: 56 * fontSizeScale, right: 16 * fontSizeScale, bottom: 8 * fontSizeScale),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildMuteOptionItem(
                                            title: localizations.forever,
                                            value: 0,
                                            setModalState: setModalState,
                                          ),
                                          _buildMuteOptionItem(
                                            title: localizations.sevenDays,
                                            value: 10080,
                                            setModalState: setModalState,
                                          ),
                                          _buildMuteOptionItem(
                                            title: localizations.twentyFourHours,
                                            value: 1440,
                                            setModalState: setModalState,
                                          ),
                                          _buildMuteOptionItem(
                                            title: localizations.twelveHours,
                                            value: 720,
                                            setModalState: setModalState,
                                          ),
                                          _buildMuteOptionItem(
                                            title: localizations.threeHours,
                                            value: 180,
                                            setModalState: setModalState,
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
                  
                  if (isSubscribed && !isOwner) const Divider(color: Colors.transparent),

                  // Кнопка пригласить
                  if (!isOwner)
                    _buildMenuButton(
                      icon: Icons.person_add,
                      text: localizations.invite ?? 'Пригласить',
                      onTap: () {
                        Navigator.pop(context); // Закрываем текущее меню
                        _showInviteModal();
                      },
                      color: MessengerTheme.lightAccent,
                    ),
                  
                  if (!isOwner) const Divider(color: Colors.transparent),

                  _buildMenuButton(
                    icon: Icons.people,
                    text: localizations.subscribers ?? 'Subscribers',
                    trailing: Text(
                      '${_channelInfo['subscribersCount']}',
                      style: TextStyle(
                        fontSize: 16 * fontSizeScale,
                        fontWeight: FontWeight.bold,
                        color: MessengerTheme.lightAccent,
                      ),
                    ),
                    onTap: _showSubscribers,
                  ),
                  
                  const Divider(color: Colors.transparent),
                  
                  if (isOwner)
                    _buildMenuButton(
                      icon: Icons.settings,
                      text: localizations.settings ?? 'Settings',
                      onTap: _showChannelSettings,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInviteModal() {
    showDialog(
      context: context,
      builder: (context) => InviteUsersModal(
        channelId: widget.channelId,
        channelTitle: widget.channelTitle,
        baseUrl: widget.baseUrl,
        token: widget.token,
        myUserId: widget.myUserId,
        onInviteSent: (int count) {
          final localizations = AppLocalizations.of(context)!;
          if (count == 1) {
            _showTooltip(localizations.invitationSent);
          } else {
            _showTooltip(localizations.invitationsSent);
          }
        },
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      if (colorString.startsWith('#')) {
        return Color(int.parse(colorString.substring(1), radix: 16) + 0xFF000000);
      }
      return MessengerTheme.lightAccent;
    } catch (e) {
      return MessengerTheme.lightAccent;
    }
  }

  Widget _buildMuteOptionItem({
    required String title,
    required int value,
    required Function(void Function()) setModalState,
  }) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
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
    Widget? trailing,
    required VoidCallback onTap,
    Color? color,
  }) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12 * fontSizeScale, horizontal: 16 * fontSizeScale),
          child: Row(
            children: [
              Icon(icon, color: color ?? MessengerTheme.lightAccent, size: 24 * fontSizeScale),
              SizedBox(width: 16 * fontSizeScale),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: color ?? Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  void _showSubscribers() {
    final localizations = AppLocalizations.of(context)!;
    Navigator.pop(context);
    // TODO: Implement subscribers list
    _showSnackBar(localizations.comingSoon ?? 'Coming soon');
  }

  void _showChannelSettings() {
    final localizations = AppLocalizations.of(context)!;
    Navigator.pop(context);
    // TODO: Implement channel settings
    _showSnackBar(localizations.comingSoon ?? 'Coming soon');
  }

  Widget _buildSubscribeButton() {
    final localizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final isSubscribed = _isSubscribedOptimistic;

    return Container(
      padding: EdgeInsets.all(8 * fontSizeScale),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.6,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: MessengerTheme.lightAccent,
              padding: EdgeInsets.symmetric(vertical: 12 * fontSizeScale, horizontal: 24 * fontSizeScale),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: _isTogglingSubscription ? null : _toggleSubscription,
            child: _isTogglingSubscription
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    isSubscribed 
                        ? (localizations.unsubscribe ?? 'Unsubscribe')
                        : (localizations.subscribe ?? 'Subscribe'),
                    style: TextStyle(
                      fontSize: 16 * fontSizeScale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final isOwner = _channelInfo['created_by'] == widget.myUserId;
    final isSubscribed = _isSubscribedOptimistic;

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
                  hintText: AppLocalizations.of(context)!.search,
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
                          icon: Icon(Icons.arrow_upward, size: 20 * fontSizeScale),
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
                          icon: Icon(Icons.arrow_downward, size: 20 * fontSizeScale),
                          color: Colors.white,
                          onPressed: _currentSearchIndex < _searchResults.length - 1
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
                onTap: _showChannelInfo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.channelTitle,
                      style: TextStyle(
                        fontSize: 18 * fontSizeScale,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      localizations.channel ?? 'Channel',
                      style: TextStyle(
                        fontSize: 12 * fontSizeScale,
                        color: Colors.white70,
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
          _buildNotificationStatusIndicator(),
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              size: 24 * fontSizeScale,
            ),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: MessengerTheme.lightAccent),
                            const SizedBox(height: 16),
                            Text(
                              'Загрузка сообщений...',
                              style: TextStyle(
                                fontSize: 14 * fontSizeScale,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              'Нет сообщений',
                              style: TextStyle(
                                fontSize: 16 * fontSizeScale,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.all(16 * fontSizeScale),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              return _buildMessageBubble(message);
                            },
                          ),
              ),
              // Показываем поле ввода только для автора или кнопку подписки для неподписанных пользователей
              if (isOwner)
                _buildInputArea()
              else if (!isSubscribed)
                _buildSubscribeButton()
              else
                const SizedBox.shrink(), // Для подписчиков (не авторов) ничего не показываем
            ],
          ),
          if (_isSendingMessage)
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: MessengerTheme.lightAccent.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Отправка...',
                        style: TextStyle(
                          fontSize: 14 * fontSizeScale,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _showScrollDownButton
          ? FloatingActionButton(
              mini: true,
              onPressed: _scrollToBottom,
              backgroundColor: MessengerTheme.lightAccent,
              child: const Icon(Icons.arrow_downward, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildMessageBubble(Message message) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final isMyMessage = message.userId == widget.myUserId;

    // Конвертируем UTC время в локальное время
    final localTime = message.createdAt.toLocal();

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showMessageContextMenu(message, details, context);
      },
      onLongPressStart: (details) {
        _showMessageContextMenu(message, null, context);
      },
      child: Align(
        alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 4 * fontSizeScale),
          padding: EdgeInsets.all(12 * fontSizeScale),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
          decoration: BoxDecoration(
            color: isMyMessage
                ? MessengerTheme.lightAccent
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16 * fontSizeScale),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.text.isNotEmpty)
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: isMyMessage ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              if (message.fileUrl != null) ...[
                SizedBox(height: 8 * fontSizeScale),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8 * fontSizeScale),
                  child: Image.network(
                    message.fileUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        padding: EdgeInsets.all(8 * fontSizeScale),
                        child: Icon(Icons.broken_image, size: 48 * fontSizeScale),
                      );
                    },
                  ),
                ),
              ],
              SizedBox(height: 4 * fontSizeScale),
              Text(
                _formatTime(localTime), // Используем локальное время
                style: TextStyle(
                  fontSize: 12 * fontSizeScale,
                  color: isMyMessage ? Colors.white70 : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final localizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    return Container(
      padding: EdgeInsets.all(8 * fontSizeScale),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file, size: 24 * fontSizeScale),
            onPressed: _pickFile,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: focusNode,
              maxLines: null,
              decoration: InputDecoration(
                hintText: localizations.writeToChannel ?? 'Write to channel...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16 * fontSizeScale, vertical: 8 * fontSizeScale),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.send,
              size: 24 * fontSizeScale,
              color: _controller.text.trim().isNotEmpty || _hasAttachments
                  ? MessengerTheme.lightAccent
                  : Colors.grey,
            ),
            onPressed: (_controller.text.trim().isNotEmpty || _hasAttachments) && !_isSendingMessage
                ? _sendMessage
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final localizations = AppLocalizations.of(context)!;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);

      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _attachedFiles.add({
            'bytes': bytes,
            'name': file.name,
            'type': 'image',
          });
          _hasAttachments = true;
        });
        _showSnackBar(localizations.fileAttached ?? 'File attached');
      }
    } catch (e) {
      print('${localizations.error}: $e');
      _showSnackBar(localizations.errorSelectingFiles);
    }
  }

  String _formatTime(DateTime time) {
    final localizations = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(time.year, time.month, time.day);

    if (messageDay == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return localizations.yesterday;
    } else {
      return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}';
    }
  }
}