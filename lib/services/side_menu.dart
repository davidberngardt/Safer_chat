// side_menu.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import '../providers/font_scale_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/profile_provider.dart';
import 'settings_menu.dart';
import 'profile_modal.dart';
import 'create_folder.dart';
import 'create_group_modal.dart' as group;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'contacts_modal.dart';
import '../chat_page.dart';
import '../group_page.dart';
import '../models/chat.dart';
import '../models/call_history.dart';
import '../models/user_model.dart' show User;  // Явно указываем откуда импортируем User
import '../services/call_service.dart';
import '../services/call_screen.dart';
import '../utils/platform_utils.dart';
import 'package:dio/dio.dart';

// Убираем импорт create_channel.dart, так как он конфликтует

class SideMenu extends StatefulWidget {
  final Function(String) onMenuItemClicked;
  final int archivedChatsCount;
  final int myUserId;
  final String? token;
  final String? baseUrl;
  final Function(int channelId, String channelName)? onChannelTap;
  final Function(int groupId, String groupName)? onGroupTap;
  final List<Chat>? availableChats;

  const SideMenu({
    Key? key,
    required this.onMenuItemClicked,
    this.archivedChatsCount = 0,
    required this.myUserId,
    this.token,
    this.baseUrl,
    this.onChannelTap,
    this.onGroupTap, 
    this.availableChats,
  }) : super(key: key);

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  bool showSettings = false;
  bool isChannelsExpanded = false;
  bool isGroupsExpanded = false; 
  bool isFoldersExpanded = false;
  List<Map<String, dynamic>> userChannels = [];
  List<Map<String, dynamic>> userGroups = [];
  List<Map<String, dynamic>> userFolders = [];
  List<CallHistory> _allCallHistory = [];
  bool isLoadingChannels = false;
  bool isLoadingGroups = false;
  bool isLoadingFolders = false;
  bool isLoadingCalls = false;
  
  // Для пагинации
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  bool _hasMorePages = false;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  
  // Кэш имен пользователей
  final Map<int, String> _userNameCache = {};

  @override
  void initState() {
    super.initState();
    loadUserChannels();
    loadUserGroups();
    loadUserFolders();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // Загрузка каналов пользователя
  Future<void> loadUserChannels() async {
    if (widget.token == null || widget.baseUrl == null) return;

    if (!mounted) return;
    setState(() {
      isLoadingChannels = true;
    });

    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/channels'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['channels'] != null) {
          setState(() {
            userChannels = List<Map<String, dynamic>>.from(data['channels']);
            isLoadingChannels = false;
          });
        } else {
          setState(() {
            isLoadingChannels = false;
          });
        }
      } else {
        print('Error loading channels: ${response.statusCode}');
        if (mounted) {
          setState(() {
            isLoadingChannels = false;
          });
        }
      }
    } catch (e) {
      print('Exception loading channels: $e');
      if (mounted) {
        setState(() {
          isLoadingChannels = false;
        });
      }
    }
  }

  Future<void> loadUserGroups() async {
    if (widget.token == null || widget.baseUrl == null) return;

    if (!mounted) return;
    setState(() {
      isLoadingGroups = true;
    });

    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/groups'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['groups'] != null) {
          setState(() {
            userGroups = List<Map<String, dynamic>>.from(data['groups']);
            isLoadingGroups = false;
          });
        } else {
          setState(() {
            isLoadingGroups = false;
          });
        }
      } else {
        print('Error loading groups: ${response.statusCode}');
        if (mounted) {
          setState(() {
            isLoadingGroups = false;
          });
        }
      }
    } catch (e) {
      print('Exception loading groups: $e');
      if (mounted) {
        setState(() {
          isLoadingGroups = false;
        });
      }
    }
  }

  Future<void> loadUserFolders() async {
    if (widget.token == null || widget.baseUrl == null) return;

    if (!mounted) return;
    setState(() {
      isLoadingFolders = true;
    });

    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/folders'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['folders'] != null) {
          setState(() {
            userFolders = List<Map<String, dynamic>>.from(data['folders']);
            for (var folder in userFolders) {
              folder['_isExpanded'] = false;
            }
            isLoadingFolders = false;
          });
        } else {
          setState(() {
            isLoadingFolders = false;
          });
        }
      } else {
        print('Error loading folders: ${response.statusCode}');
        if (mounted) {
          setState(() {
            isLoadingFolders = false;
          });
        }
      }
    } catch (e) {
      print('Exception loading folders: $e');
      if (mounted) {
        setState(() {
          isLoadingFolders = false;
        });
      }
    }
  }

  Future<void> _showCreateGroupModal() async {
    try {
      // Загружаем доступных пользователей
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/users',
      );

      List<User> availableUsers = [];

      if (response.statusCode == 200) {
        final data = response.data;
        final users = data['users'] as List;
        
        availableUsers = users
            .where((u) => u['id'] != widget.myUserId)
            .map((u) => User(
                  id: u['id'],
                  name: u['name'] ?? 'User',
                  nickname: u['nickname'] ?? '@user_${u['id']}',
                  avatarColor: Color(int.parse(
                      u['avatar_color']?.replaceFirst('#', '0xFF') ?? '0xFF2196F3')),
                ))
            .toList();
      }

      final result = await group.showCreateGroupModal(
        context,
        availableUsers: availableUsers,
      );

      if (result != null && mounted) {
        // Обновляем список групп
        await loadUserGroups();
        
        // Открываем созданную группу
        if (widget.onGroupTap != null) {
          widget.onGroupTap!(result['id'], result['name']);
        }
        
        // Обновляем список чатов на главной
        widget.onMenuItemClicked('refreshchats');
      }
    } catch (e) {
      print('Error showing create group modal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Обработчик скролла для пагинации
  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMorePages && mounted) {
        _loadMoreCalls();
      }
    }
  }

  // Загрузка следующей страницы
  Future<void> _loadMoreCalls() async {
    if (_isLoadingMore || !_hasMorePages) return;
    
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    
    await _loadCallHistoryPage(_currentPage);
    
    if (mounted) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  // Получение имени пользователя
  Future<String> _getUserName(int userId) async {
    // Проверяем кэш
    if (_userNameCache.containsKey(userId)) {
      return _userNameCache[userId]!;
    }
    
    // Если это текущий пользователь
    if (userId == widget.myUserId) {
      final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
      final name = profileProvider.name ?? profileProvider.nickname ?? 'Я';
      _userNameCache[userId] = name;
      return name;
    }
    
    // Загружаем с сервера
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/users/$userId'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final user = data['user'];
          final name = user['name'] ?? user['nickname'] ?? 'Пользователь $userId';
          _userNameCache[userId] = name;
          return name;
        }
      }
    } catch (e) {
      print('❌ Ошибка загрузки имени пользователя $userId: $e');
    }
    
    return 'Пользователь $userId';
  }

  // Загрузка страницы истории звонков
  Future<void> _loadCallHistoryPage(int page) async {
    if (widget.token == null || widget.baseUrl == null) {
      return;
    }

    try {
      final url = Uri.parse('${widget.baseUrl}/api/calls/history?page=$page&limit=20');
      print('📞 Запрос истории звонков (страница $page): $url');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['calls'] != null) {
          final List<dynamic> historyData = data['calls'] ?? [];
          
          // Обновляем информацию о пагинации
          if (data['pagination'] != null) {
            _totalPages = data['pagination']['total_pages'] ?? 1;
            _totalItems = data['pagination']['total_items'] ?? 0;
            _hasMorePages = data['pagination']['has_more'] ?? false;
          }
          
          final newHistory = historyData.map<CallHistory>((item) {
            return CallHistory(
              id: item['id'],
              chatId: item['chat_id'],
              callerId: item['caller_id'],
              recipientId: item['recipient_id'],
              startTime: DateTime.parse(item['created_at']),
              endTime: item['ended_at'] != null ? DateTime.parse(item['ended_at']) : null,
              duration: item['duration'],
              status: item['status'],
              callType: item['call_type'] ?? (item['is_video_call'] == true ? 'video' : 'audio'),
            );
          }).toList();

          if (mounted) {
            setState(() {
              if (page == 1) {
                _allCallHistory = newHistory;
              } else {
                _allCallHistory.addAll(newHistory);
              }
            });
            
            // Загружаем имена для новых звонков
            for (final call in newHistory) {
              final otherUserId = call.callerId == widget.myUserId 
                  ? call.recipientId 
                  : call.callerId;
              await _getUserName(otherUserId);
            }
          }
        }
      }
    } catch (e) {
      print('❌ Ошибка загрузки страницы $page: $e');
    }
  }

  // Загрузка всех звонков (первая страница)
  Future<void> loadAllCallHistory() async {
    if (widget.token == null || widget.baseUrl == null) {
      print('❌ loadAllCallHistory: token или baseUrl = null');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка: не удалось загрузить историю звонков'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      isLoadingCalls = true;
      _currentPage = 1;
      _allCallHistory.clear();
      _userNameCache.clear();
    });

    await _loadCallHistoryPage(1);

    if (mounted) {
      setState(() {
        isLoadingCalls = false;
      });
    }
  }

  // 🎯 ОБНОВЛЕННЫЙ МЕТОД: инициация звонка из истории
  Future<void> _startCallFromHistory(CallHistory call) async {
    final otherUserId = call.callerId == widget.myUserId 
        ? call.recipientId 
        : call.callerId;
    
    final otherUserName = await _getUserName(otherUserId);
    
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    final callType = await showDialog<CallType>(
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
                otherUserName,
                style: TextStyle(
                  fontSize: 18 * fontSizeScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20 * fontSizeScale),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Кнопка аудиозвонка
                  GestureDetector(
                    onTap: () => Navigator.pop(context, CallType.audio),
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
                  // Кнопка видеозвонка
                  GestureDetector(
                    onTap: () => Navigator.pop(context, CallType.video),
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
              SizedBox(height: 16 * fontSizeScale),
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
    
    if (callType != null && mounted) {
      final callService = CallService();
      await callService.startCall(
        token: widget.token!,
        baseUrl: widget.baseUrl!,
        myUserId: widget.myUserId,
        recipientId: otherUserId,
        chatId: call.chatId,
        recipientName: otherUserName,
        context: context,
        callType: callType,
      );
    }
  }

  // Открытие модального окна с историей звонков
  Future<void> _showAllCallHistoryModal() async {
    if (!mounted) return;
    
    print('📱 Открытие модального окна истории звонков');
    
    if (widget.token == null || widget.baseUrl == null) {
      print('❌ Ошибка: token или baseUrl отсутствуют!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: не удалось загрузить историю звонков'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    await loadAllCallHistory();
    
    if (!mounted) return;
    
    final fontScaleProvider = Provider.of<FontScaleProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final fontSizeScale = fontScaleProvider.fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;
    final appLocalizations = AppLocalizations.of(context);
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        // Создаем локальные копии данных для модального окна
        List<CallHistory> modalCallHistory = List.from(_allCallHistory);
        bool modalIsLoading = isLoadingCalls;
        int modalTotalItems = _totalItems;
        bool modalHasMorePages = _hasMorePages;
        
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: Container(
                  margin: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 50,
                    bottom: MediaQuery.of(context).padding.bottom + 50,
                    left: 20,
                    right: 20,
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
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
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 24 * fontSizeScale,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            SizedBox(width: 8 * fontSizeScale),
                            Text(
                              appLocalizations?.callHistory ?? 'История звонков',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20 * fontSizeScale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$modalTotalItems',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14 * fontSizeScale,
                              ),
                            ),
                            SizedBox(width: 8 * fontSizeScale),
                            IconButton(
                              icon: Icon(
                                Icons.refresh,
                                color: Colors.white,
                                size: 24 * fontSizeScale,
                              ),
                              onPressed: () async {
                                print('🔄 Нажата кнопка обновления');
                                
                                setModalState(() {
                                  modalIsLoading = true;
                                });
                                
                                await loadAllCallHistory();
                                
                                if (mounted) {
                                  setModalState(() {
                                    modalCallHistory = List.from(_allCallHistory);
                                    modalIsLoading = false;
                                    modalTotalItems = _totalItems;
                                    modalHasMorePages = _hasMorePages;
                                  });
                                  print('✅ Данные обновлены');
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      
                      Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        child: modalIsLoading
                            ? Container(
                                height: 200,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: const Color(0xFFFF9800),
                                  ),
                                ),
                              )
                            : modalCallHistory.isEmpty
                                ? Container(
                                    height: 200,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.phone_disabled,
                                            size: 60 * fontSizeScale,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 16 * fontSizeScale),
                                          Text(
                                            appLocalizations?.noCallHistory ?? 'Нет истории звонков',
                                            style: TextStyle(
                                              fontSize: 16 * fontSizeScale,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          SizedBox(height: 8 * fontSizeScale),
                                          Text(
                                            'Совершите свой первый звонок',
                                            style: TextStyle(
                                              fontSize: 14 * fontSizeScale,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.all(16 * fontSizeScale),
                                        child: Row(
                                          children: [
                                            Text(
                                              'Всего: $modalTotalItems',
                                              style: TextStyle(
                                                fontSize: 14 * fontSizeScale,
                                                color: isDarkMode ? Colors.white70 : Colors.black54,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const Spacer(),
                                            ElevatedButton.icon(
                                              icon: Icon(Icons.delete_outline, size: 18 * fontSizeScale),
                                              label: Text(
                                                'Очистить все',
                                                style: TextStyle(fontSize: 14 * fontSizeScale),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 16 * fontSizeScale,
                                                  vertical: 8 * fontSizeScale,
                                                ),
                                              ),
                                              onPressed: () {
                                                Navigator.pop(context);
                                                _showClearAllCallsConfirmation();
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      Divider(height: 1, color: isDarkMode ? Colors.white24 : Colors.black12),
                                      Flexible(
                                        child: ListView.builder(
                                          controller: _scrollController,
                                          shrinkWrap: true,
                                          itemCount: modalCallHistory.length + (modalHasMorePages ? 1 : 0),
                                          itemBuilder: (context, index) {
                                            if (index == modalCallHistory.length) {
                                              return Container(
                                                padding: EdgeInsets.all(16 * fontSizeScale),
                                                child: Center(
                                                  child: _isLoadingMore
                                                      ? CircularProgressIndicator(
                                                          color: const Color(0xFFFF9800),
                                                        )
                                                      : null,
                                                ),
                                              );
                                            }
                                            
                                            final call = modalCallHistory[index];
                                            return FutureBuilder<String>(
                                              future: _getUserName(
                                                call.callerId == widget.myUserId 
                                                    ? call.recipientId 
                                                    : call.callerId
                                              ),
                                              builder: (context, snapshot) {
                                                final otherUserName = snapshot.data ?? 'Загрузка...';
                                                return _buildCallHistoryItem(
                                                  call, 
                                                  otherUserName,
                                                  fontSizeScale, 
                                                  isDarkMode, 
                                                  appLocalizations,
                                                  context,
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Создание новой папки
  Future<void> _createNewFolder() async {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    
    final result = await showCreateFolderModal(
      context,
      availableChats: widget.availableChats ?? [],
      onFolderCreated: () {
        loadUserFolders();
      },
    );
    
    if (result == true) {
      loadUserFolders();
    }
  }

  // Открытие чата из папки
  void _openChatFromFolder(int chatId, String chatTitle, int? recipientUserId) {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          myUserId: widget.myUserId,
          baseUrl: widget.baseUrl ?? 'http://localhost:3004',
          token: widget.token ?? '',
          chatId: chatId,
          chatTitle: chatTitle,
          recipientUserId: recipientUserId,
        ),
      ),
    ).then((_) {
      if (widget.onMenuItemClicked != null) {
        widget.onMenuItemClicked('refreshchats');
      }
    });
  }

  // Редактирование папки
  Future<void> _editFolder(Map<String, dynamic> folder) async {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    
    final result = await showCreateFolderModal(
      context,
      folderData: folder,
      availableChats: widget.availableChats ?? [],
      onFolderCreated: () {
        loadUserFolders();
      },
    );
    
    if (result == true) {
      loadUserFolders();
    }
  }

  // Удаление папки
  Future<void> _deleteFolder(int folderId) async {
    final appLocalizations = AppLocalizations.of(context)!;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appLocalizations.deleteFolder ?? 'Удалить папку'),
        content: Text(appLocalizations.areYouSureYouWantToDeleteFolder ?? 'Вы уверены, что хотите удалить эту папку?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appLocalizations.cancel ?? 'Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              appLocalizations.delete ?? 'Удалить',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    
    if (confirm == true && widget.token != null && widget.baseUrl != null) {
      try {
        final response = await http.delete(
          Uri.parse('${widget.baseUrl}/api/folders/$folderId'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
          },
        );
        
        if (response.statusCode == 200) {
          loadUserFolders();
        }
      } catch (e) {
        print('Error deleting folder: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при удалении папки')),
        );
      }
    }
  }

  // Подтверждение очистки всех звонков
  void _showClearAllCallsConfirmation() {
    final appLocalizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          appLocalizations.clearCallHistory ?? 'Очистить историю звонков',
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: Text(
          appLocalizations.areYouSureDeleteCallHistory ?? 'Вы уверены, что хотите удалить всю историю звонков? Это действие нельзя отменить.',
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              appLocalizations.cancel ?? 'Отмена',
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAllCallHistory();
            },
            child: Text(
              appLocalizations.delete ?? 'Удалить',
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Очистка всей истории звонков
  Future<void> _clearAllCallHistory() async {
    if (!mounted) return;
    setState(() {
      _allCallHistory.clear();
      _totalItems = 0;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)?.callHistoryCleared ?? 'История звонков очищена'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // Форматирование даты звонка
  String _formatCallDateTime(DateTime dateTime, AppLocalizations? appLocalizations) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final callDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (callDate == today) {
      return appLocalizations?.today ?? 'Сегодня';
    } else if (callDate == yesterday) {
      return appLocalizations?.yesterday ?? 'Вчера';
    } else {
      return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year}';
    }
  }

  // Форматирование времени звонка
  String _formatCallTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // Форматирование длительности звонка
  String _formatDuration(int seconds, AppLocalizations? appLocalizations) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '$hours ч $minutes м';
    } else if (minutes > 0) {
      return '$minutes м $remainingSeconds с';
    } else {
      return '$seconds с';
    }
  }

  // 🎯 ОБНОВЛЕННЫЙ: виджет элемента истории звонка с кнопкой перезвонить
  Widget _buildCallHistoryItem(
    CallHistory call, 
    String otherUserName,
    double fontSizeScale, 
    bool isDarkMode,
    AppLocalizations? appLocalizations,
    BuildContext dialogContext,
  ) {
    final isIncoming = call.callerId != widget.myUserId;
    final isMissed = call.status == 'missed' || call.status == 'rejected' || call.status == 'failed';
    final isOutgoing = !isIncoming && !isMissed;
    final isVideoCall = call.callType == 'video';

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isMissed) {
      statusColor = Colors.red;
      statusIcon = Icons.phone_missed;
      statusText = appLocalizations?.missed ?? 'Пропущенный';
    } else if (isOutgoing) {
      statusColor = const Color(0xFFFF9800);
      statusIcon = Icons.call_made;
      statusText = appLocalizations?.outgoing ?? 'Исходящий';
    } else {
      statusColor = const Color(0xFF4CAF50);
      statusIcon = Icons.phone_callback;
      statusText = appLocalizations?.incoming ?? 'Входящий';
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? Colors.white12 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40 * fontSizeScale,
          height: 40 * fontSizeScale,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20 * fontSizeScale),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(statusIcon, color: statusColor, size: 20 * fontSizeScale),
              if (isVideoCall)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: EdgeInsets.all(2 * fontSizeScale),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(4 * fontSizeScale),
                    ),
                    child: Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: 10 * fontSizeScale,
                    ),
                  ),
                ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                otherUserName,
                style: TextStyle(
                  fontSize: 16 * fontSizeScale,
                  fontWeight: FontWeight.w500,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 6 * fontSizeScale,
                vertical: 2 * fontSizeScale,
              ),
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
              '${_formatCallDateTime(call.startTime, appLocalizations)}, ${_formatCallTime(call.startTime)}',
              style: TextStyle(
                fontSize: 12 * fontSizeScale,
                color: Colors.grey,
              ),
            ),
            if (call.duration != null && call.duration! > 0)
              Text(
                '${appLocalizations?.duration ?? 'Длительность'}: ${_formatDuration(call.duration!, appLocalizations)}',
                style: TextStyle(
                  fontSize: 12 * fontSizeScale,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🎯 КНОПКА ПЕРЕЗВОНИТЬ
            IconButton(
              icon: Icon(
                isVideoCall ? Icons.videocam : Icons.phone,
                color: isVideoCall ? Colors.blue : Colors.green,
                size: 20 * fontSizeScale,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _startCallFromHistory(call);
              },
            ),
          ],
        ),
        onTap: () {
          Navigator.pop(dialogContext);
          _openChatFromCallHistory(call);
        },
      ),
    );
  }

  // Открытие чата из истории звонков
  void _openChatFromCallHistory(CallHistory call) {
    final chatId = call.chatId;
    final otherUserId = call.callerId == widget.myUserId ? call.recipientId : call.callerId;
    final otherUserName = call.callerId == widget.myUserId 
        ? 'Пользователь $otherUserId'
        : 'Пользователь $otherUserId';
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          myUserId: widget.myUserId,
          baseUrl: widget.baseUrl ?? 'http://localhost:3004',
          token: widget.token ?? '',
          chatId: chatId,
          chatTitle: otherUserName,
          recipientUserId: chatId == 0 ? otherUserId : null,
        ),
      ),
    ).then((_) {
      if (widget.onMenuItemClicked != null) {
        widget.onMenuItemClicked('refreshchats');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fontScaleProvider = Provider.of<FontScaleProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final fontSizeScale = fontScaleProvider.fontSizeScale;
    final appLocalizations = AppLocalizations.of(context);
    final isDarkMode = themeProvider.isDarkMode;

    if (appLocalizations == null) {
      return const Drawer(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    String cleanNickname = '';
    if (profileProvider.nickname != null && profileProvider.nickname!.isNotEmpty) {
      cleanNickname = profileProvider.nickname!.replaceAll('@', '').trim();
    }

    String displayName;
    if (cleanNickname.isNotEmpty) {
      displayName = cleanNickname;
    } else if (profileProvider.name != null && profileProvider.name!.isNotEmpty) {
      displayName = profileProvider.name!;
    } else {
      displayName = appLocalizations.profile ?? 'Профиль';
    }

    return Drawer(
      child: Container(
        color: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!showSettings)
              Container(
                height: 140,
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
                padding: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 20),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: profileProvider.avatarBytes != null
                              ? Colors.transparent
                              : profileProvider.avatarColor,
                          backgroundImage: profileProvider.avatarBytes != null
                              ? MemoryImage(profileProvider.avatarBytes!)
                              : null,
                          child: profileProvider.avatarBytes == null
                              ? const Icon(Icons.person_rounded, size: 36, color: Colors.white)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: showSettings
                  ? SettingsMenu(
                      onBackToMainMenu: () {
                        setState(() {
                          showSettings = false;
                        });
                      },
                    )
                  : _buildMainMenu(fontSizeScale, appLocalizations, isDarkMode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainMenu(double fontSizeScale, AppLocalizations appLocalizations, bool isDarkMode) {
    return Container(
      color: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 12),

          // Channels Section
          _buildChannelsSection(fontSizeScale, appLocalizations, isDarkMode),

          // ✅ Groups Section
          _buildGroupsSection(fontSizeScale, appLocalizations, isDarkMode),

          // Archive
          _buildArchivedMenuItem(fontSizeScale, appLocalizations, isDarkMode),

          // Chat Folders Section
          _buildFoldersSection(fontSizeScale, appLocalizations, isDarkMode),

          // Contacts
          buildMenuItem(
            Icons.contacts_outlined,
            appLocalizations.contacts ?? 'Контакты',
            fontSizeScale,
            isDarkMode,
            () async {
              print('🔵 Нажата кнопка "Контакты"');
    
              final navigator = Navigator.of(context);
    
              Navigator.pop(context);
    
              final result = await showContactsModal(
                context,
                widget.token,
                widget.baseUrl,
                widget.myUserId,
                null,
              );
    
              if (result != null && result is Map<String, dynamic>) {
                final userId = result['userId'] as int;
                final contactName = result['contactName'] as String;
      
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) {
                      return ChatPage(
                         myUserId: widget.myUserId,
                         baseUrl: widget.baseUrl ?? 'http://localhost:3004',
                         token: widget.token ?? '',
                         chatId: 0,
                         chatTitle: contactName,
                         recipientUserId: userId,
                       );
                    },
                  ),
                );
              }
            },
          ),

          // Звонки
          buildMenuItem(
            Icons.phone_rounded,
            appLocalizations.calls ?? 'Звонки',
            fontSizeScale,
            isDarkMode,
            () {
              print('📞 Нажата кнопка "Звонки"');
              
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
              
              Future.microtask(() {
                if (mounted) {
                  _showAllCallHistoryModal();
                }
              });
            },
          ),

          // Favorites
          buildMenuItem(
            Icons.star_rounded,
            appLocalizations.favorites ?? 'Избранное',
            fontSizeScale,
            isDarkMode,
            () {
              Navigator.pop(context);
              widget.onMenuItemClicked('favorites');
            },
          ),

          // Settings
          buildMenuItem(
            Icons.settings_rounded,
            appLocalizations.settings ?? 'Настройки',
            fontSizeScale,
            isDarkMode,
            () {
              setState(() {
                showSettings = true;
              });
            },
          ),

          // Invite
          buildMenuItem(
            Icons.person_add_alt_rounded,
            appLocalizations.invite ?? 'Пригласить',
            fontSizeScale,
            isDarkMode,
            () {
              widget.onMenuItemClicked('invite');
            },
          ),

          // Logout
          buildMenuItem(
            Icons.logout_rounded,
            appLocalizations.logout ?? 'Выход',
            fontSizeScale,
            isDarkMode,
            () {
              widget.onMenuItemClicked('logout');
            },
          ),

          const SizedBox(height: 40),

          // Footer
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Made with ',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.grey[600]!,
                          fontSize: 12 * fontSizeScale,
                        ),
                      ),
                      Text(
                        'Safer Chat ',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black87,
                          fontSize: 12 * fontSizeScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.favorite_rounded,
                        color: const Color(0xFFFF5722),
                        size: 14 * fontSizeScale,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: MediaQuery.of(context).padding.bottom + 20,
                    color: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ ДОБАВЛЕНО: Секция групп
  Widget _buildGroupsSection(double fontSizeScale, AppLocalizations appLocalizations, bool isDarkMode) {
    if (isLoadingGroups) {
      return ListTile(
        leading: SizedBox(
          width: (24 * fontSizeScale).clamp(18, 32),
          height: (24 * fontSizeScale).clamp(18, 32),
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
          ),
        ),
        title: Text(
          appLocalizations.loading ?? 'Загрузка...',
          style: TextStyle(
            fontSize: (18 * fontSizeScale).clamp(14, 22),
            color: isDarkMode ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: (24 * fontSizeScale).clamp(16, 32),
          vertical: (12 * fontSizeScale).clamp(8, 16),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    if (userGroups.isEmpty) {
      return buildMenuItem(
        Icons.group_add,
        appLocalizations.createGroup ?? 'Создать группу',
        fontSizeScale,
        isDarkMode,
        _showCreateGroupModal,
      );
    }

    return Column(
      children: [
        ListTile(
          leading: Icon(
            Icons.group_rounded,
            color: const Color(0xFFFF9800),
            size: (24 * fontSizeScale).clamp(18, 32),
          ),
          title: Text(
            appLocalizations.groups ?? 'Группы',
            style: TextStyle(
              fontSize: (18 * fontSizeScale).clamp(14, 22),
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Icon(
            isGroupsExpanded ? Icons.expand_less : Icons.expand_more,
            color: isDarkMode ? Colors.white70 : Colors.black54,
            size: (24 * fontSizeScale).clamp(18, 32),
          ),
          onTap: () {
            setState(() {
              isGroupsExpanded = !isGroupsExpanded;
            });
          },
          tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          contentPadding: EdgeInsets.symmetric(
            horizontal: (24 * fontSizeScale).clamp(16, 32),
            vertical: (12 * fontSizeScale).clamp(8, 16),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        if (isGroupsExpanded) ...[
          ...userGroups.map((group) => _buildGroupItem(group, fontSizeScale, isDarkMode, appLocalizations)),
          Padding(
            padding: EdgeInsets.only(left: (48 * fontSizeScale).clamp(32, 64)),
            child: ListTile(
              leading: Icon(
                Icons.add_circle_outline,
                color: const Color(0xFF4CAF50),
                size: (20 * fontSizeScale).clamp(16, 28),
              ),
              title: Text(
                appLocalizations.createGroup ?? 'Создать группу',
                style: TextStyle(
                  fontSize: (16 * fontSizeScale).clamp(12, 20),
                  color: const Color(0xFF4CAF50),
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: _showCreateGroupModal,
              tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: (16 * fontSizeScale).clamp(12, 24),
                vertical: (8 * fontSizeScale).clamp(6, 12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ✅ ДОБАВЛЕНО: Элемент группы
  Widget _buildGroupItem(Map<String, dynamic> group, double fontSizeScale, bool isDarkMode, AppLocalizations appLocalizations) {
    final groupId = group['id'] as int;
    final groupName = group['name'] ?? 'Unnamed Group';
    final membersCount = group['members_count'] ?? 0;

    return Padding(
      padding: EdgeInsets.only(left: (48 * fontSizeScale).clamp(32, 64)),
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              radius: (18 * fontSizeScale).clamp(14, 22),
              backgroundColor: group['avatar_color'] != null
                  ? Color(int.parse(group['avatar_color'].replaceFirst('#', '0xFF')))
                  : Colors.blue,
              backgroundImage: group['avatar_url'] != null
                  ? NetworkImage(group['avatar_url'])
                  : null,
              child: group['avatar_url'] == null
                  ? Icon(
                      Icons.group,
                      size: (18 * fontSizeScale).clamp(14, 22),
                      color: Colors.white,
                    )
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: (12 * fontSizeScale).clamp(8, 16),
                height: (12 * fontSizeScale).clamp(8, 16),
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    membersCount.toString(),
                    style: TextStyle(
                      fontSize: (6 * fontSizeScale).clamp(5, 8),
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          groupName,
          style: TextStyle(
            fontSize: (16 * fontSizeScale).clamp(12, 20),
            color: isDarkMode ? Colors.white70 : Colors.black87,
            fontWeight: FontWeight.w400,
          ),
        ),
        subtitle: Text(
          '${appLocalizations.membersCount ?? 'Участников'}: $membersCount',
          style: TextStyle(
            fontSize: (12 * fontSizeScale).clamp(10, 14),
            color: isDarkMode ? Colors.white38 : Colors.black38,
          ),
        ),
        onTap: () {
          if (widget.onGroupTap != null) {
            Navigator.pop(context);
            widget.onGroupTap!(groupId, groupName);
          }
        },
        tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: (16 * fontSizeScale).clamp(12, 24),
          vertical: (8 * fontSizeScale).clamp(6, 12),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildChannelsSection(double fontSizeScale, AppLocalizations appLocalizations, bool isDarkMode) {
    if (isLoadingChannels) {
      return ListTile(
        leading: SizedBox(
          width: (24 * fontSizeScale).clamp(18, 32),
          height: (24 * fontSizeScale).clamp(18, 32),
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
          ),
        ),
        title: Text(
          appLocalizations.loading ?? 'Загрузка...',
          style: TextStyle(
            fontSize: (18 * fontSizeScale).clamp(14, 22),
            color: isDarkMode ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: (24 * fontSizeScale).clamp(16, 32),
          vertical: (12 * fontSizeScale).clamp(8, 16),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    if (userChannels.isEmpty) {
      return buildMenuItem(
        Icons.add_circle_outline,
        appLocalizations.createChannel ?? 'Создать канал',
        fontSizeScale,
        isDarkMode,
        () async {
          Navigator.pop(context);
          final result = await group.showCreateGroupModal(
            context,
            availableUsers: [],
          );
          if (result != null) {
            widget.onMenuItemClicked('refreshchats');
            loadUserChannels();
          }
        },
      );
    }

    return Column(
      children: [
        ListTile(
          leading: Icon(
            Icons.campaign_rounded,
            color: const Color(0xFFFF9800),
            size: (24 * fontSizeScale).clamp(18, 32),
          ),
          title: Text(
            appLocalizations.channels ?? 'Каналы',
            style: TextStyle(
              fontSize: (18 * fontSizeScale).clamp(14, 22),
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Icon(
            isChannelsExpanded ? Icons.expand_less : Icons.expand_more,
            color: isDarkMode ? Colors.white70 : Colors.black54,
            size: (24 * fontSizeScale).clamp(18, 32),
          ),
          onTap: () {
            setState(() {
              isChannelsExpanded = !isChannelsExpanded;
            });
          },
          tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          contentPadding: EdgeInsets.symmetric(
            horizontal: (24 * fontSizeScale).clamp(16, 32),
            vertical: (12 * fontSizeScale).clamp(8, 16),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        if (isChannelsExpanded) ...[
          ...userChannels.map((channel) => _buildChannelItem(channel, fontSizeScale, isDarkMode)),
          Padding(
            padding: EdgeInsets.only(left: (48 * fontSizeScale).clamp(32, 64)),
            child: ListTile(
              leading: Icon(
                Icons.add_circle_outline,
                color: const Color(0xFF4CAF50),
                size: (20 * fontSizeScale).clamp(16, 28),
              ),
              title: Text(
                appLocalizations.createChannel ?? 'Создать канал',
                style: TextStyle(
                  fontSize: (16 * fontSizeScale).clamp(12, 20),
                  color: const Color(0xFF4CAF50),
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                final result = await group.showCreateGroupModal(
                  context,
                  availableUsers: [],
                );
                if (result != null) {
                  widget.onMenuItemClicked('refreshchats');
                  loadUserChannels();
                }
              },
              tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: (16 * fontSizeScale).clamp(12, 24),
                vertical: (8 * fontSizeScale).clamp(6, 12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChannelItem(Map<String, dynamic> channel, double fontSizeScale, bool isDarkMode) {
    final channelId = channel['id'] as int;
    final channelName = channel['name'] ?? 'Unnamed Channel';

    return Padding(
      padding: EdgeInsets.only(left: (48 * fontSizeScale).clamp(32, 64)),
      child: ListTile(
        leading: Icon(
          Icons.tag,
          color: const Color(0xFFFF9800),
          size: (20 * fontSizeScale).clamp(16, 28),
        ),
        title: Text(
          channelName,
          style: TextStyle(
            fontSize: (16 * fontSizeScale).clamp(12, 20),
            color: isDarkMode ? Colors.white70 : Colors.black87,
            fontWeight: FontWeight.w400,
          ),
        ),
        onTap: () {
          if (widget.onChannelTap != null) {
            Navigator.pop(context);
            widget.onChannelTap!(channelId, channelName);
          }
        },
        tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: (16 * fontSizeScale).clamp(12, 24),
          vertical: (8 * fontSizeScale).clamp(6, 12),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildArchivedMenuItem(double fontSizeScale, AppLocalizations appLocalizations, bool isDarkMode) {
    return ListTile(
      leading: Icon(
        Icons.archive_rounded,
        color: const Color(0xFFFF9800),
        size: (24 * fontSizeScale).clamp(18, 32),
      ),
      title: Row(
        children: [
          Text(
            appLocalizations.archive ?? 'Архив',
            style: TextStyle(
              fontSize: (18 * fontSizeScale).clamp(14, 22),
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (widget.archivedChatsCount > 0) ...[
            SizedBox(width: (12 * fontSizeScale).clamp(8, 16)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: (8 * fontSizeScale).clamp(6, 12),
                vertical: (4 * fontSizeScale).clamp(3, 6),
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800),
                borderRadius: BorderRadius.circular((12 * fontSizeScale).clamp(8, 16)),
              ),
              child: Text(
                widget.archivedChatsCount > 99 ? '99+' : widget.archivedChatsCount.toString(),
                style: TextStyle(
                  fontSize: (12 * fontSizeScale).clamp(10, 14),
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        widget.onMenuItemClicked('archive');
      },
      tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      contentPadding: EdgeInsets.symmetric(
        horizontal: (24 * fontSizeScale).clamp(16, 32),
        vertical: (12 * fontSizeScale).clamp(8, 16),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildFoldersSection(double fontSizeScale, AppLocalizations appLocalizations, bool isDarkMode) {
    if (isLoadingFolders) {
      return ListTile(
        leading: SizedBox(
          width: (24 * fontSizeScale).clamp(18, 32),
          height: (24 * fontSizeScale).clamp(18, 32),
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
          ),
        ),
        title: Text(
          appLocalizations.loading ?? 'Загрузка...',
          style: TextStyle(
            fontSize: (18 * fontSizeScale).clamp(14, 22),
            color: isDarkMode ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: (24 * fontSizeScale).clamp(16, 32),
          vertical: (12 * fontSizeScale).clamp(8, 16),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    return Column(
      children: [
        ListTile(
          leading: Icon(
            Icons.folder_rounded,
            color: const Color(0xFFFF9800),
            size: (24 * fontSizeScale).clamp(18, 32),
          ),
          title: Text(
            appLocalizations.chatFolders ?? 'Папки чатов',
            style: TextStyle(
              fontSize: (18 * fontSizeScale).clamp(14, 22),
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Icon(
            isFoldersExpanded ? Icons.expand_less : Icons.expand_more,
            color: isDarkMode ? Colors.white70 : Colors.black54,
            size: (24 * fontSizeScale).clamp(18, 32),
          ),
          onTap: () {
            setState(() {
              isFoldersExpanded = !isFoldersExpanded;
            });
          },
          tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          contentPadding: EdgeInsets.symmetric(
            horizontal: (24 * fontSizeScale).clamp(16, 32),
            vertical: (12 * fontSizeScale).clamp(8, 16),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        if (isFoldersExpanded) ...[
          Padding(
            padding: EdgeInsets.only(left: (48 * fontSizeScale).clamp(32, 64)),
            child: ListTile(
              leading: Icon(
                Icons.create_new_folder_outlined,
                color: const Color(0xFF4CAF50),
                size: (20 * fontSizeScale).clamp(16, 28),
              ),
              title: Text(
                appLocalizations.createFolder ?? 'Создать папку',
                style: TextStyle(
                  fontSize: (16 * fontSizeScale).clamp(12, 20),
                  color: const Color(0xFF4CAF50),
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: _createNewFolder,
              tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: (16 * fontSizeScale).clamp(12, 24),
                vertical: (8 * fontSizeScale).clamp(6, 12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          ...userFolders.map((folder) => _buildFolderItem(folder, fontSizeScale, isDarkMode)),
        ],
      ],
    );
  }

  Widget _buildFolderItem(Map<String, dynamic> folder, double fontSizeScale, bool isDarkMode) {
    final folderId = folder['id'] as int;
    final folderName = folder['name'] ?? 'Без названия';
    final avatarColor = folder['avatar_color'] != null
        ? Color(int.parse(folder['avatar_color'].replaceFirst('#', '0xFF')))
        : Colors.blue;
    final chats = folder['chats'] as List<dynamic>? ?? [];
    final isExpanded = folder['_isExpanded'] ?? false;

    return Padding(
      padding: EdgeInsets.only(left: (48 * fontSizeScale).clamp(32, 64)),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              radius: (20 * fontSizeScale).clamp(16, 24),
              backgroundColor: avatarColor,
              child: folder['avatar_url'] != null
                  ? null
                  : Icon(Icons.folder_rounded, 
                      color: Colors.white, 
                      size: (20 * fontSizeScale).clamp(16, 24)),
              backgroundImage: folder['avatar_url'] != null
                  ? NetworkImage(folder['avatar_url'])
                  : null,
            ),
            title: Text(
              folderName,
              style: TextStyle(
                fontSize: (16 * fontSizeScale).clamp(12, 20),
                color: isDarkMode ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w400,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: isDarkMode ? Colors.white54 : Colors.grey,
                  size: (20 * fontSizeScale).clamp(16, 28),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert,
                    color: isDarkMode ? Colors.white54 : Colors.grey,
                    size: (20 * fontSizeScale).clamp(16, 28),
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editFolder(folder);
                    } else if (value == 'delete') {
                      _deleteFolder(folderId);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: (20 * fontSizeScale).clamp(16, 28)),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.edit ?? 'Редактировать'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: (20 * fontSizeScale).clamp(16, 28), color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)!.delete ?? 'Удалить',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            onTap: () {
              setState(() {
                folder['_isExpanded'] = !isExpanded;
              });
            },
            tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            contentPadding: EdgeInsets.symmetric(
              horizontal: (16 * fontSizeScale).clamp(12, 24),
              vertical: (8 * fontSizeScale).clamp(6, 12),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          if (isExpanded && chats.isNotEmpty)
            ...chats.map((chat) => _buildFolderChatItem(chat, fontSizeScale, isDarkMode)),
        ],
      ),
    );
  }

  Widget _buildFolderChatItem(dynamic chat, double fontSizeScale, bool isDarkMode) {
    final chatData = chat as Map<String, dynamic>;
    final chatId = chatData['id'] as int;
    final chatTitle = chatData['title'] ?? 'Чат';
    final recipientUserId = chatData['recipient_user_id'];

    return Padding(
      padding: EdgeInsets.only(left: (80 * fontSizeScale).clamp(64, 96)),
      child: ListTile(
        leading: CircleAvatar(
          radius: (16 * fontSizeScale).clamp(12, 20),
          backgroundColor: Colors.grey[300],
          child: Text(
            chatTitle[0].toUpperCase(),
            style: TextStyle(
              fontSize: (12 * fontSizeScale).clamp(10, 14),
              color: Colors.black,
            ),
          ),
        ),
        title: Text(
          chatTitle,
          style: TextStyle(
            fontSize: (14 * fontSizeScale).clamp(12, 18),
            color: isDarkMode ? Colors.white54 : Colors.black54,
          ),
        ),
        onTap: () => _openChatFromFolder(chatId, chatTitle, recipientUserId),
        tileColor: isDarkMode ? const Color(0xFF252525) : Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(
          horizontal: (12 * fontSizeScale).clamp(10, 16),
          vertical: (6 * fontSizeScale).clamp(4, 8),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  Widget buildMenuItem(
    IconData icon,
    String title,
    double fontSizeScale,
    bool isDarkMode,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(
        icon,
        color: const Color(0xFFFF9800),
        size: (24 * fontSizeScale).clamp(18, 32),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: (18 * fontSizeScale).clamp(14, 22),
          color: isDarkMode ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      tileColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      contentPadding: EdgeInsets.symmetric(
        horizontal: (24 * fontSizeScale).clamp(16, 32),
        vertical: (12 * fontSizeScale).clamp(8, 16),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}