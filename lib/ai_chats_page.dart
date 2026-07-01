// ai_chats_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:safer_chat/providers/font_scale_provider.dart';
import 'package:safer_chat/providers/ai_chats_provider.dart';
import 'package:safer_chat/providers/ai_chat_provider.dart';
import 'package:safer_chat/ai_chat_page.dart';
import 'package:safer_chat/utils/platform_utils.dart';

class AIChatsPage extends StatefulWidget {
  final int myUserId;
  final String token;
  final String baseUrl;

  const AIChatsPage({
    Key? key,
    required this.myUserId,
    required this.token,
    required this.baseUrl,
  }) : super(key: key);

  @override
  _AIChatsPageState createState() => _AIChatsPageState();
}

class _AIChatsPageState extends State<AIChatsPage> with WidgetsBindingObserver {
  String? _editingChatId;
  final TextEditingController _editingController = TextEditingController();
  final FocusNode _editingFocusNode = FocusNode();
  late AIChatsProvider _chatsProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AIChatsProvider>(context, listen: false);
      provider.loadChats();
      _chatsProvider = provider;
    });
    
    // Добавляем наблюдатель для отслеживания возврата на страницу
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatsProvider = Provider.of<AIChatsProvider>(context, listen: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editingController.dispose();
    _editingFocusNode.dispose();
    super.dispose();
  }

  // Обновляем список при возврате на страницу
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Не нужно для этой логики
  }

  @override
  void didPush() {
    // Вызывается при возврате на страницу из навигатора
    print('🔄 Возврат на страницу AI чатов - обновляем список');
    _chatsProvider.loadChats();
  }

  @override
  Widget build(BuildContext context) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final appLocalizations = AppLocalizations.of(context)!;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.psychology_outlined, color: Colors.white),
            SizedBox(width: 8),
            Text(
              appLocalizations.aiAssistant,
              style: TextStyle(fontSize: 18 * fontSizeScale),
            ),
          ],
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _openNewAIChat(context),
            tooltip: appLocalizations.newChat,
          ),
        ],
      ),
      body: _buildBody(fontSizeScale, appLocalizations),
    );
  }

  Widget _buildBody(double fontSizeScale, AppLocalizations appLocalizations) {
    if (_chatsProvider.isLoading) {
      return _buildLoadingIndicator(fontSizeScale, appLocalizations);
    }

    if (_chatsProvider.chats.isEmpty) {
      return _buildEmptyState(fontSizeScale, appLocalizations);
    }

    return _buildChatsList(fontSizeScale, appLocalizations);
  }

  Widget _buildLoadingIndicator(double fontSizeScale, AppLocalizations appLocalizations) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.deepOrange),
          SizedBox(height: 20 * fontSizeScale),
          Text(
            appLocalizations.loading,
            style: TextStyle(
              fontSize: 16 * fontSizeScale,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(double fontSizeScale, AppLocalizations appLocalizations) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 80 * fontSizeScale,
            color: Colors.grey[400],
          ),
          SizedBox(height: 24 * fontSizeScale),
          Text(
            appLocalizations.noAIChatsYet,
            style: TextStyle(
              fontSize: 20 * fontSizeScale,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 32 * fontSizeScale),
          ElevatedButton.icon(
            onPressed: () => _openNewAIChat(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: 24 * fontSizeScale,
                vertical: 12 * fontSizeScale,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24 * fontSizeScale),
              ),
            ),
            icon: Icon(Icons.add, size: 20 * fontSizeScale),
            label: Text(
              appLocalizations.newChat,
              style: TextStyle(fontSize: 16 * fontSizeScale),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList(double fontSizeScale, AppLocalizations appLocalizations) {
    // Сортируем чаты: сначала закрепленные, затем обычные
    final pinnedChats = _chatsProvider.chats.where((chat) => chat.isPinned).toList();
    final regularChats = _chatsProvider.chats.where((chat) => !chat.isPinned).toList();
    
    // Сортируем по времени последнего сообщения
    pinnedChats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    regularChats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    
    final allChats = [...pinnedChats, ...regularChats];
    
    return ListView.builder(
      padding: EdgeInsets.all(16 * fontSizeScale),
      itemCount: allChats.length,
      itemBuilder: (context, index) {
        final chat = allChats[index];
        return _buildChatItem(chat, fontSizeScale, appLocalizations);
      },
    );
  }

  Widget _buildChatItem(AIChat chat, double fontSizeScale, AppLocalizations appLocalizations) {
    final isEditing = _editingChatId == chat.id;

    return Card(
      margin: EdgeInsets.only(bottom: 12 * fontSizeScale),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12 * fontSizeScale),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.all(16 * fontSizeScale),
        leading: Container(
          width: 50 * fontSizeScale,
          height: 50 * fontSizeScale,
          decoration: BoxDecoration(
            color: Colors.deepOrange[100],
            shape: BoxShape.circle,
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  Icons.psychology_outlined,
                  color: Colors.deepOrange,
                  size: 24 * fontSizeScale,
                ),
              ),
              if (chat.isPinned)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 18 * fontSizeScale,
                    height: 18 * fontSizeScale,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
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
          ),
        ),
        title: isEditing
            ? TextField(
                controller: _editingController,
                focusNode: _editingFocusNode,
                style: TextStyle(
                  fontSize: 18 * fontSizeScale,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: appLocalizations.enterNewChatName,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                autofocus: true,
                onSubmitted: (value) {
                  _finishEditing(chat, value.trim());
                },
                onEditingComplete: () {
                  _finishEditing(chat, _editingController.text.trim());
                },
              )
            : Text(
                // Используем displayTitle вместо lastMessage
                chat.displayTitle ?? chat.lastMessage ?? 'Новый чат',
                style: TextStyle(
                  fontSize: 18 * fontSizeScale,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        subtitle: null,
        trailing: isEditing
            ? IconButton(
                icon: Icon(Icons.check, color: Colors.green),
                onPressed: () {
                  _finishEditing(chat, _editingController.text.trim());
                },
              )
            : PopupMenuButton<String>(
                icon: Icon(Icons.more_vert),
                onSelected: (value) => _handleMenuItemSelected(value, chat, appLocalizations),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue, size: 20 * fontSizeScale),
                        SizedBox(width: 8 * fontSizeScale),
                        Text(appLocalizations.renameChat),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pin',
                    child: Row(
                      children: [
                        Icon(
                          chat.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          color: Colors.orange,
                          size: 20 * fontSizeScale,
                        ),
                        SizedBox(width: 8 * fontSizeScale),
                        Text(chat.isPinned ? appLocalizations.unpin : appLocalizations.pin),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red, size: 20 * fontSizeScale),
                        SizedBox(width: 8 * fontSizeScale),
                        Text(appLocalizations.delete),
                      ],
                    ),
                  ),
                ],
              ),
        onTap: () {
          if (!isEditing) {
            _openAIChat(chat);
          }
        },
        onLongPress: () {
          if (!isEditing) {
            _startEditing(chat);
          }
        },
      ),
    );
  }

  void _startEditing(AIChat chat) {
    setState(() {
      _editingChatId = chat.id;
      _editingController.text = chat.displayTitle ?? chat.lastMessage ?? '';
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editingFocusNode.requestFocus();
    });
  }

  void _finishEditing(AIChat chat, String newTitle) {
    if (newTitle.isNotEmpty && newTitle != (chat.displayTitle ?? chat.lastMessage)) {
      _chatsProvider.renameChat(chat.id, newTitle);
    }
    
    setState(() {
      _editingChatId = null;
    });
    _editingController.clear();
  }

  void _handleMenuItemSelected(String value, AIChat chat, AppLocalizations appLocalizations) {
    switch (value) {
      case 'rename':
        _startEditing(chat);
        break;
      case 'pin':
        _chatsProvider.togglePin(chat.id);
        break;
      case 'delete':
        _showDeleteDialog(chat, appLocalizations);
        break;
    }
  }

  void _showDeleteDialog(AIChat chat, AppLocalizations appLocalizations) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appLocalizations.deleteChat),
        content: Text(appLocalizations.allMessagesInThisChatWillBeDeleted),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(appLocalizations.cancel),
          ),
          TextButton(
            onPressed: () {
              _chatsProvider.deleteChat(chat.id);
              Navigator.pop(context);
            },
            child: Text(
              appLocalizations.delete,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _openNewAIChat(BuildContext context) {
    final newChatId = _chatsProvider.generateNewChatId();
    
    _chatsProvider.createOrUpdateChat(
      chatId: newChatId,
      title: '',
      lastMessage: null,
    );
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (context) => AIChatProvider(
            baseUrl: widget.baseUrl,
            token: widget.token,
            userId: widget.myUserId,
          ),
          child: AIChatPage(
            chatTitle: '',
            myUserId: widget.myUserId,
            chatId: newChatId,
            token: widget.token,
            baseUrl: widget.baseUrl,
            aiChatsProvider: _chatsProvider,
          ),
        ),
      ),
    ).then((_) {
      // Обновляем список при возврате из чата
      print('🔄 Возврат из нового чата - обновляем список');
      _chatsProvider.loadChats();
    });
  }

  void _openAIChat(AIChat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (context) => AIChatProvider(
            baseUrl: widget.baseUrl,
            token: widget.token,
            userId: widget.myUserId,
          ),
          child: AIChatPage(
            chatTitle: chat.displayTitle ?? chat.lastMessage ?? '',
            myUserId: widget.myUserId,
            chatId: chat.id,
            token: widget.token,
            baseUrl: widget.baseUrl,
            aiChatsProvider: _chatsProvider,
          ),
        ),
      ),
    ).then((_) {
      // Обновляем список при возврате из чата
      print('🔄 Возврат из чата - обновляем список');
      _chatsProvider.loadChats();
    });
  }
}