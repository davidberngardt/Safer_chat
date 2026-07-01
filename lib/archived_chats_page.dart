// archived_chats_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'models/chat.dart';
import 'chat_page.dart';
import 'ai_chat_page.dart';
import 'providers/font_scale_provider.dart';
import 'utils/platform_utils.dart'; // Добавлен импорт

class ArchivedChatsPage extends StatefulWidget {
  final List<Chat> archivedChats;
  final Function(Chat) onRestoreChat;
  final Function(Chat) onDeleteChat;
  final Function(Chat) onToggleMuteChat;
  final int myUserId;
  final String? token;
  final String baseUrl;

  const ArchivedChatsPage({
    Key? key,
    required this.archivedChats,
    required this.onRestoreChat,
    required this.onDeleteChat,
    required this.onToggleMuteChat,
    required this.myUserId,
    this.token,
    required this.baseUrl,
  }) : super(key: key);

  @override
  _ArchivedChatsPageState createState() => _ArchivedChatsPageState();
}

class _ArchivedChatsPageState extends State<ArchivedChatsPage> {
  // Добавляем геттеры для доступа к свойствам widget
  int get myUserId => widget.myUserId;
  String? get token => widget.token;
  String get baseUrl => widget.baseUrl;

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(time.year, time.month, time.day);

    if (messageDay == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return AppLocalizations.of(context)!.yesterday;
    } else {
      return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}';
    }
  }

  Color _getChatColor(int chatId) {
    final colors = [
      const Color(0xFFFFB74D),
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFF9C27B0),
      const Color(0xFFF44336),
      const Color(0xFF607D8B),
    ];
    return colors[chatId.abs() % colors.length];
  }

  Widget _buildArchivedChatMenu(Chat chat, double fontSizeScale) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert,
        color: Colors.grey[600],
        size: 20 * fontSizeScale,
      ),
      onSelected: (value) {
        switch (value) {
          case 'restore':
            widget.onRestoreChat(chat);
            break;
          case 'mute':
            widget.onToggleMuteChat(chat);
            break;
          case 'delete':
            widget.onDeleteChat(chat);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'mute',
          child: Row(
            children: [
              Icon(
                chat.isMuted ? Icons.volume_up : Icons.volume_off,
                color: Colors.grey[700],
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                chat.isMuted 
                    ? AppLocalizations.of(context)!.unmute
                    : AppLocalizations.of(context)!.mute,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'restore',
          child: Row(
            children: [
              Icon(
                Icons.unarchive,
                color: Colors.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.restore,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.green,
                ),
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
                color: Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.delete,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildArchivedChatItem(Chat chat, double fontSizeScale) {
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: 12 * fontSizeScale,
        vertical: 4 * fontSizeScale,
      ),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12 * fontSizeScale),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getChatColor(chat.id),
          radius: 24 * fontSizeScale,
          child: Text(
            chat.title[0].toUpperCase(),
            style: TextStyle(
              fontSize: 16 * fontSizeScale,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        title: Text(
          chat.title,
          style: TextStyle(
            fontSize: 16 * fontSizeScale,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: chat.lastMessage != null
            ? Text(
                chat.lastMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14 * fontSizeScale,
                  color: Colors.grey[600],
                ),
              )
            : Text(
                AppLocalizations.of(context)!.noMessages,
                style: TextStyle(
                  fontSize: 14 * fontSizeScale,
                  color: Colors.grey,
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (chat.lastMessageTime != null)
                  Text(
                    _formatTime(chat.lastMessageTime!),
                    style: TextStyle(
                      fontSize: 12 * fontSizeScale,
                      color: Colors.grey[500],
                    ),
                  ),
                SizedBox(height: 4 * fontSizeScale),
                if (chat.unreadCount > 0)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8 * fontSizeScale,
                      vertical: 2 * fontSizeScale,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800),
                      borderRadius: BorderRadius.circular(12 * fontSizeScale),
                    ),
                    child: Text(
                      chat.unreadCount > 9 ? '9+' : chat.unreadCount.toString(),
                      style: TextStyle(
                        fontSize: 12 * fontSizeScale,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: 8 * fontSizeScale),
            _buildArchivedChatMenu(chat, fontSizeScale),
          ],
        ),
        onTap: () {
          if (chat.isAIChat) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AIChatPage(
                  chatTitle: 'Чат с ИИ',
                  myUserId: myUserId,
                  chatId: 'ai_chat_${chat.id}',
                  token: token ?? '',
                  baseUrl: baseUrl,
                ),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatPage(
                  myUserId: widget.myUserId,
                  baseUrl: widget.baseUrl,
                  token: widget.token ?? '',
                  chatId: chat.id,
                  chatTitle: chat.title,
                ),
              ),
            );
          }
        },
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16 * fontSizeScale,
          vertical: 8 * fontSizeScale,
        ),
      ),
    );
  }

  Widget _buildEmptyState(double fontSizeScale) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.0 * fontSizeScale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.archive_outlined,
              size: 80 * fontSizeScale,
              color: Colors.grey[400],
            ),
            SizedBox(height: 24 * fontSizeScale),
            Text(
              AppLocalizations.of(context)!.archiveEmpty,
              style: TextStyle(
                fontSize: 20 * fontSizeScale,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 12 * fontSizeScale),
            Text(
              AppLocalizations.of(context)!.archivedChatsWillAppearHere,
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchivedChatsList(double fontSizeScale) {
    if (widget.archivedChats.isEmpty) {
      return _buildEmptyState(fontSizeScale);
    }

    return ListView.builder(
      itemCount: widget.archivedChats.length,
      itemBuilder: (context, index) {
        final chat = widget.archivedChats[index];
        return _buildArchivedChatItem(chat, fontSizeScale);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.archivedChats,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 20 * fontSizeScale,
          ),
        ),
        backgroundColor: const Color(0xFFFFB74D),
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24 * fontSizeScale,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: _buildArchivedChatsList(fontSizeScale),
    );
  }
}