import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:safer_chat/services/auth_service.dart';
import 'package:safer_chat/theme.dart';
import 'chat_page.dart';
import 'channel_page.dart';
import 'group_page.dart';
import 'models/chat.dart';
import 'models/search_result.dart';
import 'services/side_menu.dart';
import 'services/profile_modal.dart';
// ✨ ЗАКОММЕНТИРОВАНО: AI страница временно отключена
// import 'ai_chats_page.dart';
import 'services/invite_modal.dart';
import 'archived_chats_page.dart';
import 'providers/font_scale_provider.dart';
import 'favorites_chat_page.dart';
import 'providers/blocked_users_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/profile_provider.dart';
// ✨ ЗАКОММЕНТИРОВАНО: AI провайдеры временно отключены
// import 'providers/ai_chats_provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'widgets/search_overlay.dart';
import 'services/contacts_modal.dart';
import 'utils/platform_utils.dart';
import 'services/connection_quality_service.dart';
import 'services/websocket_service.dart';
import 'providers/optimized_chat_provider.dart';
import 'services/api_service.dart';
import 'services/user_api_service.dart';
import 'dart:async';

class HomePage extends StatefulWidget {
  final String token;
  final VoidCallback onLogout;
  final String? userNickname;
  final int myUserId;
  final bool isFirstLogin;
  final String? userEmail;
  final String? baseUrl;
  final WebSocketService? webSocketService;
  final ApiService? apiService;

  const HomePage({
    Key? key,
    required this.token,
    required this.onLogout,
    this.userNickname,
    required this.myUserId,
    this.isFirstLogin = false,
    this.userEmail,
    this.baseUrl,
    this.webSocketService,
    this.apiService,
  }) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late OptimizedChatProvider _chatProvider;
  late UserApiService _userApiService;
  late ApiService _apiService;
  
  List<Chat> activeChats = [];
  List<Chat> archivedChats = [];
  bool isLoading = true;
  late int currentUserId;
  late String baseUrl;
  final ScrollController scrollController = ScrollController();
  final AuthService authService = AuthService();
  String? userNickname;
  bool isPinnedExpanded = false;
  
  bool _isSearchActive = false;
  OverlayEntry? _searchOverlay;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  // Для папок
  List<Map<String, dynamic>> folders = [];
  bool isLoadingFolders = false;
  
  bool _isOffline = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    baseUrl = PlatformUtils.getBaseUrl(widget.baseUrl);
    
    final connectionQuality = Provider.of<ConnectionQualityService>(context, listen: false);
    
    _apiService = widget.apiService ??
    ApiService(
      baseUrl: baseUrl,
      token: widget.token,
      connectionQuality: connectionQuality,
    );

    _chatProvider = OptimizedChatProvider(
     apiService: _apiService,
     userId: widget.myUserId,
    );

    _userApiService = UserApiService(_apiService);
    
    initializeData();
    
    _setupConnectionQualityListener();
    
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_isOffline && mounted) {
        _updateUnreadCounts();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scrollController.dispose();
    _searchOverlay?.remove();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _refreshTimer?.cancel();
    _chatProvider.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 HomePage resumed');
        _refreshChats();
        break;
      case AppLifecycleState.paused:
        print('📱 HomePage paused');
        break;
      default:
        break;
    }
  }

  void _setupConnectionQualityListener() {
    final connectionQuality = Provider.of<ConnectionQualityService>(context, listen: false);
    connectionQuality.qualityStream.listen((quality) {
      if (mounted) {
        setState(() {
          _isOffline = quality == ConnectionQuality.offline;
        });
        
        if (quality == ConnectionQuality.offline) {
          _showOfflineBanner();
        } else if (quality == ConnectionQuality.poor) {
          _showSlowConnectionBanner();
        } else {
          _hideBanners();
        }
      }
    });
  }

  void _showOfflineBanner() {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text('Нет подключения к интернету'),
        leading: const Icon(Icons.wifi_off, color: Colors.white),
        backgroundColor: Colors.red,
        actions: [
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSlowConnectionBanner() {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text('Медленное соединение. Сообщения могут доставляться с задержкой.'),
        leading: const Icon(Icons.speed, color: Colors.white),
        backgroundColor: Colors.orange,
        actions: [
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _hideBanners() {
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
  }

  Future<void> initializeData() async {
    await loadUserId();
    await loadUserNickname();
    await _refreshChats();
    await loadFolders();
    
    if (widget.isFirstLogin && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        showProfileSettingsModal(
          context,
          initialEmail: widget.userEmail,
          isRequired: true,
        );
      }
    }
  }

  Future<void> _refreshChats() async {
    if (_isOffline) {
      setState(() {
        activeChats = _chatProvider.chats;
        isLoading = false;
      });
      return;
    }
    
    final success = await _chatProvider.loadChats(refresh: true);
    
    if (mounted) {
      setState(() {
        activeChats = _chatProvider.chats;
        isLoading = false;
      });
      
      if (!success && _chatProvider.lastError != null) {
        _showErrorSnackBar(_chatProvider.lastError!);
      }
    }
  }

  Future<void> _updateUnreadCounts() async {
    if (_isOffline) return;
    
    try {
      final response = await _apiService!.get(
        '/chats/unread-counts',
        priority: RequestPriority.low,
        useCache: false,
      );
      
      if (response['success'] == true && mounted) {
        final unreadCounts = response['unread_counts'] as Map<String, dynamic>;
        int totalUnread = 0;
        
        for (var i = 0; i < activeChats.length; i++) {
          final chatId = activeChats[i].id.toString();
          if (unreadCounts.containsKey(chatId)) {
            final newUnread = unreadCounts[chatId] as int;
            if (activeChats[i].unreadCount != newUnread) {
              activeChats[i] = activeChats[i].copyWith(unreadCount: newUnread);
            }
            totalUnread += newUnread;
          }
        }
        
        setState(() {});
      }
    } catch (e) {
      print('❌ Error updating unread counts: $e');
    }
  }

  Future<void> loadUserId() async {
    try {
      final decoded = JwtDecoder.decode(widget.token);
      final userIdFromToken = int.parse(decoded['userId'].toString());
      final savedUserId = await authService.getUserId();
      setState(() {
        currentUserId = savedUserId ?? userIdFromToken;
      });
      if (savedUserId == null) {
        await authService.saveUserDataFromToken(widget.token);
      }
    } catch (e) {
      print('userId error: $e');
      final savedUserId = await authService.getUserId();
      setState(() {
        currentUserId = savedUserId ?? 1;
      });
    }
  }

  Future<void> loadUserNickname() async {
    if (widget.userNickname != null && widget.userNickname!.isNotEmpty) {
      setState(() {
        userNickname = widget.userNickname;
      });
      return;
    }

    try {
      final decoded = JwtDecoder.decode(widget.token);
      final nicknameFromToken = decoded['nickname']?.toString();
      if (nicknameFromToken != null && nicknameFromToken.isNotEmpty) {
        setState(() {
          userNickname = nicknameFromToken;
        });
      }
    } catch (e) {
      print(e);
    }
  }

  // Загрузка папок
  Future<void> loadFolders() async {
    setState(() {
      isLoadingFolders = true;
    });

    try {
      final response = await _apiService!.get('/folders');
      
      if (response['success'] == true && response['folders'] != null) {
        setState(() {
          folders = List<Map<String, dynamic>>.from(response['folders']);
          isLoadingFolders = false;
        });
      }
    } catch (e) {
      print('Error loading folders: $e');
      setState(() {
        isLoadingFolders = false;
      });
    }
  }

  // Добавление чата в папку
  Future<void> addChatToFolder(Chat chat, int folderId) async {
    try {
      final response = await _apiService!.post(
        '/folders/$folderId/chats/${chat.id}',
        priority: RequestPriority.normal,
      );

      if (response['success'] == true) {
        setState(() {
          activeChats.removeWhere((c) => c.id == chat.id);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.chatAddedToFolder ?? 'Чат добавлен в папку'),
            backgroundColor: Colors.green,
          ),
        );
        
        await loadFolders();
        await _refreshChats();
      }
    } on ApiException catch (e) {
      print('Error adding chat to folder: $e');
      _showErrorSnackBar('${AppLocalizations.of(context)!.error ?? 'Ошибка'}: ${e.message}');
    } catch (e) {
      print('Error adding chat to folder: $e');
      _showErrorSnackBar('${AppLocalizations.of(context)!.error ?? 'Ошибка'}: $e');
    }
  }

  void _showSearchOverlay() {
    setState(() {
      _isSearchActive = true;
    });

    _searchFocusNode.requestFocus();

    _searchOverlay = OverlayEntry(
      builder: (context) => SearchOverlay(
        token: widget.token,
        baseUrl: baseUrl,
        myUserId: currentUserId,
        onResultTap: _handleSearchResultTap,
        onClose: _closeSearchOverlay,
        searchController: _searchController,
      ),
    );
    Overlay.of(context).insert(_searchOverlay!);
  }

  void _closeSearchOverlay() {
    _searchOverlay?.remove();
    _searchOverlay = null;
    _searchController.clear(); 
    _searchFocusNode.unfocus();
    setState(() {
      _isSearchActive = false;
    });
  }

  void _handleSearchResultTap(SearchResult result) {
    switch (result.type) {
      case SearchResultType.chat:
        final chat = activeChats.firstWhere(
          (c) => c.id == result.id,
          orElse: () => Chat.regular(
            id: result.id,
            title: result.title,
            lastMessage: result.subtitle ?? '',
            lastMessageTime: DateTime.now(),
            unreadCount: 0,
            participants: [currentUserId],
            isMuted: false,
            isPinned: false,
            myUserId: currentUserId,
          ),
        );
        openChat(chat);
        break;

      case SearchResultType.contact:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              myUserId: currentUserId,
              baseUrl: baseUrl,
              token: widget.token,
              chatId: 0,
              chatTitle: result.title,
              recipientUserId: result.id,
              webSocketService: widget.webSocketService,
              apiService: widget.apiService,
            ),
          ),
        ).then((_) => _refreshChats());
        break;

      case SearchResultType.channel:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChannelPage(
              myUserId: currentUserId,
              baseUrl: baseUrl,
              token: widget.token,
              channelId: result.id,
              channelTitle: result.title,
              apiService: widget.apiService,
            ),
          ),
        );
        break;
        
      case SearchResultType.group:
        openGroup(result.id, result.title);
        break;
    }
  }

  // открытие группы
  void openGroup(int groupId, String groupTitle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupPage(
          myUserId: currentUserId,
          baseUrl: baseUrl,
          token: widget.token,
          groupId: groupId,
          groupTitle: groupTitle,
          apiService: widget.apiService,
        ),
      ),
    ).then((_) => _refreshChats());
  }

  void toggleBlockUser(Chat chat) {
    final blockedUsersProvider = Provider.of<BlockedUsersProvider>(context, listen: false);
    final otherParticipantIds = chat.participants.where((id) => id != currentUserId && id != -1).toList();

    if (otherParticipantIds.isEmpty) {
      showInfoDialog(AppLocalizations.of(context)!.cannotBlockAIChat);
      return;
    }

    bool isCurrentlyBlocked = false;
    int? blockedUserId;
    for (var userId in otherParticipantIds) {
      if (blockedUsersProvider.blockedUsers.contains(userId)) {
        isCurrentlyBlocked = true;
        blockedUserId = userId;
        break;
      }
    }

    if (isCurrentlyBlocked && blockedUserId != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.unblockUser),
          content: Text(AppLocalizations.of(context)!.areYouSureYouWantToUnblockUser(chat.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () {
                blockedUsersProvider.unblockUser(blockedUserId!);
                Navigator.pop(context);
                _refreshChats();
              },
              child: Text(
                AppLocalizations.of(context)!.unblock,
                style: TextStyle(color: MessengerTheme.darkSuccess),
              ),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.blockUser),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context)!.areYouSureYouWantToBlockUser(chat.title)),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.blockUserWarning,
                style: TextStyle(
                  color: MessengerTheme.darkError,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () {
                for (var userId in otherParticipantIds) {
                  blockedUsersProvider.blockUser(userId, chat.title);
                }
                Navigator.pop(context);
                _refreshChats();
              },
              child: Text(
                AppLocalizations.of(context)!.block,
                style: TextStyle(color: MessengerTheme.darkError),
              ),
            ),
          ],
        ),
      );
    }
  }

  void showSnackBar(String message) {
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

  void _showErrorSnackBar(String message) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: 14 * fontSizeScale),
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.red,
      ),
    );
  }

  void createNewChat() async {
    print('🔵 [createNewChat] Открываем модалку контактов...');
    
    final result = await showContactsModal(
  context,
  widget.token,
  baseUrl,
  currentUserId,
  (userId, contactName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          myUserId: currentUserId,
          baseUrl: baseUrl,
          token: widget.token,
          chatId: 0,
          chatTitle: contactName,
          recipientUserId: userId,
          webSocketService: widget.webSocketService,
          apiService: _apiService,
        ),
      ),
    ).then((_) => _refreshChats());
  },
);
    if (result != null && result['userId'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            myUserId: currentUserId,
            baseUrl: baseUrl,
            token: widget.token,
            chatId: 0,
            chatTitle: result['contactName'] ?? 'Контакт',
            recipientUserId: result['userId'],
            webSocketService: widget.webSocketService,
            apiService: widget.apiService,
          ),
        ),
      ).then((_) => _refreshChats());
    }
  }

  // ✨ ИЗМЕНЕНО: AI чат временно отключен
  void createNewAIChat() {
    print('🤖 AI чаты временно недоступны');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('AI ассистент временно отключен'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
    
    /* ЗАКОММЕНТИРОВАНО
    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    final fontScaleProvider = Provider.of<FontScaleProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final blockedUsersProvider = Provider.of<BlockedUsersProvider>(context, listen: false);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ProfileProvider>.value(value: profileProvider),
            ChangeNotifierProvider<FontScaleProvider>.value(value: fontScaleProvider),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ChangeNotifierProvider<BlockedUsersProvider>.value(value: blockedUsersProvider),
            ChangeNotifierProvider<AIChatsProvider>(
              create: (context) => AIChatsProvider(
                baseUrl: baseUrl,
                token: widget.token,
                userId: widget.myUserId,
              ),
            ),
          ],
          child: AIChatsPage(
            myUserId: widget.myUserId,
            token: widget.token,
            baseUrl: baseUrl,
            apiService: widget.apiService,
          ),
        ),
      ),
    );
    */
  }

  void openChat(Chat chat) {
    if (chat.isAIChat) {
      createNewAIChat();
    } else if (chat.isGroup ?? false) {
      openGroup(chat.id, chat.title);
    } else {
      openRegularChat(chat);
    }
  }

  void openRegularChat(Chat chat) {
    if (chat.isChannel) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChannelPage(
            myUserId: currentUserId,
            baseUrl: baseUrl,
            token: widget.token,
            channelId: chat.id,
            channelTitle: chat.title,
            apiService: widget.apiService,
          ),
        ),
      ).then((_) {
        _refreshChats();
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            myUserId: currentUserId,
            baseUrl: baseUrl,
            token: widget.token,
            chatId: chat.id,
            chatTitle: chat.title,
            recipientUserId: chat.recipientUserId,
            webSocketService: widget.webSocketService,
            apiService: widget.apiService,
          ),
        ),
      ).then((_) {
        _refreshChats();
      });
    }
  }

  void toggleChatMute(Chat chat) {
    final isArchived = chat.isArchived;
    setState(() {
      if (isArchived) {
        archivedChats = archivedChats.map((c) {
          if (c.id == chat.id) return c.toggleMute();
          return c;
        }).toList();
      } else {
        final index = activeChats.indexWhere((c) => c.id == chat.id);
        if (index != -1) {
          activeChats[index] = activeChats[index].toggleMute();
        }
      }
    });
    
    // Отправляем запрос на сервер
    _chatProvider.toggleMuteChat(chat.id, !chat.isMuted);
  }

  void deleteChat(Chat chat) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.deleteChat,
          style: TextStyle(fontSize: 20 * fontSizeScale),
        ),
        content: Text(
          AppLocalizations.of(context)!.actionCannotBeUndoneAllMessagesWillBeDeleted,
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              performChatDeletion(chat);
              Navigator.pop(context);
            },
            child: Text(
              AppLocalizations.of(context)!.delete,
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: MessengerTheme.darkError,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void performChatDeletion(Chat chat) {
    setState(() {
      activeChats.removeWhere((c) => c.id == chat.id);
      archivedChats.removeWhere((c) => c.id == chat.id);
    });
    // Здесь можно отправить запрос на сервер
  }

  void archiveChat(Chat chat) {
    if (chat.isAIChat) {
      showInfoDialog(AppLocalizations.of(context)!.aiChatsCannotBeArchived);
      return;
    }
    
    if (chat.isGroup ?? false) {
      showInfoDialog('Группы нельзя архивировать');
      return;
    }

    final archivedChat = chat.archive();
    setState(() {
      activeChats.removeWhere((c) => c.id == chat.id);
      archivedChats.insert(0, archivedChat);
    });
  }

  void restoreChat(Chat chat) {
    final restoredChat = chat.restore();
    setState(() {
      archivedChats.removeWhere((c) => c.id == chat.id);
      activeChats.add(restoredChat);
    });
  }

  void toggleChatPin(Chat chat) async {
    final success = await _chatProvider.togglePinChat(chat.id, !chat.isPinned);
    if (success && mounted) {
      setState(() {
        final index = activeChats.indexWhere((c) => c.id == chat.id);
        if (index != -1) {
          activeChats[index] = activeChats[index].togglePin();
        }
        // Пересортировка
        activeChats.sort((a, b) {
          if (a.isPinned && !b.isPinned) return -1;
          if (!a.isPinned && b.isPinned) return 1;
          return 0;
        });
      });
    }
  }

  void openArchivePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArchivedChatsPage(
          archivedChats: archivedChats,
          onRestoreChat: restoreChat,
          onDeleteChat: deleteChat,
          onToggleMuteChat: toggleChatMute,
          myUserId: currentUserId,
          token: widget.token,
          baseUrl: baseUrl,
        ),
      ),
    ).then((_) => _refreshChats());
  }

  // Контекстное меню с добавлением в папку
  Widget buildChatMenu(Chat chat) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isArchived = chat.isArchived;
    final isAIChat = chat.isAIChat;
    final isBlocked = chat.isBlocked;
    final isGroup = chat.isGroup ?? false;

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        size: 20 * fontSizeScale,
      ),
      onSelected: (value) {
        if (value.startsWith('add_to_folder_')) {
          final folderId = int.parse(value.replaceFirst('add_to_folder_', ''));
          addChatToFolder(chat, folderId);
        } else {
          switch (value) {
            case 'mute':
              toggleChatMute(chat);
              break;
            case 'delete':
              deleteChat(chat);
              break;
            case 'archive':
              archiveChat(chat);
              break;
            case 'pin':
              toggleChatPin(chat);
              break;
            case 'block':
              toggleBlockUser(chat);
              break;
          }
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];
        
        // Пункт "Добавить в папку" (не для групп)
        if (folders.isNotEmpty && !isGroup) {
          items.add(
            PopupMenuItem(
              value: 'add_to_folder',
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    size: 20 * fontSizeScale,
                  ),
                  SizedBox(width: 12 * fontSizeScale),
                  Text(
                    AppLocalizations.of(context)?.addToFolder ?? 'Добавить в папку',
                    style: TextStyle(fontSize: MessengerTheme.fontSizeBase * fontSizeScale),
                  ),
                ],
              ),
            ),
          );
          
          // Подменю с папками
          if (folders.length > 1) {
            for (final folder in folders) {
              items.add(
                PopupMenuItem(
                  value: 'add_to_folder_${folder['id']}',
                  child: Padding(
                    padding: EdgeInsets.only(left: 32 * fontSizeScale),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          size: 16 * fontSizeScale,
                          color: const Color(0xFFFF9800),
                        ),
                        SizedBox(width: 8 * fontSizeScale),
                        Text(
                          folder['name'] ?? 'Папка',
                          style: TextStyle(fontSize: MessengerTheme.fontSizeBase * fontSizeScale),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
          } else if (folders.length == 1) {
            final folder = folders.first;
            items.add(
              PopupMenuItem(
                value: 'add_to_folder_${folder['id']}',
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 20 * fontSizeScale,
                      color: const Color(0xFFFF9800),
                    ),
                    SizedBox(width: 12 * fontSizeScale),
                    Text(
                      '${AppLocalizations.of(context)?.addToFolder ?? 'Добавить в папку'}: ${folder['name']}',
                      style: TextStyle(fontSize: MessengerTheme.fontSizeBase * fontSizeScale),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        
        // Остальные пункты меню
        items.addAll([
          PopupMenuItem(
            value: 'block',
            child: Row(
              children: [
                Icon(
                  isBlocked ? Icons.lock_open : Icons.block,
                  color: isBlocked ? MessengerTheme.darkSuccess : MessengerTheme.darkError,
                  size: 20 * fontSizeScale,
                ),
                SizedBox(width: 12 * fontSizeScale),
                Text(
                  isBlocked
                      ? AppLocalizations.of(context)!.unblock
                      : AppLocalizations.of(context)!.block,
                  style: TextStyle(
                    fontSize: MessengerTheme.fontSizeBase * fontSizeScale,
                    color: isBlocked ? MessengerTheme.darkSuccess : MessengerTheme.darkError,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'mute',
            child: Row(
              children: [
                Icon(
                  chat.isMuted ? Icons.volume_up : Icons.volume_off,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  size: 20 * fontSizeScale,
                ),
                SizedBox(width: 12 * fontSizeScale),
                Text(
                  chat.isMuted
                      ? AppLocalizations.of(context)!.unmute
                      : AppLocalizations.of(context)!.mute,
                  style: TextStyle(fontSize: MessengerTheme.fontSizeBase * fontSizeScale),
                ),
              ],
            ),
          ),
          if (!isAIChat && !isArchived && !isGroup)
            PopupMenuItem(
              value: 'pin',
              child: Row(
                children: [
                  Icon(
                    chat.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    size: 20 * fontSizeScale,
                  ),
                  SizedBox(width: 12 * fontSizeScale),
                  Text(
                    chat.isPinned
                        ? AppLocalizations.of(context)!.unpin
                        : AppLocalizations.of(context)!.pin,
                    style: TextStyle(fontSize: MessengerTheme.fontSizeBase * fontSizeScale),
                  ),
                ],
              ),
            ),
          if (!isAIChat && !isArchived && !isGroup)
            PopupMenuItem(
              value: 'archive',
              child: Row(
                children: [
                  Icon(
                    Icons.archive,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    size: 20 * fontSizeScale,
                  ),
                  SizedBox(width: 12 * fontSizeScale),
                  Text(
                    AppLocalizations.of(context)!.moveToArchive,
                    style: TextStyle(fontSize: MessengerTheme.fontSizeBase * fontSizeScale),
                  ),
                ],
              ),
            ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete,
                  color: MessengerTheme.darkError,
                  size: 20 * fontSizeScale,
                ),
                SizedBox(width: 12 * fontSizeScale),
                Text(
                  AppLocalizations.of(context)!.delete,
                  style: TextStyle(
                    fontSize: MessengerTheme.fontSizeBase * fontSizeScale,
                    color: MessengerTheme.darkError,
                  ),
                ),
              ],
            ),
          ),
        ]);
        
        return items;
      },
    );
  }

  Widget buildChatItem(Chat chat) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    final isPinned = chat.isPinned && !chat.isArchived;
    final isBlocked = chat.isBlocked;
    final isArchived = chat.isArchived;
    final isGroup = chat.isGroup ?? false;

    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: AnimatedContainer(
            duration: MessengerTheme.transitionFast,
            margin: EdgeInsets.symmetric(
              horizontal: 20 * fontSizeScale,
              vertical: 6 * fontSizeScale,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => openChat(chat),
                borderRadius: BorderRadius.circular(MessengerTheme.radiusLG * fontSizeScale),
                splashColor: MessengerTheme.lightAccent.withOpacity(0.1),
                highlightColor: MessengerTheme.lightAccent.withOpacity(0.05),
                hoverColor: MessengerTheme.lightAccent.withOpacity(0.08),
                child: Container(
                  padding: EdgeInsets.all(16 * fontSizeScale),
                  decoration: BoxDecoration(
                    color: isHovered
                        ? Theme.of(context).colorScheme.surface.withOpacity(0.98)
                        : Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: isHovered
                          ? MessengerTheme.lightAccent.withOpacity(0.8)
                          : Theme.of(context).dividerColor.withOpacity(0.3),
                      width: isHovered ? 2.0 : 0.5,
                    ),
                    borderRadius: BorderRadius.circular(MessengerTheme.radiusLG * fontSizeScale),
                    boxShadow: isHovered
                        ? [
                            BoxShadow(
                              color: MessengerTheme.lightAccent.withOpacity(0.3),
                              blurRadius: 12 * fontSizeScale,
                              spreadRadius: 1 * fontSizeScale,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      buildChatAvatar(chat, isPinned, isGroup),
                      SizedBox(width: 16 * fontSizeScale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    chat.title,
                                    style: isHovered
                                        ? MessengerTheme.homeChatName(context).copyWith(
                                            color: MessengerTheme.lightAccent,
                                            fontWeight: FontWeight.w700,
                                          )
                                        : MessengerTheme.homeChatName(context),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (chat.lastMessageTime != null)
                                  Text(
                                    formatTime(chat.lastMessageTime!),
                                    style: isHovered
                                        ? MessengerTheme.homeChatTime(context).copyWith(
                                            color: MessengerTheme.lightAccent.withOpacity(0.9),
                                            fontWeight: FontWeight.w600,
                                          )
                                        : MessengerTheme.homeChatTime(context),
                                  ),
                              ],
                            ),
                            SizedBox(height: 4 * fontSizeScale),
                            Text(
                              isBlocked
                                  ? AppLocalizations.of(context)!.chatIsBlocked
                                  : (chat.lastMessage ?? AppLocalizations.of(context)!.noMessages),
                              style: isHovered
                                  ? MessengerTheme.homeChatPreview(context).copyWith(
                                      color: MessengerTheme.lightAccent.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    )
                                  : MessengerTheme.homeChatPreview(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(left: 12 * fontSizeScale),
                        child: Row(
                          children: [
                            if (chat.unreadCount > 0 && !isArchived && !isBlocked)
                              Container(
                                width: 24 * fontSizeScale,
                                height: 24 * fontSizeScale,
                                decoration: BoxDecoration(
                                  color: isHovered
                                      ? MessengerTheme.lightAccent.withOpacity(0.9)
                                      : MessengerTheme.lightAccent,
                                  shape: BoxShape.circle,
                                  boxShadow: isHovered
                                      ? [
                                          BoxShadow(
                                            color: MessengerTheme.lightAccent.withOpacity(0.4),
                                            blurRadius: 4 * fontSizeScale,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    chat.unreadCount > 9 ? '9+' : chat.unreadCount.toString(),
                                    style: TextStyle(
                                      fontSize: 11.0 * fontSizeScale,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            if (chat.isMuted && !isBlocked && !isArchived)
                              Container(
                                margin: EdgeInsets.only(left: 8 * fontSizeScale),
                                child: Icon(
                                  Icons.notifications_off,
                                  size: 16 * fontSizeScale,
                                  color: isHovered
                                      ? MessengerTheme.lightAccent.withOpacity(0.8)
                                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            buildChatMenu(chat),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildChatAvatar(Chat chat, bool isPinned, bool isGroup) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return Stack(
      children: [
        Container(
          width: 56 * fontSizeScale,
          height: 56 * fontSizeScale,
          decoration: BoxDecoration(
            gradient: MessengerTheme.getAvatarGradient(chat.id),
            shape: BoxShape.circle,
          ),
          child: chat.isAIChat
              ? Icon(
                  Icons.smart_toy,
                  color: Colors.white,
                  size: 24 * fontSizeScale,
                )
              : chat.isChannel
                  ? Icon(
                      Icons.campaign,
                      color: Colors.white,
                      size: 24 * fontSizeScale,
                    )
                  : isGroup
                      ? Icon(
                          Icons.group,
                          color: Colors.white,
                          size: 24 * fontSizeScale,
                        )
                      : Center(
                          child: Text(
                            chat.title[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 20 * fontSizeScale,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
        ),
        if (isPinned)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20 * fontSizeScale,
              height: 20 * fontSizeScale,
              decoration: BoxDecoration(
                color: MessengerTheme.lightAccent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2 * fontSizeScale,
                ),
              ),
              child: Icon(
                Icons.push_pin,
                color: Colors.white,
                size: 10 * fontSizeScale,
              ),
            ),
          ),
      ],
    );
  }

  Widget buildSectionHeader(String title, IconData? icon,
      {bool isCollapsible = false, bool isExpanded = false, VoidCallback? onToggle}) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return InkWell(
      onTap: isCollapsible ? onToggle : null,
      child: Container(
        padding: EdgeInsets.only(
          left: 24 * fontSizeScale,
          right: 24 * fontSizeScale,
          bottom: 8 * fontSizeScale,
          top: 8 * fontSizeScale,
        ),
        child: Row(
          children: [
            if (icon != null)
              Icon(icon,
                  size: 16 * fontSizeScale,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            if (icon != null) SizedBox(width: 8 * fontSizeScale),
            Expanded(
              child: Text(title, style: MessengerTheme.homeSectionTitle(context)),
            ),
            if (isCollapsible)
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20 * fontSizeScale,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildEmptyState() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.0 * fontSizeScale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 80 * fontSizeScale,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
            SizedBox(height: 24 * fontSizeScale),
            Text(
              AppLocalizations.of(context)!.noChatsYet,
              style: TextStyle(
                fontSize: MessengerTheme.fontSize2XL * fontSizeScale,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            SizedBox(height: 12 * fontSizeScale),
            Container(
              constraints: BoxConstraints(maxWidth: 300 * fontSizeScale),
              child: Text(
                AppLocalizations.of(context)!.startNewDialogOrCreateAIChat,
                style: TextStyle(
                  fontSize: MessengerTheme.fontSizeLG * fontSizeScale,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildChatList() {
    if (activeChats.isEmpty && !isLoading) {
      return buildEmptyState();
    }

    if (isLoading) {
      return buildLoadingIndicator();
    }

    final pinnedChats = activeChats.where((chat) => chat.isPinned).toList();
    final regularChats = activeChats.where((chat) => !chat.isPinned).toList();

    return RefreshIndicator(
      onRefresh: _refreshChats,
      color: MessengerTheme.lightAccent,
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.only(
          bottom: 100 * Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale,
        ),
        children: [
          if (pinnedChats.isNotEmpty) ...[
            buildSectionHeader(
              AppLocalizations.of(context)!.pinned,
              Icons.push_pin,
              isCollapsible: true,
              isExpanded: isPinnedExpanded,
              onToggle: () {
                setState(() {
                  isPinnedExpanded = !isPinnedExpanded;
                });
              },
            ),
            if (isPinnedExpanded) ...pinnedChats.map((chat) => buildChatItem(chat)),
          ],
          if (regularChats.isNotEmpty) ...[
            if (pinnedChats.isNotEmpty)
              SizedBox(
                  height: 8 * Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale),
            buildSectionHeader(AppLocalizations.of(context)!.allChats, null),
            ...regularChats.map((chat) => buildChatItem(chat)),
            SizedBox(
                height: 20 * Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale),
          ],
        ],
      ),
    );
  }

  String formatTime(DateTime time) {
    final localTime = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(localTime.year, localTime.month, localTime.day);
    
    if (messageDay == today) {
      return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return AppLocalizations.of(context)!.yesterday;
    } else {
      return '${localTime.day.toString().padLeft(2, '0')}.${localTime.month.toString().padLeft(2, '0')}';
    }
  }

  void showInfoDialog(String message) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.information,
          style: TextStyle(fontSize: MessengerTheme.fontSize2XL * fontSizeScale),
        ),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: TextStyle(fontSize: MessengerTheme.fontSizeLG * fontSizeScale),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: MessengerTheme.fontSizeLG * fontSizeScale,
                color: MessengerTheme.lightAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildFloatingActionButtons() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✨ ИЗМЕНЕНО: AI кнопка временно скрыта
        /*
        FloatingActionButton(
          onPressed: createNewAIChat,
          backgroundColor: Colors.deepOrange, 
          foregroundColor: Colors.white,
          heroTag: 'ai-chat',
          shape: const CircleBorder(),
          elevation: 4,
          child: Icon(Icons.psychology_outlined, size: 24 * fontSizeScale),
        ),
        SizedBox(height: 16 * fontSizeScale),
        */
        FloatingActionButton(
          onPressed: createNewChat,
          backgroundColor: MessengerTheme.lightAccent,
          foregroundColor: Colors.white,
          heroTag: 'regular-chat',
          shape: const CircleBorder(),
          elevation: 4,
          child: Icon(Icons.add_comment_rounded, size: 28 * fontSizeScale),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    return Scaffold(
      drawer: SideMenu(
        onMenuItemClicked: handleSideMenuItemClick,
        archivedChatsCount: archivedChats.length,
        myUserId: widget.myUserId,
        token: widget.token,
        baseUrl: baseUrl,
        onChannelTap: (channelId, channelName) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChannelPage(
                myUserId: widget.myUserId,
                baseUrl: baseUrl,
                token: widget.token,
                channelId: channelId,
                channelTitle: channelName,
                apiService: _apiService,
              ),
            ),
          ).then((_) => _refreshChats());
        },
        onGroupTap: (groupId, groupName) {
          openGroup(groupId, groupName);
        },
        availableChats: activeChats,
        //apiService: _apiService,
      ),
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onTap: () {
            if (!_isSearchActive) {
              _showSearchOverlay();
            }
          },
          style: TextStyle(
            fontSize: MessengerTheme.fontSizeBase * fontSizeScale,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.searchChats,
            hintStyle: TextStyle(
              fontSize: MessengerTheme.fontSizeBase * fontSizeScale,
              color: Colors.white.withOpacity(0.7),
            ),
            border: InputBorder.none,
            prefixIcon: Icon(
              Icons.search,
              color: Colors.white.withOpacity(0.7),
              size: 24 * fontSizeScale,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      if (_isSearchActive) {
                        _closeSearchOverlay();
                      }
                    },
                    color: Colors.white.withOpacity(0.7),
                  )
                : null,
          ),
        ),
        backgroundColor: MessengerTheme.lightAccent,
        foregroundColor: Colors.white,
        elevation: 4,
        iconTheme: IconThemeData(color: Colors.white, size: 24 * fontSizeScale),
      ),
      body: isLoading ? buildLoadingIndicator() : buildChatList(),
      floatingActionButton: buildFloatingActionButtons(),
    );
  }

  Widget buildLoadingIndicator() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: MessengerTheme.lightAccent),
          SizedBox(height: 20 * fontSizeScale),
          Text(
            AppLocalizations.of(context)!.loadingYourChats,
            style: TextStyle(
              fontSize: MessengerTheme.fontSizeXL * fontSizeScale,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  void handleSideMenuItemClick(String title) {
    switch (title) {
      case 'logout':
        showLogoutDialog();
        break;
      case 'contacts':
        showInfoDialog(AppLocalizations.of(context)!.contactsSectionWillBeImplementedLater);
        break;
      case 'creategroup':
        // Этот пункт теперь обрабатывается в SideMenu
        break;
      case 'refresh_chats':
        _refreshChats();
        break;
      case 'refreshchats':
        _refreshChats();
        break;
      case 'archive':
        openArchivePage();
        break;
      case 'favorites':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => FavoritesChatPage(myUserId: widget.myUserId)),
        );
        break;
      case 'invite':
        showInviteModal(context);
        break;
      default:
        break;
    }
  }

  void showLogoutDialog() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.logoutFromAccount,
          style: TextStyle(fontSize: MessengerTheme.fontSize2XL * fontSizeScale),
        ),
        content: Text(
          AppLocalizations.of(context)!.areYouSureYouWantToLogout,
          style: TextStyle(fontSize: MessengerTheme.fontSizeLG * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(
                fontSize: MessengerTheme.fontSizeLG * fontSizeScale,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onLogout();
            },
            child: Text(
              AppLocalizations.of(context)!.logout,
              style: TextStyle(
                fontSize: MessengerTheme.fontSizeLG * fontSizeScale,
                color: MessengerTheme.lightAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}