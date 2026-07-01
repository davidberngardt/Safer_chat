import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:safer_chat/theme.dart';
import '../providers/font_scale_provider.dart';
import '../providers/theme_provider.dart';

class InviteUsersModal extends StatefulWidget {
  final int channelId;
  final String channelTitle;
  final String baseUrl;
  final String token;
  final int myUserId;
  final Function(int)? onInviteSent;

  const InviteUsersModal({
    Key? key,
    required this.channelId,
    required this.channelTitle,
    required this.baseUrl,
    required this.token,
    required this.myUserId,
    this.onInviteSent,
  }) : super(key: key);

  @override
  _InviteUsersModalState createState() => _InviteUsersModalState();
}

class _InviteUsersModalState extends State<InviteUsersModal> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  Set<int> _selectedUserIds = {};
  bool _isLoading = true;
  bool _isSendingInvites = false;
  String _myName = 'Пользователь';

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    _searchController.addListener(_filterContacts);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterContacts);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMyProfile() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/profile',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final userName = data['user']?['username'] ?? 
                        data['user']?['name'] ?? 
                        data['username'] ?? 
                        data['name'] ?? 
                        'Пользователь';
        
        setState(() {
          _myName = userName;
        });
      }
    } catch (e) {
      // Используем значение по умолчанию
    }
    
    // Загружаем контакты после загрузки профиля
    await _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/contacts',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true && data['contacts'] != null) {
          final contacts = List<Map<String, dynamic>>.from(data['contacts']);
          
          setState(() {
            _contacts = contacts.where((contact) {
              return contact['contact_user_id'] != widget.myUserId;
            }).toList();
            _filteredContacts = List.from(_contacts);
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterContacts() {
    final query = _searchController.text.toLowerCase().trim();
    
    if (query.isEmpty) {
      setState(() {
        _filteredContacts = List.from(_contacts);
      });
      return;
    }

    final filtered = _contacts.where((contact) {
      final name = contact['contact_name']?.toString().toLowerCase() ?? '';
      final username = contact['username']?.toString().toLowerCase() ?? '';
      return name.contains(query) || username.contains(query);
    }).toList();

    setState(() {
      _filteredContacts = filtered;
    });
  }

  void _toggleUserSelection(int userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _sendInvitations() async {
    if (_selectedUserIds.isEmpty) return;

    setState(() {
      _isSendingInvites = true;
    });

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      int successfulInvites = 0;

      for (final userId in _selectedUserIds) {
        try {
          // Получаем имя пользователя из контактов
          final contact = _contacts.firstWhere(
            (c) => c['contact_user_id'] == userId,
            orElse: () => {'contact_name': AppLocalizations.of(context)!.user},
          );
          
          final userName = contact['contact_name'] ?? contact['username'] ?? AppLocalizations.of(context)!.user;
          
          // Формируем текст приглашения с локализацией
          final invitationText = AppLocalizations.of(context)!.userInvitesYouToChannel(
            _myName,
            widget.channelTitle,
          );
          
          // Форматируем сообщение с кликабельной ссылкой
          final messageText = '$invitationText 👉 [${widget.channelTitle}](${widget.baseUrl}/channels/${widget.channelId})';

          final messageResponse = await dio.post(
            '${widget.baseUrl}/api/send-message',
            data: {
              'user_id': userId,
              'text': messageText,
              'type_id': 1,
              'is_invitation': true,
              'invitation_channel_id': widget.channelId,
              'metadata': {
                'channel_title': widget.channelTitle,
                'channel_id': widget.channelId,
                'inviter_name': _myName,
                'inviter_id': widget.myUserId,
                'invitation_text': invitationText,
              },
            },
          );

          if (messageResponse.statusCode == 200) {
            successfulInvites++;
          }
        } catch (e) {
          // Продолжаем отправку другим пользователям даже если один не удался
        }
      }

      if (successfulInvites > 0) {
        if (widget.onInviteSent != null) {
          widget.onInviteSent!(successfulInvites);
        }
        Navigator.pop(context);
      } else {
        _showErrorDialog(AppLocalizations.of(context)!.failedToSendInvitations);
      }
    } catch (e) {
      _showErrorDialog(AppLocalizations.of(context)!.errorSendingInvitations);
    } finally {
      setState(() {
        _isSendingInvites = false;
      });
    }
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
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
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

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, size: 24 * fontSizeScale),
                    onPressed: () => Navigator.pop(context),
                  ),
                  SizedBox(width: 12 * fontSizeScale),
                  Expanded(
                    child: Text(
                      localizations.invite ?? 'Пригласить',
                      style: TextStyle(
                        fontSize: 18 * fontSizeScale,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Поиск
            Container(
              padding: EdgeInsets.all(16 * fontSizeScale),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: localizations.search,
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10 * fontSizeScale),
                  ),
                  filled: true,
                  fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                ),
              ),
            ),

            // Список контактов
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: MessengerTheme.lightAccent,
                      ),
                    )
                  : _filteredContacts.isEmpty
                      ? Center(
                          child: Text(
                            _contacts.isEmpty
                                ? localizations.noContacts
                                : localizations.noResultsFound,
                            style: TextStyle(
                              fontSize: 16 * fontSizeScale,
                              color: isDarkMode ? Colors.white70 : Colors.grey[600],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(bottom: 80 * fontSizeScale),
                          itemCount: _filteredContacts.length,
                          itemBuilder: (context, index) {
                            final contact = _filteredContacts[index];
                            final userId = contact['contact_user_id'];
                            final userName = contact['contact_name'] ?? contact['username'] ?? localizations.user;
                            final isSelected = _selectedUserIds.contains(userId);

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _toggleUserSelection(userId),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16 * fontSizeScale,
                                    vertical: 12 * fontSizeScale,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: isDarkMode ? Colors.white12 : Colors.grey[200]!,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40 * fontSizeScale,
                                        height: 40 * fontSizeScale,
                                        decoration: BoxDecoration(
                                          gradient: MessengerTheme.getAvatarGradient(userId),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 24 * fontSizeScale,
                                        ),
                                      ),
                                      SizedBox(width: 12 * fontSizeScale),
                                      Expanded(
                                        child: Text(
                                          userName,
                                          style: TextStyle(
                                            fontSize: 16 * fontSizeScale,
                                            color: isDarkMode ? Colors.white : Colors.black,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle,
                                          color: MessengerTheme.lightAccent,
                                          size: 24 * fontSizeScale,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Кнопка пригласить (фиксированная внизу)
            if (!_isLoading && _filteredContacts.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.all(16 * fontSizeScale),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: isDarkMode ? Colors.white24 : Colors.grey[300]!,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: _selectedUserIds.isNotEmpty && !_isSendingInvites
                          ? MessengerTheme.lightAccent
                          : Colors.grey,
                      padding: EdgeInsets.symmetric(
                        vertical: 16 * fontSizeScale,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10 * fontSizeScale),
                      ),
                      minimumSize: Size(double.infinity, 0),
                    ),
                    onPressed: _selectedUserIds.isNotEmpty && !_isSendingInvites
                        ? _sendInvitations
                        : null,
                    child: _isSendingInvites
                        ? SizedBox(
                            width: 24 * fontSizeScale,
                            height: 24 * fontSizeScale,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            '${localizations.invite} (${_selectedUserIds.length})',
                            style: TextStyle(
                              fontSize: 16 * fontSizeScale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}