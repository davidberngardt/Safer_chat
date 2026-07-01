// ai_chat_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import '../models/ai_message.dart';
import '../providers/font_scale_provider.dart';
import '../providers/ai_chats_provider.dart';
import '../providers/ai_chat_provider.dart';
import '../utils/platform_utils.dart';

class AIChatPage extends StatefulWidget {
  final String chatTitle;
  final int myUserId;
  final String chatId;
  final String token;
  final String baseUrl;
  final AIChatsProvider? aiChatsProvider;

  const AIChatPage({
    Key? key,
    required this.chatTitle,
    required this.myUserId,
    required this.chatId,
    required this.token,
    required this.baseUrl,
    this.aiChatsProvider,
  }) : super(key: key);

  @override
  _AIChatPageState createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _hasFirstMessage = false;
  bool _isHistoryLoaded = false;
  bool _isSendingMessage = false;
  
  // Для определения нажатия Shift
  bool _shiftPressed = false;
  
  AnimationController? _dot1Controller;
  AnimationController? _dot2Controller;
  AnimationController? _dot3Controller;

  // Локальный экземпляр AIChatsProvider для fallback
  AIChatsProvider? _localChatsProvider;

  // Маппинг для хранения состояния кнопок копирования для каждого сообщения
  final Map<String, bool> _copyButtonStates = {};

  @override
  void initState() {
    super.initState();
    
    _initializeAnimationControllers();
    
    // Инициализируем локальный провайдер, если не передан извне
    if (widget.aiChatsProvider == null) {
      _localChatsProvider = AIChatsProvider(
        baseUrl: widget.baseUrl,
        token: widget.token,
        userId: widget.myUserId,
      );
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChatHistory();
      _focusNode.requestFocus();
    });
  }

  void _initializeAnimationControllers() {
    _dot1Controller = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
    
    _dot2Controller = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
    
    _dot3Controller = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
  }

  void _startDotAnimations() {
    if (_dot1Controller != null && !_dot1Controller!.isAnimating) {
      _dot1Controller!.repeat(reverse: true);
    }
    if (_dot2Controller != null && !_dot2Controller!.isAnimating) {
      Future.delayed(Duration(milliseconds: 200), () {
        if (mounted && _dot2Controller != null) {
          _dot2Controller!.repeat(reverse: true);
        }
      });
    }
    if (_dot3Controller != null && !_dot3Controller!.isAnimating) {
      Future.delayed(Duration(milliseconds: 400), () {
        if (mounted && _dot3Controller != null) {
          _dot3Controller!.repeat(reverse: true);
        }
      });
    }
  }

  void _stopDotAnimations() {
    if (_dot1Controller != null && _dot1Controller!.isAnimating) {
      _dot1Controller!.stop();
      _dot1Controller!.reset();
    }
    if (_dot2Controller != null && _dot2Controller!.isAnimating) {
      _dot2Controller!.stop();
      _dot2Controller!.reset();
    }
    if (_dot3Controller != null && _dot3Controller!.isAnimating) {
      _dot3Controller!.stop();
      _dot3Controller!.reset();
    }
  }

  // Получаем активный провайдер чатов
  AIChatsProvider _getChatsProvider() {
    return widget.aiChatsProvider ?? _localChatsProvider!;
  }

  @override
  void dispose() {
    // Сохраняем историю перед закрытием
    if (mounted && _isHistoryLoaded) {
      try {
        final chatProvider = Provider.of<AIChatProvider>(context, listen: false);
        if (chatProvider.messages.isNotEmpty) {
          final messages = chatProvider.messages.where((msg) => !msg.isStreaming).toList();
          if (messages.isNotEmpty) {
            _getChatsProvider().saveChatHistory(widget.chatId, messages);
          }
        }
      } catch (e) {
        print('⚠️ Ошибка при сохранении истории: $e');
      }
    }
    
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    
    if (_dot1Controller != null) {
      _dot1Controller!.dispose();
    }
    if (_dot2Controller != null) {
      _dot2Controller!.dispose();
    }
    if (_dot3Controller != null) {
      _dot3Controller!.dispose();
    }
    
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
            Expanded(
              child: Text(
                widget.chatTitle.isEmpty ? 'AI Assistant' : widget.chatTitle,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18 * fontSizeScale,
                  overflow: TextOverflow.ellipsis,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Consumer<AIChatProvider>(
        builder: (context, chatProvider, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (chatProvider.messages.isNotEmpty) {
              _scrollToBottom();
            }
          });

          return Column(
            children: [
              Expanded(
                child: _buildMessagesList(chatProvider, fontSizeScale, appLocalizations),
              ),
              _buildMessageInput(chatProvider, fontSizeScale, appLocalizations),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadChatHistory() async {
    try {
      final chatProvider = Provider.of<AIChatProvider>(context, listen: false);
      
      try {
        await chatProvider.loadMessagesFromPostgres(widget.chatId);
      } catch (e) {
        print('Ошибка загрузки через loadMessagesFromPostgres: $e');
        // Fallback на старый метод
        await _loadHistoryFallback();
      }
      
      // Проверяем, есть ли сообщения
      if (chatProvider.messages.isNotEmpty) {
        setState(() {
          _hasFirstMessage = true;
        });
      }
      
      _isHistoryLoaded = true;
    } catch (e) {
      print('Error loading chat history: $e');
      _isHistoryLoaded = true;
    }
  }

  Future<void> _loadHistoryFallback() async {
    try {
      final messages = await _getChatsProvider().loadChatHistory(widget.chatId);
      
      final chatProvider = Provider.of<AIChatProvider>(context, listen: false);
      chatProvider.loadMessages(messages);
      
      if (messages.isNotEmpty) {
        setState(() {
          _hasFirstMessage = true;
        });
      }
    } catch (e) {
      print('Fallback history load error: $e');
    }
  }

  String _extractFirstSentence(String text) {
    text = text.trim();
    
    final endOfSentencePatterns = ['.', '!', '?', '\n'];
    int endIndex = text.length;
    
    for (var pattern in endOfSentencePatterns) {
      final index = text.indexOf(pattern);
      if (index != -1 && index < endIndex) {
        endIndex = index;
      }
    }
    
    final firstSentence = endIndex < text.length ? text.substring(0, endIndex + 1) : text;
    
    if (firstSentence.length > 30) {
      return '${firstSentence.substring(0, 27)}...';
    }
    
    return firstSentence;
  }

  Widget _buildMessagesList(AIChatProvider chatProvider, double fontSizeScale, AppLocalizations appLocalizations) {
    if (chatProvider.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.psychology_outlined,
              size: 64 * fontSizeScale,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16 * fontSizeScale),
            Text(
              appLocalizations.startChatWithAIAssistant,
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(16 * fontSizeScale),
      itemCount: chatProvider.messages.length,
      itemBuilder: (context, index) {
        final message = chatProvider.messages[index];
        return _buildMessageBubble(message, fontSizeScale, appLocalizations);
      },
    );
  }

  // ИСПРАВЛЕНО: Используем PlatformUtils для копирования
  void _copyToClipboard(String text, BuildContext context, [String? messageId]) async {
    try {
      await PlatformUtils.copyToClipboard(text);
      
      if (messageId != null && messageId.isNotEmpty) {
        setState(() {
          _copyButtonStates[messageId] = true;
        });
        
        Future.delayed(Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _copyButtonStates[messageId] = false;
            });
          }
        });
      }
    } catch (e) {
      print('Не удалось скопировать текст: $e');
    }
  }

  Widget _buildMessageBubble(AIMessage message, double fontSizeScale, AppLocalizations appLocalizations) {
    final isStreaming = message.isStreaming;
    
    // Запускаем/останавливаем анимацию в зависимости от состояния
    if (isStreaming && message.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startDotAnimations();
      });
    } else if (!isStreaming) {
      _stopDotAnimations();
    }
    
    // Инициализируем состояние кнопки копирования для этого сообщения
    final messageId = message.id;
    if (!isStreaming && messageId != null && messageId.isNotEmpty && !_copyButtonStates.containsKey(messageId)) {
      _copyButtonStates[messageId] = false;
    }
    
    // Простой fallback если контроллеры не инициализированы
    Widget typingIndicator;
    if (_dot1Controller != null && _dot2Controller != null && _dot3Controller != null) {
      typingIndicator = _buildAnimatedTypingDots(fontSizeScale);
    } else {
      typingIndicator = _buildSimpleTypingDots(fontSizeScale);
    }
    
    // Проверяем состояние кнопки копирования для этого сообщения
    final isCopied = messageId != null ? _copyButtonStates[messageId] == true : false;
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4 * fontSizeScale),
      child: Row(
        mainAxisAlignment: message.isFromUser 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isFromUser) ...[
            CircleAvatar(
              backgroundColor: Colors.deepOrange[100],
              radius: 16 * fontSizeScale,
              child: Icon(
                Icons.psychology_outlined,
                size: 16 * fontSizeScale, 
                color: Colors.deepOrange,
              ),
            ),
            SizedBox(width: 8 * fontSizeScale),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: EdgeInsets.all(12 * fontSizeScale),
              decoration: BoxDecoration(
                color: message.isFromUser 
                    ? Colors.deepOrange.withOpacity(0.8)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(16 * fontSizeScale),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isStreaming && message.text.isEmpty)
                    typingIndicator
                  else if (isStreaming)
                    SelectableText(
                      message.text,
                      style: TextStyle(
                        fontSize: 16 * fontSizeScale,
                        color: Colors.black87,
                      ),
                    )
                  else
                    SelectableText(
                      message.text,
                      style: TextStyle(
                        fontSize: 16 * fontSizeScale,
                        color: message.isFromUser ? Colors.white : Colors.black87,
                      ),
                    ),
                  
                  SizedBox(height: 4 * fontSizeScale),
                  
                  if (!isStreaming) // Показываем время и кнопку копирования только для завершенных сообщений
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 10 * fontSizeScale,
                            color: message.isFromUser ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                        
                        // Кнопка копирования с галочкой при успешном копировании
                        GestureDetector(
                          onTap: () => _copyToClipboard(message.text, context, messageId),
                          child: Container(
                            padding: EdgeInsets.all(4 * fontSizeScale),
                            decoration: BoxDecoration(
                              color: message.isFromUser 
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(6 * fontSizeScale),
                            ),
                            child: isCopied
                                ? Icon(
                                    Icons.check,
                                    size: 12 * fontSizeScale,
                                    color: message.isFromUser ? Colors.white70 : Colors.grey[600],
                                  )
                                : Icon(
                                    Icons.content_copy,
                                    size: 12 * fontSizeScale,
                                    color: message.isFromUser ? Colors.white70 : Colors.grey[600],
                                  ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (message.isFromUser) SizedBox(width: 8 * fontSizeScale),
        ],
      ),
    );
  }

  // Простые статичные точки как fallback
  Widget _buildSimpleTypingDots(double fontSizeScale) {
    return SizedBox(
      width: 50 * fontSizeScale,
      height: 20 * fontSizeScale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8 * fontSizeScale,
            height: 8 * fontSizeScale,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 4 * fontSizeScale),
          Container(
            width: 8 * fontSizeScale,
            height: 8 * fontSizeScale,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 4 * fontSizeScale),
          Container(
            width: 8 * fontSizeScale,
            height: 8 * fontSizeScale,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  // Анимированные точки
  Widget _buildAnimatedTypingDots(double fontSizeScale) {
    return SizedBox(
      width: 50 * fontSizeScale,
      height: 20 * fontSizeScale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildAnimatedDot(_dot1Controller!, fontSizeScale),
          SizedBox(width: 4 * fontSizeScale),
          _buildAnimatedDot(_dot2Controller!, fontSizeScale),
          SizedBox(width: 4 * fontSizeScale),
          _buildAnimatedDot(_dot3Controller!, fontSizeScale),
        ],
      ),
    );
  }

  // Анимированная точка
  Widget _buildAnimatedDot(AnimationController controller, double fontSizeScale) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.3 + (controller.value * 0.7),
          child: Transform.scale(
            scale: 0.7 + (controller.value * 0.3),
            child: Container(
              width: 8 * fontSizeScale,
              height: 8 * fontSizeScale,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }

  // ИСПРАВЛЕНО: Точно как в chat_page.dart
  Widget _buildMessageInput(AIChatProvider chatProvider, double fontSizeScale, AppLocalizations appLocalizations) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8 * fontSizeScale,
        vertical: 6 * fontSizeScale
      ),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
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
                    // Отправка по Enter (без Shift)
                    if (event.logicalKey == LogicalKeyboardKey.enter &&
                        !_shiftPressed) {
                      _sendMessage(chatProvider);
                    }
                  } else if (event is RawKeyUpEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                        event.logicalKey == LogicalKeyboardKey.shiftRight) {
                      _shiftPressed = false;
                    }
                  }
                },
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: null,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  enableInteractiveSelection: true,
                  style: TextStyle(fontSize: 16 * fontSizeScale),
                  decoration: InputDecoration(
                    hintText: appLocalizations.enterMessage,
                    hintStyle: TextStyle(fontSize: 16 * fontSizeScale),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12 * fontSizeScale,
                      vertical: 12 * fontSizeScale
                    ),
                  ),
                  // Убираем onSubmitted полностью
                ),
              ),
            ),
          ),
          
          IconButton(
            icon: Icon(
              Icons.send,
              color: _isSendingMessage || chatProvider.isLoading
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
                  : Colors.deepOrange,
              size: 28 * fontSizeScale,
            ),
            onPressed: _isSendingMessage || chatProvider.isLoading
                ? null 
                : () => _sendMessage(chatProvider),
          ),
        ],
      ),
    );
  }

  // ИСПРАВЛЕНО: Улучшенный метод отправки с очисткой
  void _sendMessage(AIChatProvider chatProvider) async {
    if (_isSendingMessage || chatProvider.isLoading) {
      print('Предотвращена повторная отправка: _isSendingMessage=$_isSendingMessage, isLoading=${chatProvider.isLoading}');
      return;
    }
    
    final text = _textController.text;
    if (text.trim().isEmpty) {
      print('Пустое сообщение, отправка отменена');
      return;
    }
    
    setState(() {
      _isSendingMessage = true;
    });
    
    try {
      // Получаем первое предложение для заголовка
      final chatTitle = _extractFirstSentence(text);
      
      // Если это первое сообщение, создаем чат с правильным заголовком
      if (!_hasFirstMessage) {
        await _getChatsProvider().createChatWithFirstMessage(
          chatId: widget.chatId,
          firstMessage: text,
          userId: widget.myUserId,
        );
        
        setState(() {
          _hasFirstMessage = true;
        });
      } else {
        // Обновляем только последнее сообщение
        _getChatsProvider().updateLastMessage(widget.chatId, text);
      }
      
      // Сохраняем сообщение перед отправкой
      final messageToSend = text;
      
      // ПОЛНАЯ ОЧИСТКА ПОЛЯ
      _textController.clear();
      _textController.text = ''; // Двойная очистка для надежности
      
      // Принудительно обновляем состояние
      setState(() {});
      
      // Небольшая задержка перед отправкой
      await Future.delayed(Duration(milliseconds: 50));
      
      // Отправляем сообщение через провайдер
      await chatProvider.sendMessage(
        messageToSend, 
        userId: widget.myUserId, 
        chatId: widget.chatId,
      );
      
      // Возвращаем фокус с небольшой задержкой
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
      
    } catch (e) {
      print('❌ Error sending message: $e');
      
      // Показываем сообщение об ошибке пользователю
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка отправки сообщения: ${e.toString().split('\n').first}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      // ВСЕГДА сбрасываем флаг отправки
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }
}