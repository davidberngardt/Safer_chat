import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:provider/provider.dart';
import 'chat_page.dart';
import 'ai_chat_page.dart';
import 'models/chat.dart';
import 'side_menu.dart';
import 'providers/chat_provider.dart';

class HomePage extends StatefulWidget {
  final String token;
  final VoidCallback onLogout;

  const HomePage({
    Key? key,
    required this.token,
    required this.onLogout,
  }) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Chat> _chats = [];
  bool _loading = true;
  late int myUserId;
  final String baseUrl = "http://localhost:3000";

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _loadChats();
  }

  void _initializeUser() {
    try {
      final decoded = JwtDecoder.decode(widget.token);
      myUserId = int.parse(decoded['userId'].toString());
    } catch (e) {
      print('Ошибка при обработке токена: $e');
      myUserId = 1;
    }
  }

  Future<void> _loadChats() async {
    // Имитация загрузки с сервера
    await Future.delayed(const Duration(milliseconds: 1000));
    
    setState(() {
      _chats = [
        // AI чат
        Chat.aiChat(
          id: -1,
          myUserId: myUserId,
          lastMessage: 'Чем могу помочь?',
          lastMessageTime: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        // Обычные чаты
        Chat.regular(
          id: 1,
          title: 'Тестовый чат',
          lastMessage: 'Привет! Это тестовое сообщение для разработки',
          lastMessageTime: DateTime.now().subtract(const Duration(minutes: 5)),
          unreadCount: 2,
          participants: [myUserId, 2],
        ),
        Chat.regular(
          id: 2,
          title: 'Группа разработки',
          lastMessage: 'Нужно протестировать отправку сообщений',
          lastMessageTime: DateTime.now().subtract(const Duration(hours: 2)),
          unreadCount: 0,
          participants: [myUserId, 2, 3],
        ),
        Chat.regular(
          id: 3,
          title: 'Поддержка',
          lastMessage: 'Добро пожаловать в приложение!',
          lastMessageTime: DateTime.now().subtract(const Duration(days: 1)),
          unreadCount: 1,
          participants: [myUserId, 4],
        ),
        Chat.regular(
          id: 4,
          title: 'Алексей',
          lastMessage: 'Когда будет готова новая версия?',
          lastMessageTime: DateTime.now().subtract(const Duration(days: 2)),
          unreadCount: 0,
          participants: [myUserId, 5],
        ),
        Chat.regular(
          id: 5,
          title: 'Команда проекта',
          lastMessage: 'Встреча завтра в 10:00',
          lastMessageTime: DateTime.now().subtract(const Duration(days: 3)),
          unreadCount: 5,
          participants: [myUserId, 2, 3, 4, 5],
        ),
      ];
      _loading = false;
    });
  }

  void _startNewChat() {
    final newChat = Chat.regular(
      id: _chats.length + 1,
      title: 'Новый чат ${_chats.length + 1}',
      lastMessage: 'Это новый тестовый чат',
      lastMessageTime: DateTime.now(),
      unreadCount: 1,
      participants: [myUserId, 6],
    );

    setState(() {
      _chats.insert(1, newChat); // Вставляем после AI чата
    });

    _openChat(newChat);
  }

  void _startNewAIChat() {
    final aiChat = Chat.aiChat(
      id: -DateTime.now().millisecondsSinceEpoch,
      myUserId: myUserId,
      lastMessage: 'Чем могу помочь?',
      lastMessageTime: DateTime.now(),
    );

    setState(() {
      _chats.insert(0, aiChat);
    });

    _openAIChat(aiChat);
  }

  void _openChat(Chat chat) {
    if (chat.isAIChat) {
      _openAIChat(chat);
    } else {
      _openRegularChat(chat);
    }
  }

  void _openRegularChat(Chat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          myUserId: myUserId,
          baseUrl: baseUrl,
          token: widget.token,
          chatId: chat.id,
          chatTitle: chat.title,
        ),
      ),
    ).then((_) {
      _loadChats();
    });
  }

  void _openAIChat(Chat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIChatPage(
          chatTitle: chat.title,
          myUserId: myUserId,
        ),
      ),
    ).then((_) {
      _loadChats();
    });
  }

  Widget _buildChatItem(Chat chat) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: chat.isAIChat 
              ? Colors.purple 
              : _getChatColor(chat.id),
          radius: 24,
          child: Text(
            chat.isAIChat ? '🤖' : chat.title[0].toUpperCase(),
            style: TextStyle(
              fontSize: chat.isAIChat ? 18 : 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        title: Text(
          chat.title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: chat.isAIChat ? Colors.purple : null,
          ),
        ),
        subtitle: chat.lastMessage != null
            ? Text(
                chat.lastMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              )
            : const Text(
                'Нет сообщений',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (chat.lastMessageTime != null)
              Text(
                _formatTime(chat.lastMessageTime!),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            const SizedBox(height: 4),
            if (chat.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: chat.isAIChat ? Colors.purple : const Color(0xFFFF9800),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  chat.unreadCount > 9 ? '9+' : chat.unreadCount.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        onTap: () => _openChat(chat),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            const Text(
              'Пока нет чатов',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Начните новый диалог с AI ассистентом или создайте обычный чат',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Кнопка для AI чата
            ElevatedButton.icon(
              onPressed: _startNewAIChat,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.smart_toy),
              label: const Text(
                'Поговорить с AI',
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),
            // Кнопка для обычного чата
            ElevatedButton.icon(
              onPressed: _startNewChat,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB74D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text(
                'Обычный чат',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    if (_chats.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadChats,
      color: const Color(0xFFFFB74D),
      child: ListView.builder(
        itemCount: _chats.length,
        itemBuilder: (context, index) => _buildChatItem(_chats[index]),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(time.year, time.month, time.day);

    if (messageDay == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return 'Вчера';
    } else {
      return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}';
    }
  }

  void _testAIResponse(ChatProvider chatProvider) async {
    try {
      final response = await chatProvider.openAIService.getBotResponse('Привет!');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI ответил: ${response.substring(0, 50)}...'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка AI: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearAllChats() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить все чаты?'),
        content: const Text('Все чаты будут удалены. Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _chats.clear();
              });
              Navigator.pop(context);
            },
            child: const Text('Очистить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);

    return Scaffold(
      drawer: SideMenu(
        onMenuItemClicked: (title) {
          switch (title) {
            case 'Выйти':
              _showLogoutDialog();
              break;
            case 'Настройки':
              _showSettingsDialog();
              break;
            case 'Контакты':
              _showContactsDialog();
              break;
            case 'Создать чат':
              _startNewChat();
              break;
            case 'AI Ассистент':
              _startNewAIChat();
              break;
            default:
              print('Выбран пункт: $title');
          }
        },
      ),
      appBar: AppBar(
        title: const Text(
          'Мои чаты',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFFFFB74D),
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Кнопка для быстрого создания AI чата
          IconButton(
            icon: const Icon(Icons.smart_toy, color: Colors.white),
            onPressed: _startNewAIChat,
            tooltip: 'Новый AI чат',
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Поиск чатов'),
                  content: const Text('Функция поиска будет реализована позже'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK', style: TextStyle(color: Color(0xFFFF9800))),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadChats,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'add_ai_chat':
                  _startNewAIChat();
                  break;
                case 'add_test_chat':
                  _startNewChat();
                  break;
                case 'test_ai':
                  _testAIResponse(chatProvider);
                  break;
                case 'clear_chats':
                  _clearAllChats();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_ai_chat',
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('Новый AI чат'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_test_chat',
                child: Row(
                  children: [
                    Icon(Icons.chat, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Новый обычный чат'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'test_ai',
                child: Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Тест AI'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_chats',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Очистить все чаты'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFB74D)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Загружаем ваши чаты...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : _buildChatList(),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Кнопка для AI чата
          FloatingActionButton(
            onPressed: _startNewAIChat,
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
            mini: true,
            heroTag: 'ai_chat',
            child: const Icon(Icons.smart_toy, size: 20),
          ),
          const SizedBox(height: 12),
          // Основная кнопка для обычного чата
          FloatingActionButton(
            onPressed: _startNewChat,
            backgroundColor: const Color(0xFFFFB74D),
            foregroundColor: Colors.white,
            heroTag: 'regular_chat',
            child: const Icon(Icons.chat_rounded, size: 28),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Color(0xFFFF9800))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onLogout();
            },
            child: const Text('Выйти', style: TextStyle(color: Color(0xFFFF9800))),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Настройки'),
        content: const Text('Раздел настроек будет реализован позже'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFFFF9800))),
          ),
        ],
      ),
    );
  }

  void _showContactsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Контакты'),
        content: const Text('Раздел контактов будет реализован позже'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFFFF9800))),
          ),
        ],
      ),
    );
  }
}