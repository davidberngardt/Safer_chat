import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../models/message.dart';
import '../services/emoji_data.dart';
import '../services/voice_service.dart';
import '../services/media_service.dart';
import '../services/websocket_service.dart';
import '../services/notification_service_v2.dart';
import '../providers/font_scale_provider.dart';
import '../providers/favorites_provider.dart';
import '../forward_message_page.dart';
import '../providers/theme_provider.dart';
import '../services/contacts_modal.dart';
import '../services/media_gallery_modal.dart';
import '../models/group.dart';
import '../models/group_member.dart';
import '../models/group_members_modal.dart';
import '../utils/platform_utils.dart';
import '../services/api_service.dart';

class GroupPage extends StatefulWidget {
  final int myUserId;
  final String baseUrl;
  final String token;
  final int groupId;
  final String groupTitle;
  final Message? forwardedMessage;
  final WebSocketService? webSocketService;
  final ApiService? apiService;

  const GroupPage({
    Key? key,
    required this.myUserId,
    required this.baseUrl,
    required this.token,
    required this.groupId,
    required this.groupTitle,
    this.forwardedMessage,
    this.webSocketService,
    this.apiService,
  }) : super(key: key);

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> with SingleTickerProviderStateMixin {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode focusNode = FocusNode();

  late VoiceService _voiceService;
  final MediaService _mediaService = MediaService();
  late WebSocketService _webSocketService;
  late NotificationService _notificationService;

  bool _showScrollDownButton = false;
  bool _showEmojiPicker = false;
  bool _isLoading = true;
  bool _hasMoreMessages = true;
  int _currentPage = 1;
  late TabController _tabController;

  List<XFile> _attachedFiles = [];
  bool _hasAttachments = false;

  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;
  bool _showVideoModal = false;
  String? _currentVideoUrl;

  bool _isPlaying = false;
  int? _playingMessageId;
  Timer? _progressTimer;

  bool _showSearch = false;
  List<Message> _searchResults = [];
  int _currentSearchIndex = -1;

  // Group info
  Group? _groupInfo;
  List<GroupMember> _members = [];
  bool _isLoadingMembers = false;
  bool _isMember = true;

  bool _audioAvailable = false;
  bool _audioInitialized = false;
  bool _microphonePermissionGranted = false;
  bool _shiftPressed = false;

  OverlayEntry? _contextMenuOverlay;
  Message? _selectedMessageForContextMenu;
  Offset _contextMenuPosition = Offset.zero;
  bool _contextMenuOpen = false;

  bool _notificationsEnabled = true;
  int? _muteDuration;
  DateTime? _muteUntil;
  bool _showMuteOptions = false;
  Timer? _notificationCheckTimer;
  Timer? _tooltipTimer;
  Timer? _delayedFocusTimer;
  int? _highlightedMessageId;
  Timer? _highlightTimer;
  bool _hasMarkedAsRead = false;

  bool _isSendingFiles = false;
  
  // WebSocket subscription
  StreamSubscription<Map<String, dynamic>>? _webSocketSubscription;

  Future<bool> get _canSendMessage async {
    final hasVoiceMessage = await _voiceService.hasVoiceMessage;
    return (_controller.text.trim().isNotEmpty || 
           _attachedFiles.isNotEmpty ||
           hasVoiceMessage) && _isMember;
  }

  Future<bool> get _isSendButtonActive async {
    return await _canSendMessage;
  }

  @override
  void initState() {
    super.initState();
    
    _voiceService = VoiceService();
    _webSocketService = widget.webSocketService ?? WebSocketService();
    _notificationService = NotificationService();
    
    _scrollController.addListener(_scrollListener);
    _tabController = TabController(
      length: EmojiData.categories.length,
      vsync: this,
    );
    
    _initializeServices();
    _loadGroupInfo();
    _loadMessages();
    _loadMembers();
    _loadNotificationSettings();
    _initializeWebSocket();
    
    _startNotificationCheckTimer();
    
    if (kIsWeb) {
      _setupWebContextMenu();
    }
    
    _delayedFocusTimer = Timer(Duration(milliseconds: 300), () {
      if (mounted && _isMember) {
        focusNode.requestFocus();
      }
    });
    
    _controller.addListener(_updateSendButtonState);
    _setupVoiceServiceListeners();
    
    if (widget.forwardedMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleForwardedMessage();
      });
    }
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
      
      // Подписываемся на сообщения этой группы
      _webSocketSubscription = _webSocketService.onMessage.listen((event) {
         _handleNewWebSocketMessage(event);
      });
      
      print('✅ WebSocket initialized for group ${widget.groupId}');
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
        isForwarded: messageData['isForwarded'] ?? messageData['is_forwarded'] ?? false,
        forwardedFrom: messageData['forwardedFrom'] ?? messageData['forwarded_from'],
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
        _markGroupAsRead();
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
    _progressTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
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
      _microphonePermissionGranted = await _voiceService.checkMicrophonePermission();
      _audioAvailable = true;
      _audioInitialized = true;
    } catch (e) {
      _audioInitialized = true;
      _audioAvailable = false;
    }
  }

  Future<void> _loadGroupInfo() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/groups/${widget.groupId}',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _groupInfo = Group.fromMap(data['group']);
          _isMember = _groupInfo?.isMember ?? true;
        });
      }
    } catch (e) {
      print('Error loading group info: $e');
    }
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoadingMembers = true;
    });

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/groups/${widget.groupId}/members',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _members = (data['members'] as List)
              .map((m) => GroupMember.fromMap(m))
              .toList();
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      print('Error loading members: $e');
      setState(() {
        _isLoadingMembers = false;
      });
    }
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };
      
      final response = await dio.get(
        '${widget.baseUrl}/api/groups/${widget.groupId}/notification-settings',
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
      
      await dio.put(
        '${widget.baseUrl}/api/groups/${widget.groupId}/notification-settings',
        data: data,
      );
    } catch (e) {
      print('Error updating notification settings: $e');
    }
  }

  void _startNotificationCheckTimer() {
    _notificationCheckTimer = Timer.periodic(Duration(minutes: 1), (timer) {
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
        content: Text(message, style: const TextStyle(fontSize: 14)),
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
    const menuWidth = 220.0;
    const menuHeight = 300.0;
    
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
    final favoritesProvider = Provider.of<FavoritesProvider>(context, listen: false);
    final isFavorite = favoritesProvider.isMessageFavorite(message.id);
    final isMyMessage = message.userId == widget.myUserId;

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
            color: isFavorite ? Colors.amber : null,
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

  void _addToFavorites(Message message) {
    final favoritesProvider = Provider.of<FavoritesProvider>(context, listen: false);
    
    favoritesProvider.addFavoriteMessage(
      originalMessageId: message.id,
      chatId: widget.groupId,
      chatTitle: widget.groupTitle,
      text: message.text,
      createdAt: message.createdAt,
      fileUrl: message.fileUrl,
      typeId: message.typeId,
      duration: message.duration,
      originalUserId: message.userId,
    );
    
    _showTooltip(AppLocalizations.of(context)!.addedToFavorites ?? 'Added to favorites');
  }

  void _removeFromFavorites(Message message) {
    final favoritesProvider = Provider.of<FavoritesProvider>(context, listen: false);
    
    try {
      final favMessage = favoritesProvider.favoriteMessages.firstWhere(
        (fav) => fav.originalMessageId == message.id,
      );
      
      favoritesProvider.removeFavoriteMessage(favMessage.id);
      _showTooltip(AppLocalizations.of(context)!.removedFromFavorites ?? 'Removed from favorites');
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _sendForwardedMessage(Message message) async {
    if (!_isMember) return;
    
    try {
      final dio = Dio();
      
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final forwardData = {
        'text': message.text,
        'group_id': widget.groupId,
        'forwarded_message_id': message.id,
        'type_id': message.typeId,
      };

      final response = await dio.post(
        '${widget.baseUrl}/api/groups/${widget.groupId}/messages',
        data: forwardData,
      );

      if (response.statusCode == 200) {
        await _refreshMessages();
        _scrollToBottom();
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
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
            onPressed: () async {
              try {
                final dio = Dio();
                dio.options.headers = {
                  'Authorization': 'Bearer ${widget.token}',
                };

                await dio.delete(
                  '${widget.baseUrl}/api/groups/${widget.groupId}/messages/${message.id}',
                );

                setState(() {
                  _messages.remove(message);
                });

                Navigator.pop(context);
                _showTooltip(AppLocalizations.of(context)!.deleted ?? 'Deleted');
              } catch (e) {
                _showErrorDialog(AppLocalizations.of(context)!.errorSendingMessage);
              }
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

  void _scrollListener() {
    if (_scrollController.offset < _scrollController.position.maxScrollExtent - 300) {
      if (!_showScrollDownButton) setState(() => _showScrollDownButton = true);
    } else {
      if (_showScrollDownButton) setState(() => _showScrollDownButton = false);
    }

    if (_scrollController.offset <= _scrollController.position.minScrollExtent + 100) {
      _loadMoreMessages();
    }

    if (_scrollController.offset >= _scrollController.position.maxScrollExtent - 100) {
      _markGroupAsRead();
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
          _markGroupAsRead();
        } catch (e) {
          try {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            _markGroupAsRead();
          } catch (e) {
            // Ignore
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
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/groups/${widget.groupId}/messages',
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

          DateTime createdAt;
          try {
            final utcTime = DateTime.parse(messageJson['createdAt'] ?? messageJson['created_at']);
            createdAt = utcTime.toLocal();
          } catch (e) {
            createdAt = DateTime.now();
          }

          return Message(
            id: messageJson['id'],
            userId: messageJson['userId'] ?? messageJson['user_id'],
            text: messageJson['text'] ?? '',
            createdAt: createdAt,
            fileUrl: fileUrl,
            typeId: messageJson['typeId'] ?? messageJson['type_id'] ?? 1,
            duration: messageJson['duration'],
            isForwarded: messageJson['isForwarded'] ?? messageJson['is_forwarded'] ?? false,
            forwardedFrom: messageJson['forwardedFrom'] ?? messageJson['forwarded_from'],
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
            _hasMoreMessages = pagination['hasMore'] ?? (loadedMessages.length == 20);
          } else {
            _hasMoreMessages = loadedMessages.length == 20;
          }
        });

        if (!loadMore) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (e is DioException && e.response?.statusCode == 404) {
        _showErrorDialog('Группа не найдена');
      } else {
        _showErrorDialog('Ошибка загрузки сообщений: $e');
      }
    }
  }

  Future<void> _refreshMessages() async {
    await _loadMessages(loadMore: false);
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoading || !_hasMoreMessages) return;

    setState(() {
      _currentPage++;
    });

    await _loadMessages(loadMore: true);
  }

  Future<void> _markGroupAsRead() async {
    if (_hasMarkedAsRead) return;
    
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
      };
      
      await dio.post(
        '${widget.baseUrl}/api/groups/${widget.groupId}/mark-read',
      );
      
      _hasMarkedAsRead = true;
    } catch (e) {
      print('Error marking group as read: $e');
    }
  }

  void _showGroupMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildGroupMenu(),
    );
  }

  Widget _buildGroupMenu() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;
    final isOwner = _groupInfo?.createdBy == widget.myUserId;

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
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
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
                // Header
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
                          gradient: MessengerTheme.getAvatarGradient(widget.groupId),
                          shape: BoxShape.circle,
                        ),
                        child: _groupInfo?.avatarUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(25 * fontSizeScale),
                                child: Image.network(_groupInfo!.avatarUrl!, fit: BoxFit.cover),
                              )
                            : Icon(Icons.group, size: 30 * fontSizeScale, color: Colors.white),
                      ),
                      SizedBox(width: 12 * fontSizeScale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.groupTitle,
                              style: TextStyle(
                                fontSize: 18 * fontSizeScale,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4 * fontSizeScale),
                            Text(
                              '${_members.length} ${AppLocalizations.of(context)!.members}',
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

                // Menu items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Media
                      _buildMenuButton(
                        icon: Icons.photo_library,
                        text: AppLocalizations.of(context)!.media,
                        onTap: () {
                          Navigator.pop(context);
                          _showMediaGallery();
                        },
                      ),

                      const Divider(color: Colors.transparent),

                      // Members
                      _buildMenuButton(
                        icon: Icons.people,
                        text: AppLocalizations.of(context)!.members,
                        trailing: Text(
                          '${_members.length}',
                          style: TextStyle(
                            fontSize: 16 * fontSizeScale,
                            fontWeight: FontWeight.bold,
                            color: MessengerTheme.lightAccent,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _showMembersModal();
                        },
                      ),

                      const Divider(color: Colors.transparent),

                      // Notification settings
                      StatefulBuilder(
                        builder: (context, innerSetState) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMenuButton(
                                icon: _notificationsEnabled ? Icons.notifications_active : Icons.notifications_off,
                                text: _notificationsEnabled
                                    ? AppLocalizations.of(context)!.disableNotifications
                                    : AppLocalizations.of(context)!.enableNotifications,
                                onTap: () {
                                  if (_notificationsEnabled) {
                                    setModalState(() {
                                      _showMuteOptions = !_showMuteOptions;
                                    });
                                  } else {
                                    _enableNotifications();
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
                                        padding: EdgeInsets.only(left: 56 * fontSizeScale, right: 16 * fontSizeScale, bottom: 8 * fontSizeScale),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildMuteOptionItem(
                                              title: AppLocalizations.of(context)!.forever,
                                              value: 0,
                                              setModalState: setModalState,
                                            ),
                                            _buildMuteOptionItem(
                                              title: AppLocalizations.of(context)!.sevenDays,
                                              value: 10080,
                                              setModalState: setModalState,
                                            ),
                                            _buildMuteOptionItem(
                                              title: AppLocalizations.of(context)!.twentyFourHours,
                                              value: 1440,
                                              setModalState: setModalState,
                                            ),
                                            _buildMuteOptionItem(
                                              title: AppLocalizations.of(context)!.twelveHours,
                                              value: 720,
                                              setModalState: setModalState,
                                            ),
                                            _buildMuteOptionItem(
                                              title: AppLocalizations.of(context)!.threeHours,
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

                      const Divider(color: Colors.transparent),

                      // Leave group
                      _buildMenuButton(
                        icon: Icons.exit_to_app,
                        text: AppLocalizations.of(context)!.leaveGroup ?? 'Выйти из группы',
                        onTap: () {
                          Navigator.pop(context);
                          _showLeaveGroupConfirmation();
                        },
                        color: MessengerTheme.darkError,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showMediaGallery() {
    showDialog(
      context: context,
      builder: (context) => MediaGalleryModal(
        chatId: widget.groupId,
        baseUrl: widget.baseUrl,
        token: widget.token,
      ),
    );
  }

  void _showMembersModal() {
    showDialog(
      context: context,
      builder: (context) => GroupMembersModal(
        groupId: widget.groupId,
        groupTitle: widget.groupTitle,
        baseUrl: widget.baseUrl,
        token: widget.token,
        myUserId: widget.myUserId,
        members: _members,
        onMembersUpdated: _loadMembers,
      ),
    );
  }

  void _showLeaveGroupConfirmation() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.leaveGroup ?? 'Выйти из группы',
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: Text(
          AppLocalizations.of(context)!.areYouSureLeaveGroup ?? 'Вы уверены, что хотите покинуть группу?',
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
            onPressed: () async {
              Navigator.pop(context);
              await _leaveGroup();
            },
            child: Text(
              AppLocalizations.of(context)!.leave,
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

  Future<void> _leaveGroup() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

      final response = await dio.delete(
        '${widget.baseUrl}/api/groups/${widget.groupId}/members/${widget.myUserId}',
      );

      if (response.statusCode == 200) {
        _showTooltip(AppLocalizations.of(context)!.youLeftGroup ?? 'Вы покинули группу');
        Navigator.of(context).pop();
      } else {
        _showErrorDialog(AppLocalizations.of(context)!.failedToLeaveGroup ?? 'Не удалось покинуть группу');
      }
    } catch (e) {
      _showErrorDialog('${AppLocalizations.of(context)!.error}: $e');
    }
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
    final message = durationMinutes == 0
        ? AppLocalizations.of(context)!.notificationsDisabledForever
        : '${AppLocalizations.of(context)!.notificationsDisabledFor} $durationText';
    
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
    
    _showTooltip(AppLocalizations.of(context)!.notificationsEnabled);
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
    _voiceService.dispose();
    _progressTimer?.cancel();
    _notificationCheckTimer?.cancel();
    _tooltipTimer?.cancel();
    _delayedFocusTimer?.cancel();
    _highlightTimer?.cancel();
    _closeContextMenu();
    
    super.dispose();
  }

  // Audio recording methods
  Future<void> _startRecording() async {
    if (!_isMember) {
      _showErrorDialog(AppLocalizations.of(context)!.cannotSendMessageNotMember ?? 'Вы не можете отправлять сообщения');
      return;
    }
    
    if (!_audioInitialized) {
      _showErrorDialog(AppLocalizations.of(context)!.audioServiceNotInitialized);
      return;
    }
    
    if (!_microphonePermissionGranted) {
      _showErrorDialog(AppLocalizations.of(context)!.microphonePermissionNotGranted);
      return;
    }
    
    try {
      await _voiceService.startRecording();
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.failedToStartRecording);
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _voiceService.stopRecording();
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.errorStoppingRecording);
    }
  }

  Future<void> _deleteRecording() async {
    try {
      await _voiceService.deleteRecording();
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.errorDeletingRecording);
    }
  }

  Future<void> _sendVoiceMessage() async {
    if (!_isMember) return;
    
    final hasVoiceMessage = await _voiceService.hasVoiceMessage;
    if (!hasVoiceMessage) {
      _showErrorDialog(AppLocalizations.of(context)!.recordVoiceMessageFirst);
      return;
    }

    final duration = Duration(seconds: _voiceService.recordingSeconds);

    final tempMsg = Message(
      id: const Uuid().v4().hashCode,
      userId: widget.myUserId,
      text: AppLocalizations.of(context)!.voiceMessage,
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
        chatId: widget.groupId,
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
      _markGroupAsRead();
      
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.errorSendingVoiceMessage);
      
      setState(() {
        _messages.removeWhere((msg) => msg.id == tempMsg.id);
      });
      
      focusNode.requestFocus();
    }
  }

  Future<void> _playVoiceMessage(Message message) async {
    if (!_audioInitialized) {
      _showErrorDialog(AppLocalizations.of(context)!.audioServiceNotInitialized);
      return;
    }
    
    try {
      if (_isPlaying && _playingMessageId == message.id) {
        await _voiceService.pausePlaying();
      } else {
        await _voiceService.playVoiceMessage(message, message.id);
      }
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.failedToPlayVoiceMessage);
      
      _voiceService.onPlayingStateChanged?.call(false);
      _voiceService.onPlayingMessageIdChanged?.call(null);
    }
  }

  // File attachment methods
  Future<void> _attachFile() async {
    try {
      final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            AppLocalizations.of(context)!.chooseFileType,
            style: TextStyle(fontSize: 18 * fontSizeScale),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.image, color: MessengerTheme.lightAccent),
                title: Text(AppLocalizations.of(context)!.images),
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
                leading: Icon(Icons.attach_file, color: MessengerTheme.lightAccent),
                title: Text(AppLocalizations.of(context)!.anyFile),
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
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
          ],
        ),
      );
      
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.errorSelectingFiles);
    }
  }

  void _removeAttachedFile(int index) {
    setState(() {
      _attachedFiles.removeAt(index);
      _hasAttachments = _attachedFiles.isNotEmpty;
    });
  }

  // Send message
  Future<void> _sendMessage() async {
    if (!_isMember) {
      _showErrorDialog(AppLocalizations.of(context)!.cannotSendMessageNotMember ?? 'Вы не можете отправлять сообщения');
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
      await _sendTextOnly(text);
    }
  }

  Future<void> _sendTextOnly(String text) async {
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

      final response = await dio.post(
        '${widget.baseUrl}/api/groups/${widget.groupId}/messages',
        data: {
          'text': text,
          'type_id': 1,
        },
      );

      if (response.statusCode == 200) {
        final responseData = response.data;

        setState(() {
          final index = _messages.indexWhere((msg) => msg.id == tempMsg.id);
          if (index != -1) {
            _messages[index] = Message(
              id: responseData['id'] ?? tempMsg.id,
              userId: widget.myUserId,
              text: text,
              createdAt: DateTime.now(),
              typeId: 1,
            );
          }
        });
        
        _markGroupAsRead();
      } else {
        setState(() {
          _messages.removeWhere((msg) => msg.id == tempMsg.id);
        });
        
        _showErrorDialog('Ошибка ${response.statusCode}: ${response.data['error'] ?? 'Неизвестная ошибка'}');
      }
    } catch (e) {
      setState(() {
        _messages.removeWhere((msg) => msg.id == tempMsg.id);
      });
      
      _showErrorDialog('Ошибка отправки сообщения: $e');
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
        formData.fields.add(MapEntry('group_id', widget.groupId.toString()));

        final dio = Dio();
        dio.options.headers = {
          'Authorization': 'Bearer ${widget.token}',
        };

        final response = await dio.post(
          '${widget.baseUrl}/api/groups/upload',
          data: formData,
        );

        if (response.statusCode == 200 && mounted) {
          final data = response.data;
          
          setState(() {
            _messages.removeWhere((msg) => msg.id == tempId);
            
            DateTime createdAt;
            try {
              createdAt = DateTime.parse(data['created_at'] ?? data['createdAt']);
            } catch (e) {
              createdAt = DateTime.now();
            }
            
            final serverTypeId = data['type_id'] ?? data['typeId'];
            
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
      
      _markGroupAsRead();
      
    } catch (e) {
      _showErrorDialog('${AppLocalizations.of(context)!.errorSendingFiles}: $e');
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

  // Emoji
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

  // Video
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
                    AppLocalizations.of(context)!.errorLoadingVideo,
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

  // Copy to clipboard
  Future<void> _copyToClipboard(String text) async {
    await PlatformUtils.copyToClipboard(text);
    _showTooltip(AppLocalizations.of(context)!.copiedToClipboard);
    focusNode.requestFocus();
  }

  // Image viewer
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

  void _showVideoErrorDialog(String videoUrl) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: MessengerTheme.darkError, size: 24 * fontSizeScale),
            SizedBox(width: 8 * fontSizeScale),
            Text(
              AppLocalizations.of(context)!.error,
              style: TextStyle(fontSize: 18 * fontSizeScale),
            ),
          ],
        ),
        content: Text(
          AppLocalizations.of(context)!.failedToLoadVideoTryBrowser,
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.close,
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _copyToClipboard(videoUrl);
            },
            child: Text(
              AppLocalizations.of(context)!.copyLink,
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

  void _showErrorDialog(String message) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.error,
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
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: MessengerTheme.lightAccent
              )
            ),
          ),
        ],
      ),
    );
  }

  // Formatting helpers
  String _formatShortDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _getFileName(String fileUrl) {
    try {
      final uri = Uri.parse(fileUrl);
      final path = uri.path;
      return path.split('/').last;
    } catch (e) {
      return AppLocalizations.of(context)!.file;
    }
  }

  IconData _getFileIcon(String fileUrl) {
    final extension = fileUrl.split('.').last.toLowerCase();
    
    if (['pdf'].contains(extension)) return Icons.picture_as_pdf;
    if (['doc', 'docx'].contains(extension)) return Icons.description;
    if (['xls', 'xlsx'].contains(extension)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(extension)) return Icons.slideshow;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(extension)) return Icons.archive;
    if (['txt', 'md', 'rtf'].contains(extension)) return Icons.text_snippet;
    
    return Icons.insert_drive_file;
  }

  void _showFileOptions(String fileUrl, String fileName) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.download, color: MessengerTheme.lightAccent),
              title: Text(
                AppLocalizations.of(context)!.downloadFile,
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
                AppLocalizations.of(context)!.share,
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
                AppLocalizations.of(context)!.copyLink,
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
        _showTooltip(AppLocalizations.of(context)!.linkCopied);
      }
    });
  }

  void _shareFile(String fileUrl) {
    PlatformUtils.openUrl(fileUrl);
    if (!kIsWeb && mounted) {
      _showTooltip(AppLocalizations.of(context)!.linkCopied);
    }
  }

  // UI Builders
  Widget _buildForwardedMessageHeader(Message msg) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    if (!msg.isForwarded || msg.forwardedFrom == null || msg.forwardedFrom!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      margin: EdgeInsets.only(bottom: 4 * fontSizeScale),
      padding: EdgeInsets.symmetric(horizontal: 8 * fontSizeScale, vertical: 4 * fontSizeScale),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6 * fontSizeScale),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.reply, size: 12 * fontSizeScale,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          SizedBox(width: 4 * fontSizeScale),
          Text(
            '${AppLocalizations.of(context)!.from}: ${msg.forwardedFrom!}',
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

  Widget _buildVoiceMessage(Message msg, bool isMe) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
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
                  minHeight: 40 * fontSizeScale
                ),
              ),
              SizedBox(width: 8 * fontSizeScale),
              
              _buildAudioVisualization(msg, isMe, isPlaying),
              SizedBox(width: 12 * fontSizeScale),
              
              Text(
                _formatShortDuration(duration),
                style: TextStyle(
                  fontSize: 14 * fontSizeScale,
                  color: isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
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
                  left: (progress.clamp(0.0, 1.0).toDouble() * 200 * fontSizeScale) - 15 * fontSizeScale,
                  top: -20 * fontSizeScale,
                  child: Text(
                    _formatShortDuration(position.inSeconds),
                    style: TextStyle(
                      fontSize: 10 * fontSizeScale,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    return Container(
      height: 30 * fontSizeScale,
      width: 80 * fontSizeScale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (index) {
          final baseHeight = (index + 1) * 3.0 * fontSizeScale;
          final animatedHeight = isPlaying
              ? baseHeight + (DateTime.now().millisecond % 10) * fontSizeScale / 10
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final imageUrl = msg.fileUrl!;

    return GestureDetector(
      onTap: () => _showImageDialog(context, imageUrl),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 250 * fontSizeScale,
          maxHeight: 250 * fontSizeScale
        ),
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
                    Icon(
                      Icons.broken_image,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      size: 50 * fontSizeScale
                    ),
                    SizedBox(height: 8 * fontSizeScale),
                    Text(
                      AppLocalizations.of(context)!.failedToLoadImage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12 * fontSizeScale,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
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
                  horizontal: 6 * fontSizeScale,
                  vertical: 2 * fontSizeScale
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4 * fontSizeScale),
                ),
                child: Row(
                  children: [
                    Icon(Icons.videocam, color: Colors.white, size: 12 * fontSizeScale),
                    SizedBox(width: 2 * fontSizeScale),
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final fileUrl = msg.fileUrl!;

    return GestureDetector(
      onTap: () {
        _showFileOptions(fileUrl, msg.text);
      },
      child: Container(
        width: 250 * fontSizeScale,
        padding: EdgeInsets.all(12 * fontSizeScale),
        decoration: BoxDecoration(
          color: isMe ? MessengerTheme.lightAccent : Theme.of(context).colorScheme.surface,
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
                color: isMe ? Colors.white : MessengerTheme.lightAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8 * fontSizeScale),
              ),
              child: Icon(
                _getFileIcon(msg.fileUrl ?? ''),
                color: isMe ? MessengerTheme.lightAccent : MessengerTheme.lightAccent,
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
                      color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4 * fontSizeScale),
                  Text(
                    AppLocalizations.of(context)!.tapToDownload,
                    style: TextStyle(
                      fontSize: 12 * fontSizeScale,
                      color: isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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

  Widget _buildRecordingControls() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isRecording = _voiceService.recordingState == RecordingState.recording;
    final isStopped = _voiceService.recordingState == RecordingState.stopped;
    final recordingSeconds = _voiceService.recordingSeconds;

    if (isRecording || isStopped) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * fontSizeScale,
              vertical: 8 * fontSizeScale
            ),
            decoration: BoxDecoration(
              color: MessengerTheme.darkError.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16 * fontSizeScale),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fiber_manual_record, color: MessengerTheme.darkError, size: 16 * fontSizeScale),
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
          onPressed: _isMember ? _toggleEmojiPicker : null,
        ),
        IconButton(
          icon: Icon(
            Icons.attach_file,
            color: _isMember ? MessengerTheme.lightAccent : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            size: 28 * fontSizeScale,
          ),
          onPressed: _isMember ? _attachFile : null,
        ),
      ],
    );
  }

  Widget _buildRightButtons() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isRecording = _voiceService.recordingState == RecordingState.recording;
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
                icon: Icon(
                  Icons.delete,
                  color: MessengerTheme.darkError,
                  size: 28 * fontSizeScale
                ),
                onPressed: () async {
                  await _deleteRecording();
                  focusNode.requestFocus();
                },
              ),
            
            SizedBox(width: (isRecording || isStopped) ? 4 * fontSizeScale : 0),
            
            if (!isRecording && !isStopped && _isMember)
              IconButton(
                icon: Icon(
                  Icons.mic,
                  color: _audioAvailable && _audioInitialized && _microphonePermissionGranted
                      ? MessengerTheme.lightAccent
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  size: 28 * fontSizeScale,
                ),
                onPressed: _audioAvailable && _audioInitialized && _microphonePermissionGranted
                    ? _startRecording
                    : null,
              ),
            
            SizedBox(width: 4 * fontSizeScale),
            
            if (_isMember)
              MouseRegion(
                cursor: isActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
                child: IconButton(
                  icon: Icon(
                    Icons.send,
                    color: isActive && !_isSendingFiles ? MessengerTheme.lightAccent
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    size: 28 * fontSizeScale,
                  ),
                  onPressed: isActive && !_isSendingFiles ? () async {
                    await _sendMessage();
                  } : null,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAttachedFiles() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    if (!_hasAttachments) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(8 * fontSizeScale),
      color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.attachedFiles,
            style: TextStyle(
              fontSize: 12 * fontSizeScale,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)
            ),
          ),
          SizedBox(height: 4 * fontSizeScale),
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
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
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
                          borderRadius: BorderRadius.circular(8 * fontSizeScale),
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    if (!_showVideoModal || _chewieController == null) return const SizedBox.shrink();

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
                      child: Icon(
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
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

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
                onTap: () {
                  focusNode.unfocus();
                  _showGroupMenu();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.groupTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16 * fontSizeScale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_members.length} ${AppLocalizations.of(context)!.members}',
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
          _buildNotificationStatusIndicator(),
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
                      : !_isMember
                          ? _buildNotMemberView()
                          : ListView.builder(
                              key: ValueKey(_messages.length),
                              controller: _scrollController,
                              itemCount: _messages.length + (_hasMoreMessages ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == 0 && _hasMoreMessages) {
                                  return Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(8.0 * fontSizeScale),
                                      child: CircularProgressIndicator(
                                        color: MessengerTheme.lightAccent,
                                      ),
                                    ),
                                  );
                                }

                                final msgIndex = _hasMoreMessages ? index - 1 : index;
                                final msg = _messages[msgIndex];
                                final isMe = msg.userId == widget.myUserId;
                                final timeString =
                                    "${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}";

                                final isSearchResult = _searchResults.contains(msg);
                                final isCurrentSearchResult = _searchResults.isNotEmpty &&
                                    _currentSearchIndex >= 0 &&
                                    _searchResults[_currentSearchIndex] == msg;

                                final isHighlighted = msg.id == _highlightedMessageId;

                                return GestureDetector(
                                  key: Key('message_${msg.id}'),
                                  onTapDown: (details) {
                                    if (!kIsWeb) {
                                      _showMessageContextMenu(msg, details, context);
                                    }
                                  },
                                  onSecondaryTapDown: (details) {
                                    _showMessageContextMenu(msg, details, context);
                                  },
                                  onLongPress: () {
                                    if (!kIsWeb) {
                                      final renderBox = context.findRenderObject() as RenderBox?;
                                      if (renderBox != null) {
                                        final offset = renderBox.localToGlobal(renderBox.size.center(Offset.zero));
                                        _showMessageContextMenuAtPosition(msg, offset);
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
                                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Container(
                                        margin: EdgeInsets.symmetric(
                                          horizontal: 10 * fontSizeScale,
                                          vertical: 6 * fontSizeScale
                                        ),
                                        padding: EdgeInsets.all(10 * fontSizeScale),
                                        decoration: BoxDecoration(
                                          color: isMe ? MessengerTheme.lightAccent : Theme.of(context).colorScheme.surface,
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(isMe ? MessengerTheme.radiusLG * fontSizeScale : MessengerTheme.radiusSM * fontSizeScale),
                                            topRight: Radius.circular(isMe ? MessengerTheme.radiusSM * fontSizeScale : MessengerTheme.radiusLG * fontSizeScale),
                                            bottomLeft: Radius.circular(MessengerTheme.radiusLG * fontSizeScale),
                                            bottomRight: Radius.circular(MessengerTheme.radiusLG * fontSizeScale),
                                          ),
                                          boxShadow: isHighlighted
                                              ? [
                                                  BoxShadow(
                                                    color: MessengerTheme.lightAccent.withOpacity(0.8),
                                                    blurRadius: 20,
                                                    spreadRadius: 4,
                                                    offset: Offset.zero,
                                                  ),
                                                  BoxShadow(
                                                    color: Colors.white.withOpacity(0.3),
                                                    blurRadius: 10,
                                                    spreadRadius: 2,
                                                    offset: Offset.zero,
                                                  )
                                                ]
                                              : null,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                          children: [
                                            _buildForwardedMessageHeader(msg),
                                            
                                            if (msg.typeId == 4)
                                              _buildVoiceMessage(msg, isMe)
                                            else if (msg.fileUrl != null && msg.fileUrl!.isNotEmpty)
                                              if (msg.typeId == 2)
                                                _buildImageMessage(msg, isMe)
                                              else if (msg.typeId == 3)
                                                _buildVideoMessage(msg, isMe)
                                              else if (msg.typeId == 5)
                                                _buildFileMessage(msg, isMe)
                                              else
                                                _buildFileMessage(msg, isMe),
                                            
                                            if (msg.text.isNotEmpty && msg.typeId != 4)
                                              Padding(
                                                padding: EdgeInsets.only(bottom: 4 * fontSizeScale),
                                                child: Text(
                                                  msg.text,
                                                  style: TextStyle(
                                                    fontSize: 16 * fontSizeScale,
                                                    color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                            
                                            Text(
                                              timeString,
                                              style: TextStyle(
                                                fontSize: 11 * fontSizeScale,
                                                color: isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
                ),
                if (_showEmojiPicker && _isMember) _buildEmojiPicker(),
                _buildAttachedFiles(),
                
                if (_isMember) ...[
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8 * fontSizeScale,
                      vertical: 6 * fontSizeScale
                    ),
                    color: Theme.of(context).colorScheme.surface,
                    child: Row(
                      children: [
                        _buildRecordingControls(),
                        
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.symmetric(horizontal: 8 * fontSizeScale),
                            child: RawKeyboardListener(
                              focusNode: FocusNode(),
                              onKey: (RawKeyEvent event) {
                                if (event is RawKeyDownEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                                      event.logicalKey == LogicalKeyboardKey.shiftRight) {
                                    _shiftPressed = true;
                                  }
                                  if (event.logicalKey == LogicalKeyboardKey.enter &&
                                      !_shiftPressed) {
                                    _sendMessage();
                                  }
                                } else if (event is RawKeyUpEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                                      event.logicalKey == LogicalKeyboardKey.shiftRight) {
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
                                    ? AppLocalizations.of(context)!.enterMessageWithFiles
                                    : AppLocalizations.of(context)!.enterMessage,
                                  hintStyle: TextStyle(fontSize: 16 * fontSizeScale),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12 * fontSizeScale,
                                    vertical: 12 * fontSizeScale
                                  ),
                                ),
                                onSubmitted: (text) {
                                  if (!_shiftPressed) {
                                    _sendMessage();
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        
                        _buildRightButtons(),
                      ],
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

  Widget _buildNotMemberView() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_off,
            size: 80 * fontSizeScale,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          SizedBox(height: 16 * fontSizeScale),
          Text(
            AppLocalizations.of(context)!.youAreNotMember ?? 'Вы не являетесь участником этой группы',
            style: TextStyle(
              fontSize: 16 * fontSizeScale,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}