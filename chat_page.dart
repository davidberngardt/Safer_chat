import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'models/message.dart';

class ChatPage extends StatefulWidget {
  final int myUserId;
  final String baseUrl;
  final String token;
  final int chatId;
  final String chatTitle;

  const ChatPage({
    Key? key,
    required this.myUserId,
    required this.baseUrl,
    required this.token,
    required this.chatId,
    required this.chatTitle,
  }) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final focusNode = FocusNode();

  bool _showScrollDownButton = false;
  bool _showEmojiPicker = false;
  late TabController _tabController;

  // Новые поля для управления прикрепленными файлами
  List<XFile> _attachedFiles = [];
  bool _hasAttachments = false;

  // Поля для управления видео
  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;
  bool _showVideoModal = false;
  String? _currentVideoUrl;

  final Map<String, List<String>> _emojiCategories = {
    '😊': [
      '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
      '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚',
      '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥸',
      '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️',
      '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡',
      '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨', '😰', '😥', '😓',
      '🤗', '🤔', '🤭', '🤫', '🤥', '😶', '😐', '😑', '😬', '🙄',
      '😯', '😦', '😧', '😮', '😲', '🥱', '😴', '🤤', '😪', '😵',
    ],
    '👋': [
      '👋', '🤚', '🖐', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞',
      '🤟', '🤘', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎',
      '👊', '✊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏',
      '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻', '👃', '🧠', '🫀',
      '🫁', '🦷', '🦴', '👀', '👁', '👅', '👄', '👶', '🧒', '👦',
      '👧', '🧑', '👱', '👨', '🧔', '👨‍🦰', '👨‍🦱', '👨‍🦳', '👨‍🦲', '👩',
      '👩‍🦰', '👩‍🦱', '👩‍🦳', '👩‍🦲', '🧓', '👴', '👵', '🙍', '🙎', '🙅',
      '🙆', '💁', '🙋', '🧏', '🙇', '🤦', '🤷', '👮', '🕵️', '💂',
      '👷', '🤴', '👸', '👳', '👲', '🧕', '🤵', '👰', '🤰', '🤱',
    ],
    '🐻': [
      '🐵', '🐒', '🦍', '🦧', '🐶', '🐕', '🦮', '🐩', '🐺', '🦊',
      '🦝', '🐱', '🐈', '🦁', '🐯', '🐅', '🐆', '🐴', '🐎', '🦄',
      '🦓', '🦌', '🐮', '🐂', '🐃', '🐄', '🐷', '🐖', '🐗', '🐽',
      '🐏', '🐑', '🐐', '🐪', '🐫', '🦙', '🦒', '🐘', '🦏', '🦛',
      '🐭', '🐁', '🐀', '🐹', '🐰', '🐇', '🐿', '🦔', '🦇', '🐻',
      '🐨', '🐼', '🦥', '🦦', '🦨', '🦘', '🦡', '🐾', '🦃', '🐔',
      '🐓', '🐣', '🐤', '🐥', '🐦', '🐧', '🕊', '🦅', '🦆', '🦢',
      '🦉', '🦩', '🦚', '🦜', '🐸', '🐊', '🐢', '🦎', '🐍', '🐲',
      '🐉', '🦕', '🦖', '🐳', '🐋', '🐬', '🦭', '🐟', '🐠', '🐡',
      '🦈', '🐙', '🐚', '🐌', '🦋', '🐛', '🐜', '🐝', '🐞', '🦗',
      '🕷', '🕸', '🦂', '🦟', '🦠', '💐', '🌸', '💮', '🏵', '🌹',
      '🥀', '🌺', '🌻', '🌼', '🌷', '🌱', '🪴', '🌲', '🌳', '🌴',
    ],
    '🍕': [
      '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
      '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑',
      '🥦', '🥬', '🥒', '🌶', '🫑', '🌽', '🥕', '🫒', '🧄', '🧅',
      '🥔', '🍠', '🥐', '🥯', '🍞', '🥖', '🥨', '🧀', '🥚', '🍳',
      '🧈', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🦴', '🌭', '🍔',
      '🍟', '🍕', '🫓', '🥪', '🥙', '🧆', '🌮', '🌯', '🫔', '🥗',
      '🥘', '🫕', '🥫', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟',
      '🦪', '🍤', '🍙', '🍚', '🍘', '🍥', '🥠', '🥮', '🍢', '🍡',
      '🍧', '🍨', '🍦', '🥧', '🧁', '🍰', '🎂', '🍮', '🍭', '🍬',
      '🍫', '🍿', '🧈', '🍩', '🍪', '🌰', '🥜', '🍯', '🥛', '🍼',
    ],
    '⚽️': [
      '⚽️', '🏀', '🏈', '⚾️', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
      '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🎿', '⛷', '🏂',
      '🪂', '🏋️', '🤼', '🤸', '⛹️', '🤾', '🏌️', '🏇', '🧘', '🏄',
      '🏊', '🤽', '🚣', '🧗', '🚵', '🚴', '🏆', '🥇', '🥈', '🥉',
      '🏅', '🎖', '🏵', '🎗', '🎫', '🎟', '🎪', '🤹', '🎭', '🩰',
      '🎨', '🎬', '🎤', '🎧', '🎼', '🎹', '🥁', '🪘', '🎷', '🎺',
      '🎸', '🪕', '🎻', '🎲', '♟', '🎯', '🎳', '🎮', '🎰', '🧩',
    ],
    '🚗': [
      '🚗', '🚕', '🚙', '🚌', '🚎', '🏎', '🚓', '🚑', '🚒', '🚐',
      '🛻', '🚚', '🚛', '🚜', '🦯', '🦽', '🦼', '🛴', '🚲', '🛵',
      '🏍', '🛺', '🚨', '🚔', '🚍', '🚘', '🚖', '🚡', '🚠', '🚟',
      '🚃', '🚋', '🚞', '🚝', '🚄', '🚅', '🚈', '🚂', '🚆', '🚇',
      '🚊', '🚉', '✈️', '🛫', '🛬', '🛩', '💺', '🛰', '🚀', '🛸',
      '🚁', '🛶', '⛵️', '🚤', '🛥', '🛳', '⛴', '🚢', '⚓️', '⛽️',
      '🚧', '🚦', '🚥', '🚏', '🗺', '🗿', '🗽', '🗼', '🏰', '🏯',
      '🏟', '🎡', '🎢', '🎠', '⛲️', '⛱', '🏖', '🏝', '🏜', '🌋',
      '⛰', '🏔', '🗻', '🏕', '🏠', '🏡', '🏘', '🏚', '🏗', '🏭',
    ],
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _tabController = TabController(
      length: _emojiCategories.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    focusNode.dispose();
    _tabController.dispose();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
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

  Future<void> _attachFile() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty) return;

    setState(() {
      _attachedFiles.addAll(files);
      _hasAttachments = true;
    });
  }

  void _removeAttachedFile(int index) {
    setState(() {
      _attachedFiles.removeAt(index);
      _hasAttachments = _attachedFiles.isNotEmpty;
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    
    // Если нет текста и нет прикрепленных файлов - ничего не делаем
    if (text.isEmpty && _attachedFiles.isEmpty) return;

    // Создаем временное сообщение
    final tempMsg = Message(
      id: const Uuid().v4().hashCode,
      userId: widget.myUserId,
      text: text.isNotEmpty ? text : 'Файл',
      createdAt: DateTime.now(),
      fileUrl: _attachedFiles.isNotEmpty ? (_attachedFiles.first.path) : null,
      typeId: _attachedFiles.isNotEmpty ? 2 : 1,
    );

    setState(() {
      _messages.add(tempMsg);
    });
    _scrollToBottom();

    try {
      // Если есть прикрепленные файлы, отправляем их вместе с текстом
      if (_attachedFiles.isNotEmpty) {
        await _sendMessageWithFiles(text, tempMsg);
      } else {
        // Если только текст
        await _sendTextOnly(text, tempMsg);
      }

    } catch (e) {
      print('Ошибка при отправке сообщения: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при отправке сообщения'),
          backgroundColor: Colors.red,
        ),
      );
    }

    // Очищаем после отправки
    setState(() {
      _controller.clear();
      _attachedFiles.clear();
      _hasAttachments = false;
      _showEmojiPicker = false;
    });
  }

  Future<void> _sendTextOnly(String text, Message tempMsg) async {
    final dio = Dio();
    
    dio.options.headers = {
      'Authorization': 'Bearer ${widget.token}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final response = await dio.post(
      '${widget.baseUrl}/api/send-message',
      data: {
        'text': text,
        'chat_id': widget.chatId,
      },
    );

    if (response.statusCode == 200) {
      final data = response.data;
      setState(() {
        final index = _messages.indexOf(tempMsg);
        if (index != -1) {
          _messages[index] = Message(
            id: data['message_id'] ?? data['id'] ?? tempMsg.id,
            userId: widget.myUserId,
            text: text,
            createdAt: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
            typeId: 1,
          );
        }
      });
    }
  }

  Future<void> _sendMessageWithFiles(String text, Message tempMsg) async {
    final dio = Dio();
    dio.options.headers['Authorization'] = 'Bearer ${widget.token}';

    // Отправляем файлы по одному, но создаем одно сообщение
    if (_attachedFiles.isNotEmpty) {
      final firstFile = _attachedFiles.first;
      
      FormData formData;
      if (kIsWeb) {
        final bytes = await firstFile.readAsBytes();
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: firstFile.name),
          'chat_id': widget.chatId,
          'text': text, // Добавляем текст к файлу
        });
      } else {
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(firstFile.path, filename: firstFile.name),
          'chat_id': widget.chatId,
          'text': text, // Добавляем текст к файлу
        });
      }

      final response = await dio.post('${widget.baseUrl}/api/upload', data: formData);

      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          final index = _messages.indexOf(tempMsg);
          if (index != -1) {
            _messages[index] = Message(
              id: data['message_id'] ?? tempMsg.id,
              userId: widget.myUserId,
              text: text.isNotEmpty ? text : (data['original_name'] ?? firstFile.name),
              createdAt: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
              fileUrl: data['file_url'],
              typeId: 2,
            );
          }
        });
      }
    }

    // Если есть дополнительные файлы, отправляем их отдельно как новые сообщения
    if (_attachedFiles.length > 1) {
      for (int i = 1; i < _attachedFiles.length; i++) {
        await _sendSingleFile(_attachedFiles[i]);
      }
    }
  }

  Future<void> _sendSingleFile(XFile file) async {
    final tempMsg = Message(
      id: const Uuid().v4().hashCode,
      userId: widget.myUserId,
      text: file.name,
      createdAt: DateTime.now(),
      fileUrl: kIsWeb ? file.path : file.path,
      typeId: 2,
    );

    setState(() {
      _messages.add(tempMsg);
    });

    try {
      final dio = Dio();
      dio.options.headers['Authorization'] = 'Bearer ${widget.token}';

      FormData formData;
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: file.name),
          'chat_id': widget.chatId,
        });
      } else {
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path, filename: file.name),
          'chat_id': widget.chatId,
        });
      }

      final response = await dio.post('${widget.baseUrl}/api/upload', data: formData);

      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          final index = _messages.indexOf(tempMsg);
          if (index != -1) {
            _messages[index] = Message(
              id: data['message_id'] ?? tempMsg.id,
              userId: widget.myUserId,
              text: data['original_name'] ?? file.name,
              createdAt: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
              fileUrl: data['file_url'],
              typeId: 2,
            );
          }
        });
      }
    } catch (e) {
      print('Ошибка при отправке файла: $e');
    }
  }

  // Остальные методы остаются без изменений...
  Widget _buildAttachedFiles() {
    if (!_hasAttachments) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Прикрепленные файлы:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: _attachedFiles.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;
              return Chip(
                label: Text(
                  file.name.length > 15 
                    ? '${file.name.substring(0, 15)}...' 
                    : file.name,
                  style: const TextStyle(fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeAttachedFile(index),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return Container(
      height: 250,
      color: Colors.grey[50],
      child: Column(
        children: [
          Container(
            height: 40,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: const Color(0xFFFF9800),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFFF9800),
              tabs: _emojiCategories.keys.map((emoji) {
                return Tab(text: emoji);
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _emojiCategories.values.map((emojis) {
                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: emojis.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _addEmoji(emojis[index]),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            emojis[index],
                            style: const TextStyle(fontSize: 18),
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

  // Вспомогательный метод для плейсхолдера
  Widget _buildFilePlaceholder(IconData icon, String text) {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.grey),
            SizedBox(height: 4),
            Text(
              text,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Метод для открытия видео в модальном окне
  Future<void> _openVideo(String videoUrl) async {
    try {
      setState(() {
        _currentVideoUrl = videoUrl;
        _showVideoModal = true;
      });

      // Инициализируем видеоплеер
      _videoPlayerController = VideoPlayerController.network(videoUrl);
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Color(0xFFFF9800),
          handleColor: Color(0xFFFF9800),
          backgroundColor: Colors.grey,
          bufferedColor: Colors.grey[300]!,
        ),
        placeholder: Container(
          color: Colors.grey[900],
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFFFF9800)),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Container(
            color: Colors.grey[900],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.white, size: 50),
                  SizedBox(height: 16),
                  Text(
                    'Ошибка загрузки видео',
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );

      setState(() {});
    } catch (e) {
      print('Ошибка при загрузке видео: $e');
      _showVideoErrorDialog(videoUrl);
      _closeVideoModal();
    }
  }

  // Закрытие модального окна с видео
  void _closeVideoModal() {
    setState(() {
      _showVideoModal = false;
      _currentVideoUrl = null;
    });
    _chewieController?.dispose();
    _chewieController = null;
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  // Диалог для случая ошибки
  void _showVideoErrorDialog(String videoUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Ошибка'),
          ],
        ),
        content: Text('Не удалось загрузить видео. Попробуйте открыть его в браузере.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Закрыть'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _copyToClipboard(videoUrl);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ссылка скопирована в буфер обмена'),
                ),
              );
            },
            child: Text('Копировать ссылку'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF9800),
            ),
          ),
        ],
      ),
    );
  }

  // Метод для копирования в буфер обмена
  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  // Метод для открытия изображения
  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.black,
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Expanded(
                child: InteractiveViewer(
                  child: kIsWeb
                      ? Image.network(imageUrl, fit: BoxFit.contain)
                      : Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Виджет модального окна с видео
  Widget _buildVideoModal() {
    if (!_showVideoModal || _chewieController == null) return SizedBox.shrink();

    return Stack(
      children: [
        // Затемненный фон
        GestureDetector(
          onTap: _closeVideoModal,
          child: Container(
            color: Colors.black.withOpacity(0.8),
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        // Контент модального окна
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                // Заголовок
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.videocam_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Видео',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: _closeVideoModal,
                      ),
                    ],
                  ),
                ),
                // Видеоплеер
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: Chewie(controller: _chewieController!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.chatTitle,
          style: const TextStyle(color: Colors.white),
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
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg.userId == widget.myUserId;
                      final timeString =
                          "${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}";

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFFFFB74D) : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              // Отображение файлов (изображений или видео)
                              if (msg.fileUrl != null) ...[
                                if (msg.isImage)
                                  GestureDetector(
                                    onTap: () => _showImageDialog(context, msg.fileUrl!),
                                    child: Container(
                                      width: 200,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.grey[300],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: kIsWeb
                                            ? Image.network(
                                                msg.fileUrl!,
                                                width: 200,
                                                height: 150,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return _buildFilePlaceholder(
                                                    Icons.broken_image,
                                                    'Ошибка загрузки',
                                                  );
                                                },
                                              )
                                            : Image.network(
                                                msg.fileUrl!,
                                                width: 200,
                                                height: 150,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return _buildFilePlaceholder(
                                                    Icons.broken_image,
                                                    'Ошибка загрузки',
                                                  );
                                                },
                                              ),
                                      ),
                                    ),
                                  )
                                else if (msg.isVideo)
                                  GestureDetector(
                                    onTap: () => _openVideo(msg.fileUrl!),
                                    child: Container(
                                      width: 200,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey[400]!),
                                      ),
                                      child: Stack(
                                        children: [
                                          // Можно добавить превью видео если нужно
                                          // Пока просто фон
                                          Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              color: Colors.black.withOpacity(0.3),
                                            ),
                                          ),
                                          // Иконка воспроизведения
                                          Center(
                                            child: Container(
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.9),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.play_arrow_rounded,
                                                size: 30,
                                                color: const Color(0xFFFF9800),
                                              ),
                                            ),
                                          ),
                                          // Информация о видео внизу
                                          Positioned(
                                            bottom: 8,
                                            left: 8,
                                            right: 8,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.videocam_rounded,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    'Видео',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  GestureDetector(
                                    onTap: () {
                                      _copyToClipboard(msg.fileUrl!);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Ссылка на файл скопирована'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 200,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey[300]!),
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.insert_drive_file_rounded,
                                            size: 24,
                                            color: const Color(0xFFFF9800),
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Файл',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[700],
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  msg.text.length > 20 
                                                    ? '${msg.text.substring(0, 20)}...' 
                                                    : msg.text,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey[600],
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                              ],
                              
                              // Текст сообщения (показываем всегда, если есть текст)
                              if (msg.text.isNotEmpty && !msg.text.contains('[загрузка файла...]'))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    msg.text,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: isMe ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                              
                              // Время
                              Text(
                                timeString,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isMe ? Colors.white70 : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_showEmojiPicker) _buildEmojiPicker(),
                _buildAttachedFiles(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.emoji_emotions_outlined,
                          color: Color(0xFFFF9800),
                        ),
                        onPressed: _toggleEmojiPicker,
                      ),
                      IconButton(
                        icon: const Icon(Icons.attach_file, color: Color(0xFFFF9800)),
                        onPressed: _attachFile,
                      ),
                      Expanded(
                        child: RawKeyboardListener(
                          focusNode: FocusNode(),
                          onKey: (event) {
                            if (event.isKeyPressed(LogicalKeyboardKey.enter)) {
                              if (event.isShiftPressed) {
                                final newText = "${_controller.text}\r";
                                _controller.text = newText;
                                _controller.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _controller.text.length));
                              } else {
                                _sendMessage();
                              }
                            }
                          },
                          child: TextField(
                            controller: _controller,
                            focusNode: focusNode,
                            maxLines: null,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: _hasAttachments 
                                ? 'Введите сообщение с файлами...' 
                                : 'Введите сообщение...',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.send_rounded, 
                          color: _hasAttachments || _controller.text.trim().isNotEmpty 
                            ? const Color(0xFFFF9800) 
                            : Colors.grey,
                        ),
                        onPressed: (_hasAttachments || _controller.text.trim().isNotEmpty) 
                          ? _sendMessage 
                          : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Модальное окно с видео поверх всего
          if (_showVideoModal) _buildVideoModal(),
        ],
      ),
      floatingActionButton: _showScrollDownButton
          ? FloatingActionButton.small(
              onPressed: _scrollToBottom,
              backgroundColor: const Color(0xFFFF9800),
              child: const Icon(Icons.arrow_downward, color: Colors.white),
            )
          : null,
    );
  }
}