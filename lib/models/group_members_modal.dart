import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:safer_chat/theme.dart';
import 'package:safer_chat/providers/font_scale_provider.dart';
import 'package:safer_chat/providers/theme_provider.dart';
import '../models/group_member.dart';
import '../services/contacts_modal.dart';
import '../chat_page.dart';
import '../utils/platform_utils.dart';

class GroupMembersModal extends StatefulWidget {
  final int groupId;
  final String groupTitle;
  final String baseUrl;
  final String token;
  final int myUserId;
  final List<GroupMember> members;
  final VoidCallback onMembersUpdated;

  const GroupMembersModal({
    Key? key,
    required this.groupId,
    required this.groupTitle,
    required this.baseUrl,
    required this.token,
    required this.myUserId,
    required this.members,
    required this.onMembersUpdated,
  }) : super(key: key);

  @override
  State<GroupMembersModal> createState() => _GroupMembersModalState();
}

class _GroupMembersModalState extends State<GroupMembersModal> {
  final TextEditingController searchController = TextEditingController();
  List<GroupMember> filteredMembers = [];
  bool isOwner = false;
  bool isAddingMembers = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    filteredMembers = widget.members;
    searchController.addListener(_filterMembers);
    _checkOwnership();
  }

  @override
  void dispose() {
    searchController.removeListener(_filterMembers);
    searchController.dispose();
    super.dispose();
  }

  void _checkOwnership() {
    final owner = widget.members.firstWhere(
      (m) => m.role == 'admin',
      orElse: () => widget.members.first,
    );
    setState(() {
      isOwner = owner.userId == widget.myUserId;
    });
  }

  void _filterMembers() {
    final query = searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredMembers = widget.members;
      } else {
        filteredMembers = widget.members.where((member) {
          return member.displayName.toLowerCase().contains(query) ||
              member.nickname.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _addMembers() async {
    final result = await showContactsModal(
      context,
      widget.token,
      widget.baseUrl,
      widget.myUserId,
      null,
    );

    if (result != null && result['userId'] != null) {
      _addMemberToGroup(result['userId'] as int);
    }
  }

  Future<void> _addMemberToGroup(int userId) async {
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
        '${widget.baseUrl}/api/groups/${widget.groupId}/members',
        data: {'user_id': userId},
      );

      if (response.statusCode == 200) {
        widget.onMembersUpdated();
        Navigator.pop(context);
      } else {
        _showErrorDialog('Не удалось добавить участника');
      }
    } catch (e) {
      _showErrorDialog('Ошибка: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _removeMember(GroupMember member) async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.removeMember ?? 'Удалить участника'),
        content: Text(
          '${localizations.areYouSureRemoveMember ?? 'Вы уверены, что хотите удалить'} ${member.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.cancel ?? 'Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(localizations.remove ?? 'Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      isLoading = true;
    });

    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
      };

      final response = await dio.delete(
        '${widget.baseUrl}/api/groups/${widget.groupId}/members/${member.userId}',
      );

      if (response.statusCode == 200) {
        widget.onMembersUpdated();
        Navigator.pop(context);
      } else {
        _showErrorDialog('Не удалось удалить участника');
      }
    } catch (e) {
      _showErrorDialog('Ошибка: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _openChatWithMember(GroupMember member) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          myUserId: widget.myUserId,
          baseUrl: widget.baseUrl,
          token: widget.token,
          chatId: 0,
          chatTitle: member.displayName,
          recipientUserId: member.userId,
        ),
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
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localizations = AppLocalizations.of(context)!;
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
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
                  Expanded(
                    child: Text(
                      localizations.members ?? 'Участники',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isOwner && !isLoading)
                    IconButton(
                      icon: const Icon(Icons.person_add, color: Colors.white),
                      onPressed: _addMembers,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: searchController,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: localizations.searchPlaceholder ?? 'Поиск участников...',
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                  filled: true,
                  fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

            // Members list
            Expanded(
              child: isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: MessengerTheme.lightAccent,
                      ),
                    )
                  : filteredMembers.isEmpty
                      ? Center(
                          child: Text(
                            localizations.noMatches ?? 'Нет совпадений',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDarkMode ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                          itemCount: filteredMembers.length,
                          itemBuilder: (context, index) {
                            final member = filteredMembers[index];
                            final isMe = member.userId == widget.myUserId;
                            final isAdmin = member.role == 'admin';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: member.avatarColor,
                                  child: Text(
                                    member.displayName[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        member.displayName,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: isDarkMode ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (isAdmin)
                                      Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: MessengerTheme.lightAccent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          localizations.admin ?? 'Админ',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: MessengerTheme.lightAccent,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    if (isMe)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          localizations.you ?? 'Вы',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDarkMode ? Colors.white70 : Colors.black54,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  member.nickname,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDarkMode ? Colors.white54 : Colors.black54,
                                  ),
                                ),
                                onTap: () => _openChatWithMember(member),
                                trailing: isOwner && !isMe && !isLoading
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.remove_circle_outline,
                                          color: MessengerTheme.darkError,
                                        ),
                                        onPressed: () => _removeMember(member),
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
