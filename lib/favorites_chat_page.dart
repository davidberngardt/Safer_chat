// favorites_chat_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/favorite_message.dart';
import '../providers/favorites_provider.dart';
import '../providers/font_scale_provider.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/emoji_data.dart';
import '../services/voice_service.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import '../utils/platform_utils.dart';

class FavoritesChatPage extends StatefulWidget {
  final int myUserId;

  const FavoritesChatPage({
    Key? key,
    required this.myUserId,
  }) : super(key: key);

  @override
  _FavoritesChatPageState createState() => _FavoritesChatPageState();
}

class _FavoritesChatPageState extends State<FavoritesChatPage> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final focusNode = FocusNode();
  bool _showScrollDownButton = false;
  bool _showSearch = false;
  bool _showEmojiPicker = false;
  late TabController _tabController;
  
  // Сервис голосовых сообщений
  late VoiceService _voiceService;
  bool _audioAvailable = false;
  bool _audioInitialized = false;
  bool _microphonePermissionGranted = false;
  
  // Состояние воспроизведения аудио
  bool _isPlaying = false;
  int? _playingMessageId;
  
  // Прикрепленные файлы
  List<XFile> _attachedFiles = [];
  bool _hasAttachments = false;
  
  // Поиск
  List<FavoriteMessage> _searchResults = [];
  int _currentSearchIndex = -1;
  
  // Флаг для Shift
  bool _shiftPressed = false;

  @override
  void initState() {
    super.initState();
    
    // Инициализация сервиса голосовых сообщений
    _voiceService = VoiceService();
    
    _scrollController.addListener(_scrollListener);
    _tabController = TabController(
      length: EmojiData.categories.length,
      vsync: this,
    );
    
    _initializeServices();
    
    // Слушаем изменения текста
    _controller.addListener(_updateSendButtonState);
    
    // Настраиваем слушатели состояния воспроизведения
    _setupVoiceServiceListeners();
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
      });
    };
  }

  void _updateSendButtonState() {
    setState(() {});
  }

  Future<void> _initializeServices() async {
    try {
      await _voiceService.initialize();
      
      // Проверяем разрешение микрофона
      _microphonePermissionGranted = await _voiceService.checkMicrophonePermission();
      
      _audioAvailable = true;
      _audioInitialized = true;
      
    } catch (e) {
      _audioInitialized = true;
      _audioAvailable = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateSendButtonState);
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    focusNode.dispose();
    _tabController.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.offset < _scrollController.position.maxScrollExtent - 300) {
      if (!_showScrollDownButton) setState(() => _showScrollDownButton = true);
    } else {
      if (_showScrollDownButton) setState(() => _showScrollDownButton = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ========== ПОИСК ==========
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

    final favoritesProvider = Provider.of<FavoritesProvider>(context, listen: false);
    final results = favoritesProvider.favoriteMessages.where((favMessage) {
      return favMessage.text.toLowerCase().contains(query.toLowerCase()) ||
             favMessage.chatTitle.toLowerCase().contains(query.toLowerCase());
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

    _scrollToSearchResult(_searchResults[_currentSearchIndex]);
  }

  void _scrollToSearchResult(FavoriteMessage favMessage) {
    final favoritesProvider = Provider.of<FavoritesProvider>(context, listen: false);
    final index = favoritesProvider.favoriteMessages.indexOf(favMessage);
    if (index != -1 && _scrollController.hasClients) {
      _scrollController.animateTo(
        index * 100.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildSearchBar(double fontSizeScale) {
    if (!_showSearch) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 16 * fontSizeScale,
        vertical: 8 * fontSizeScale,
      ),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: 16 * fontSizeScale),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.searchInFavorites,
                hintStyle: TextStyle(fontSize: 16 * fontSizeScale),
                border: InputBorder.none,
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 24 * fontSizeScale,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
              ),
              onChanged: _performSearch,
              onSubmitted: (query) {
                if (_searchResults.isNotEmpty) {
                  _navigateToSearchResult(0);
                }
              },
            ),
          ),
          if (_searchResults.isNotEmpty) ...[
            Text(
              '${_currentSearchIndex + 1}/${_searchResults.length}',
              style: TextStyle(
                fontSize: 14 * fontSizeScale,
                color: Colors.grey,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.arrow_upward,
                size: 24 * fontSizeScale,
              ),
              onPressed: () => _navigateToSearchResult(-1),
            ),
            IconButton(
              icon: Icon(
                Icons.arrow_downward,
                size: 24 * fontSizeScale,
              ),
              onPressed: () => _navigateToSearchResult(1),
            ),
          ],
          IconButton(
            icon: Icon(
              Icons.close,
              size: 24 * fontSizeScale,
            ),
            onPressed: _toggleSearch,
          ),
        ],
      ),
    );
  }

  // ========== ВИДЖЕТЫ ДЛЯ СООБЩЕНИЙ ==========
  Widget _buildMessageItem(FavoriteMessage favMessage, double fontSizeScale, bool isSearchResult, bool isCurrentSearchResult) {
    final isMe = favMessage.originalUserId == widget.myUserId;
    
    return GestureDetector(
      onLongPress: () => _showMessageMenu(favMessage, fontSizeScale),
      child: Container(
        decoration: BoxDecoration(
          color: isCurrentSearchResult 
              ? Colors.yellow.withOpacity(0.3)
              : isSearchResult
                  ? Colors.yellow.withOpacity(0.1)
                  : Colors.transparent,
        ),
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: 10 * fontSizeScale,
            vertical: 6 * fontSizeScale,
          ),
          padding: EdgeInsets.all(10 * fontSizeScale),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFFFFB74D) : Colors.grey[200],
            borderRadius: BorderRadius.circular(12 * fontSizeScale),
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Заголовок чата
              Container(
                margin: EdgeInsets.only(bottom: 6 * fontSizeScale),
                padding: EdgeInsets.symmetric(
                  horizontal: 8 * fontSizeScale,
                  vertical: 4 * fontSizeScale,
                ),
                decoration: BoxDecoration(
                  color: isMe ? Colors.white.withOpacity(0.2) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(8 * fontSizeScale),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chat,
                      size: 14 * fontSizeScale,
                      color: isMe ? Colors.white70 : Colors.grey[600],
                    ),
                    SizedBox(width: 4 * fontSizeScale),
                    Text(
                      favMessage.chatTitle,
                      style: TextStyle(
                        fontSize: 12 * fontSizeScale,
                        color: isMe ? Colors.white70 : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Текст сообщения
              if (favMessage.text.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: 4 * fontSizeScale),
                  child: Text(
                    favMessage.text,
                    style: TextStyle(
                      fontSize: 16 * fontSizeScale,
                      color: isMe ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              
              // Информация о времени
              Row(
                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Text(
                    '${favMessage.createdAt.hour.toString().padLeft(2, '0')}:${favMessage.createdAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 11 * fontSizeScale,
                      color: isMe ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                  SizedBox(width: 8 * fontSizeScale),
                  Text(
                    '${AppLocalizations.of(context)!.saved}: ${favMessage.savedAt.day.toString().padLeft(2, '0')}.${favMessage.savedAt.month.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10 * fontSizeScale,
                      color: isMe ? Colors.white60 : Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== ПАНЕЛЬ ВВОДА ==========
  Widget _buildRecordingControls(double fontSizeScale) {
    final recordingState = _voiceService.recordingState;
    final isRecording = recordingState == RecordingState.recording;
    final isStopped = recordingState == RecordingState.stopped;
    final recordingSeconds = _voiceService.recordingSeconds;

    if (isRecording || isStopped) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * fontSizeScale,
              vertical: 8 * fontSizeScale,
            ),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16 * fontSizeScale),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fiber_manual_record,
                  color: Colors.red,
                  size: 16 * fontSizeScale,
                ),
                SizedBox(width: 8 * fontSizeScale),
                Text(
                  _formatShortDuration(recordingSeconds),
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14 * fontSizeScale,
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
            color: Color(0xFFFF9800),
            size: 28 * fontSizeScale,
          ),
          onPressed: _toggleEmojiPicker,
        ),
        IconButton(
          icon: Icon(
            Icons.attach_file,
            color: Color(0xFFFF9800),
            size: 28 * fontSizeScale,
          ),
          onPressed: _attachFile,
        ),
      ],
    );
  }

  Future<void> _attachFile() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files.isEmpty) return;

      setState(() {
        _attachedFiles.addAll(files);
        _hasAttachments = true;
      });
      
      focusNode.requestFocus();
      
    } catch (e) {
      print('Ошибка при выборе файлов: $e');
    }
  }

  void _removeAttachedFile(int index, double fontSizeScale) {
    setState(() {
      _attachedFiles.removeAt(index);
      _hasAttachments = _attachedFiles.isNotEmpty;
    });
  }

  Widget _buildRightButtons(double fontSizeScale) {
    final recordingState = _voiceService.recordingState;
    final isRecording = recordingState == RecordingState.recording;
    final isStopped = recordingState == RecordingState.stopped;
    
    final isActive = _controller.text.trim().isNotEmpty || 
                     _attachedFiles.isNotEmpty ||
                     isStopped;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isRecording || isStopped)
          IconButton(
            icon: Icon(
              Icons.delete,
              color: Colors.red,
              size: 28 * fontSizeScale,
            ),
            onPressed: () async {
              await _voiceService.deleteRecording();
              focusNode.requestFocus();
            },
          ),
        
        SizedBox(width: (isRecording || isStopped ? 4 : 0) * fontSizeScale),
        
        if (!isRecording && !isStopped)
          IconButton(
            icon: Icon(
              Icons.mic,
              color: _audioAvailable && _audioInitialized && _microphonePermissionGranted
                  ? Color(0xFFFF9800) 
                  : Colors.grey,
              size: 28 * fontSizeScale,
            ),
            onPressed: _audioAvailable && _audioInitialized && _microphonePermissionGranted
                ? _startRecording 
                : null,
          ),
        
        SizedBox(width: 4 * fontSizeScale),
        
        MouseRegion(
          cursor: isActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: IconButton(
            icon: Icon(
              Icons.send,
              color: isActive ? Color(0xFFFF9800) : Colors.grey[400],
              size: 28 * fontSizeScale,
            ),
            onPressed: isActive ? () async {
              await _sendMessage();
            } : null,
          ),
        ),
      ],
    );
  }

  Future<void> _startRecording() async {
    if (!_audioInitialized) {
      return;
    }
    
    if (!_microphonePermissionGranted) {
      return;
    }
    
    try {
      await _voiceService.startRecording();
    } catch (e) {
      print('Ошибка начала записи: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    
    // Проверяем наличие голосового сообщения для отправки
    final hasVoiceMessage = await _voiceService.hasVoiceMessage;
    if (hasVoiceMessage) {
      // В избранном голосовые сообщения не отправляем
      await _voiceService.deleteRecording();
      return;
    }

    // Если только текст
    if (text.isNotEmpty) {
      // В избранном сообщения не отправляем, только сохраняем локально
      print('Сообщение для избранного: $text');
    }

    _clearInputs();
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

  // ========== EMOJI ==========
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

  Widget _buildEmojiPicker(double fontSizeScale) {
    return Container(
      height: 250 * fontSizeScale,
      color: Colors.grey[50],
      child: Column(
        children: [
          Container(
            height: 40 * fontSizeScale,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: const Color(0xFFFF9800),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFFF9800),
              labelStyle: TextStyle(fontSize: 14 * fontSizeScale),
              unselectedLabelStyle: TextStyle(fontSize: 14 * fontSizeScale),
              tabs: EmojiData.categories.keys.map((emoji) {
                return Tab(text: emoji);
              }).toList(),
            ),
          ),
          Divider(height: 1 * fontSizeScale),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: EmojiData.categories.values.map((emojis) {
                return GridView.builder(
                  padding: EdgeInsets.all(8 * fontSizeScale),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    crossAxisSpacing: 4 * fontSizeScale,
                    mainAxisSpacing: 4 * fontSizeScale,
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

  Widget _buildAttachedFiles(double fontSizeScale) {
    if (!_hasAttachments) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(8 * fontSizeScale),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.attachedFiles,
            style: TextStyle(
              fontSize: 12 * fontSizeScale,
              color: Colors.grey,
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
                deleteIcon: Icon(
                  Icons.close,
                  size: 16 * fontSizeScale,
                ),
                onDeleted: () => _removeAttachedFile(index, fontSizeScale),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ========== МЕНЮ СООБЩЕНИЙ ==========
  void _showMessageMenu(FavoriteMessage favMessage, double fontSizeScale) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20 * fontSizeScale),
            topRight: Radius.circular(20 * fontSizeScale),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.delete,
                  color: Colors.red,
                  size: 24 * fontSizeScale,
                ),
                title: Text(
                  AppLocalizations.of(context)!.deleteFromFavorites,
                  style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteFromFavorites(favMessage, fontSizeScale);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.copy,
                  color: Color(0xFFFF9800),
                  size: 24 * fontSizeScale,
                ),
                title: Text(
                  AppLocalizations.of(context)!.copyText,
                  style: TextStyle(fontSize: 16 * fontSizeScale),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(favMessage.text);
                },
              ),
              SizedBox(height: 20 * fontSizeScale),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteFromFavorites(FavoriteMessage favMessage, double fontSizeScale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.deleteFromFavoritesQuestion,
          style: TextStyle(fontSize: 20 * fontSizeScale),
        ),
        content: Text(
          AppLocalizations.of(context)!.deleteFromFavoritesDescription,
          style: TextStyle(fontSize: 16 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: Colors.grey[600],
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Provider.of<FavoritesProvider>(context, listen: false)
                  .removeFavoriteMessage(favMessage.id);
              Navigator.pop(context);
            },
            child: Text(
              AppLocalizations.of(context)!.delete,
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await PlatformUtils.copyToClipboard(text);
  }

  String _formatShortDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildEmptyState(double fontSizeScale) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.0 * fontSizeScale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_border_rounded,
              size: 80 * fontSizeScale,
              color: Colors.grey[400],
            ),
            SizedBox(height: 24 * fontSizeScale),
            Text(
              AppLocalizations.of(context)!.noFavoriteMessages,
              style: TextStyle(
                fontSize: 22 * fontSizeScale,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 12 * fontSizeScale),
            Container(
              constraints: BoxConstraints(maxWidth: 300 * fontSizeScale),
              child: Text(
                AppLocalizations.of(context)!.saveImportantMessages,
                style: TextStyle(
                  fontSize: 16 * fontSizeScale,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final favorites = Provider.of<FavoritesProvider>(context).favoriteMessages;
    final displayList = _showSearch && _searchResults.isNotEmpty ? _searchResults : favorites;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.favorites,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22 * fontSizeScale,
          ),
        ),
        backgroundColor: const Color(0xFFFFB74D),
        elevation: 0,
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
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              Icons.search,
              color: Colors.white,
              size: 24 * fontSizeScale,
            ),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(fontSizeScale),
            Expanded(
              child: displayList.isEmpty
                  ? _buildEmptyState(fontSizeScale)
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: displayList.length,
                      itemBuilder: (context, index) {
                        final favMessage = displayList[index];
                        final isSearchResult = _searchResults.contains(favMessage);
                        final isCurrentSearchResult = _searchResults.isNotEmpty && 
                            _currentSearchIndex >= 0 && 
                            _searchResults[_currentSearchIndex] == favMessage;
                        
                        return _buildMessageItem(
                          favMessage, 
                          fontSizeScale, 
                          isSearchResult, 
                          isCurrentSearchResult
                        );
                      },
                    ),
            ),
            if (_showEmojiPicker) _buildEmojiPicker(fontSizeScale),
            _buildAttachedFiles(fontSizeScale),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 8 * fontSizeScale,
                vertical: 6 * fontSizeScale,
              ),
              color: Colors.grey[100],
              child: Row(
                children: [
                  // Левая часть - кнопки
                  _buildRecordingControls(fontSizeScale),
                  
                  // Центральная часть - поле ввода
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 8 * fontSizeScale),
                      child: RawKeyboardListener(
                        focusNode: FocusNode(),
                        onKey: (RawKeyEvent event) {
                          // Отслеживаем нажатие Shift
                          if (event is RawKeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                                event.logicalKey == LogicalKeyboardKey.shiftRight) {
                              _shiftPressed = true;
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
                          style: TextStyle(fontSize: 16 * fontSizeScale),
                          decoration: InputDecoration(
                            hintText: _hasAttachments 
                              ? AppLocalizations.of(context)!.enterMessageWithFiles
                              : AppLocalizations.of(context)!.enterMessage,
                            hintStyle: TextStyle(fontSize: 16 * fontSizeScale),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12 * fontSizeScale,
                              vertical: 12 * fontSizeScale,
                            ),
                          ),
                          onSubmitted: (text) {
                            // Enter отправляет сообщение только если не нажат Shift
                            if (!_shiftPressed) {
                              _sendMessage();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  
                  // Правая часть - кнопки
                  _buildRightButtons(fontSizeScale),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _showScrollDownButton
          ? FloatingActionButton.small(
              onPressed: _scrollToBottom,
              backgroundColor: const Color(0xFFFF9800),
              child: Icon(
                Icons.arrow_downward,
                color: Colors.white,
                size: 24 * fontSizeScale,
              ),
            )
          : null,
    );
  }
}