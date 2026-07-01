// forward_message_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import '../models/message.dart';
import '../models/chat.dart';
import 'chat_page.dart';
import 'providers/font_scale_provider.dart';
import 'utils/platform_utils.dart'; // Добавлен импорт

class ForwardMessagePage extends StatefulWidget {
  final Message message;
  final int myUserId;
  final String token;
  final String baseUrl;

  const ForwardMessagePage({
    Key? key,
    required this.message,
    required this.myUserId,
    required this.token,
    required this.baseUrl,
  }) : super(key: key);

  @override
  _ForwardMessagePageState createState() => _ForwardMessagePageState();
}

class _ForwardMessagePageState extends State<ForwardMessagePage> {
  List<Chat> _chats = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  List<Chat> _filteredChats = [];

  @override
  void initState() {
    super.initState();
    _loadChats();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    // Имитация загрузки списка чатов
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() {
      _chats = [
        Chat.regular(
          id: 1,
          title: AppLocalizations.of(context)!.testChat,
          lastMessage: AppLocalizations.of(context)!.lastMessage,
          lastMessageTime: DateTime.now(),
          unreadCount: 0,
          participants: [widget.myUserId, 2],
          isMuted: false,
          isPinned: false,
          myUserId: widget.myUserId,
        ),
        Chat.regular(
          id: 2,
          title: AppLocalizations.of(context)!.developmentGroup,
          lastMessage: AppLocalizations.of(context)!.needToTest,
          lastMessageTime: DateTime.now(),
          unreadCount: 0,
          participants: [widget.myUserId, 2, 3],
          isMuted: false,
          isPinned: false,
          myUserId: widget.myUserId,
        ),
        Chat.regular(
          id: 3,
          title: AppLocalizations.of(context)!.workChat,
          lastMessage: AppLocalizations.of(context)!.projectDiscussion,
          lastMessageTime: DateTime.now(),
          unreadCount: 0,
          participants: [widget.myUserId, 4, 5],
          isMuted: false,
          isPinned: false,
          myUserId: widget.myUserId,
        ),
        Chat.regular(
          id: 4,
          title: AppLocalizations.of(context)!.family,
          lastMessage: AppLocalizations.of(context)!.weekendPlans,
          lastMessageTime: DateTime.now(),
          unreadCount: 0,
          participants: [widget.myUserId, 6, 7, 8],
          isMuted: false,
          isPinned: false,
          myUserId: widget.myUserId,
        ),
      ];
      _filteredChats = _chats;
      _loading = false;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    
    if (query.isEmpty) {
      setState(() {
        _filteredChats = _chats;
      });
      return;
    }
    
    final results = _chats.where((chat) {
      return chat.title.toLowerCase().contains(query) ||
            (chat.lastMessage ?? '').toLowerCase().contains(query);
    }).toList();
    
    setState(() {
      _filteredChats = results;
    });
  }

  Widget _buildChatItem(Chat chat, double fontSizeScale) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(0xFFFFB74D),
        child: Text(
          chat.title[0].toUpperCase(),
          style: TextStyle(color: Colors.white),
        ),
      ),
      title: Text(
        chat.title,
        style: TextStyle(fontSize: 17 * fontSizeScale),
      ),
      subtitle: Text(
        chat.lastMessage ?? '',
        style: TextStyle(fontSize: 14 * fontSizeScale),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        _forwardToChat(chat);
      },
    );
  }

  void _forwardToChat(Chat chat) {
    // Переходим в выбранный чат с пересылаемым сообщением
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          myUserId: widget.myUserId,
          baseUrl: widget.baseUrl,
          token: widget.token,
          chatId: chat.id,
          chatTitle: chat.title,
          forwardedMessage: widget.message,
        ),
      ),
    );
  }

  Widget _buildSearchBar(double fontSizeScale) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.searchChat,
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.forwardMessage,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 20 * fontSizeScale,
          ),
        ),
        backgroundColor: const Color(0xFFFFB74D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildSearchBar(fontSizeScale),
          
          // Заголовок списка чатов
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.chat, color: Color(0xFFFF9800), size: 20),
                SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.selectChatToForward,
                  style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF9800),
                    ),
                  )
                : _filteredChats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? AppLocalizations.of(context)!.chatsNotFound
                                  : AppLocalizations.of(context)!.noAvailableChats,
                              style: TextStyle(
                                fontSize: 18 * fontSizeScale,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filteredChats.length,
                        separatorBuilder: (context, index) => Divider(height: 1),
                        itemBuilder: (context, index) {
                          return _buildChatItem(_filteredChats[index], fontSizeScale);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}