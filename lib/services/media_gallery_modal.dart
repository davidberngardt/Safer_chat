// media_gallery_modal.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:safer_chat/theme.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/providers/font_scale_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import '../utils/platform_utils.dart'; // Добавлен импорт

class MediaGalleryModal extends StatefulWidget {
  final int chatId;
  final String baseUrl;
  final String token;

  const MediaGalleryModal({
    Key? key,
    required this.chatId,
    required this.baseUrl,
    required this.token,
  }) : super(key: key);

  @override
  State<MediaGalleryModal> createState() => _MediaGalleryModalState();
}

class _MediaGalleryModalState extends State<MediaGalleryModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  
  List<MediaItem> _photos = [];
  List<MediaItem> _videos = [];
  List<MediaItem> _audios = [];

  // Для воспроизведения аудио
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  MediaItem? _currentlyPlayingItem;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMedia();
    
    // Настройка слушателей для аудио-плеера
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });
    
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        _isPlaying = false;
        _currentlyPlayingItem = null;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadMedia() async {
    try {
      final dio = Dio();
      dio.options.headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      };

      final response = await dio.get(
        '${widget.baseUrl}/api/chats/${widget.chatId}/media',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        
        setState(() {
          _photos = (data['photos'] as List?)
              ?.map((item) => MediaItem.fromMap(item))
              .toList() ?? [];
          _videos = (data['videos'] as List?)
              ?.map((item) => MediaItem.fromMap(item))
              .toList() ?? [];
          _audios = (data['audios'] as List?)
              ?.map((item) => MediaItem.fromMap(item))
              .toList() ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки медиа: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.background,
          borderRadius: BorderRadius.circular(MessengerTheme.radiusLG),
        ),
        child: Column(
          children: [
            // Заголовок
            Container(
              padding: EdgeInsets.all(16 * fontSizeScale),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(MessengerTheme.radiusLG),
                  topRight: Radius.circular(MessengerTheme.radiusLG),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.media,
                    style: TextStyle(
                      fontSize: 20 * fontSizeScale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Вкладки
            TabBar(
              controller: _tabController,
              labelColor: MessengerTheme.lightAccent,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              indicatorColor: MessengerTheme.lightAccent,
              labelStyle: TextStyle(fontSize: 16 * fontSizeScale, fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: AppLocalizations.of(context)!.photos),
                Tab(text: AppLocalizations.of(context)!.videos),
                Tab(text: AppLocalizations.of(context)!.audio),
              ],
            ),
            
            // Контент
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPhotoTab(),
                        _buildVideoTab(),
                        _buildAudioTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoTab() {
    if (_photos.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context)!.noPhotos);
    }

    return _buildMediaGrid(_photos, MediaType.photo);
  }

  Widget _buildVideoTab() {
    if (_videos.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context)!.noVideos);
    }

    return _buildMediaGrid(_videos, MediaType.video);
  }

  Widget _buildAudioTab() {
    if (_audios.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context)!.noAudio);
    }

    return _buildAudioList(_audios);
  }

  Widget _buildEmptyState(String message) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64 * fontSizeScale,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          SizedBox(height: 16 * fontSizeScale),
          Text(
            message,
            style: TextStyle(
              fontSize: 16 * fontSizeScale,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(List<MediaItem> items, MediaType type) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final groupedByDate = _groupByDate(items);
    
    return ListView.builder(
      padding: EdgeInsets.all(16 * fontSizeScale),
      itemCount: groupedByDate.length,
      itemBuilder: (context, index) {
        final dateKey = groupedByDate.keys.elementAt(index);
        final dateItems = groupedByDate[dateKey]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок даты
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8 * fontSizeScale),
              child: Text(
                _formatDateHeader(dateKey),
                style: TextStyle(
                  fontSize: 14 * fontSizeScale,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
            
            // Сетка медиа
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8 * fontSizeScale,
                mainAxisSpacing: 8 * fontSizeScale,
              ),
              itemCount: dateItems.length,
              itemBuilder: (context, itemIndex) {
                final item = dateItems[itemIndex];
                return _buildMediaThumbnail(item, type);
              },
            ),
            
            SizedBox(height: 16 * fontSizeScale),
          ],
        );
      },
    );
  }

  Widget _buildMediaThumbnail(MediaItem item, MediaType type) {
    return GestureDetector(
      onTap: () => _openMedia(item, type),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MessengerTheme.radiusSM),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MessengerTheme.radiusSM),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                item.fileUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: Icon(
                      type == MediaType.photo ? Icons.image : Icons.videocam,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                    ),
                  );
                },
              ),
              
              if (type == MediaType.video)
                Center(
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioList(List<MediaItem> items) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final groupedByDate = _groupByDate(items);
    
    return ListView.builder(
      padding: EdgeInsets.all(16 * fontSizeScale),
      itemCount: groupedByDate.length,
      itemBuilder: (context, index) {
        final dateKey = groupedByDate.keys.elementAt(index);
        final dateItems = groupedByDate[dateKey]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок даты
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8 * fontSizeScale),
              child: Text(
                _formatDateHeader(dateKey),
                style: TextStyle(
                  fontSize: 14 * fontSizeScale,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
            
            // Список аудио
            ...dateItems.map((item) => _buildAudioItem(item)).toList(),
            
            SizedBox(height: 16 * fontSizeScale),
          ],
        );
      },
    );
  }

  Widget _buildAudioItem(MediaItem item) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final isCurrentlyPlaying = _currentlyPlayingItem?.id == item.id && _isPlaying;
    
    return Container(
      margin: EdgeInsets.only(bottom: 8 * fontSizeScale),
      padding: EdgeInsets.all(12 * fontSizeScale),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(MessengerTheme.radiusMD),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8 * fontSizeScale),
            decoration: BoxDecoration(
              color: MessengerTheme.lightAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.audiotrack,
              color: MessengerTheme.lightAccent,
              size: 24 * fontSizeScale,
            ),
          ),
          
          SizedBox(width: 12 * fontSizeScale),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName ?? 'Audio',
                  style: TextStyle(
                    fontSize: 14 * fontSizeScale,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                
                if (item.duration != null)
                  Text(
                    _formatDuration(item.duration!),
                    style: TextStyle(
                      fontSize: 12 * fontSizeScale,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
          
          IconButton(
            icon: Icon(
              isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
              color: MessengerTheme.lightAccent,
            ),
            onPressed: () => _toggleAudioPlayback(item),
          ),
        ],
      ),
    );
  }

  Map<DateTime, List<MediaItem>> _groupByDate(List<MediaItem> items) {
    final Map<DateTime, List<MediaItem>> grouped = {};
    
    for (var item in items) {
      final date = DateTime(
        item.createdAt.year,
        item.createdAt.month,
        item.createdAt.day,
      );
      
      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(item);
    }
    
    // Сортируем по дате (сначала новые)
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return Map.fromIterable(
      sortedKeys,
      key: (k) => k,
      value: (k) => grouped[k]!,
    );
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    
    if (date == today) {
      return AppLocalizations.of(context)!.today;
    } else if (date == yesterday) {
      return AppLocalizations.of(context)!.yesterday;
    } else {
      return DateFormat('dd MMMM yyyy', 'ru').format(date);
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _openMedia(MediaItem item, MediaType type) {
    if (type == MediaType.photo) {
      _showPhotoViewer(item);
    } else if (type == MediaType.video) {
      _showVideoPlayer(item);
    }
  }

  void _showPhotoViewer(MediaItem item) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(item.fileUrl),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoPlayer(MediaItem item) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: VideoPlayerWidget(videoUrl: item.fileUrl),
        ),
      ),
    );
  }

  Future<void> _toggleAudioPlayback(MediaItem item) async {
    try {
      if (_currentlyPlayingItem?.id == item.id && _isPlaying) {
        // Пауза текущего трека
        await _audioPlayer.pause();
        setState(() {
          _isPlaying = false;
        });
      } else {
        // Остановка предыдущего трека, если он играет
        if (_currentlyPlayingItem != null && _isPlaying) {
          await _audioPlayer.stop();
        }
        
        // Воспроизведение нового трека
        await _audioPlayer.play(UrlSource(item.fileUrl));
        setState(() {
          _currentlyPlayingItem = item;
          _isPlaying = true;
        });
      }
    } catch (e) {
      print('Ошибка воспроизведения аудио: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось воспроизвести аудио'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Модель для медиа-элемента
class MediaItem {
  final int id;
  final String fileUrl;
  final DateTime createdAt;
  final int? duration;
  final String? fileName;

  MediaItem({
    required this.id,
    required this.fileUrl,
    required this.createdAt,
    this.duration,
    this.fileName,
  });

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: map['id'],
      fileUrl: map['file_url'],
      createdAt: DateTime.parse(map['created_at']),
      duration: map['duration'],
      fileName: map['file_name'],
    );
  }
}

enum MediaType { photo, video, audio }

// Виджет для видео-плеера
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerWidget({Key? key, required this.videoUrl}) : super(key: key);

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _videoController;
  late ChewieController _chewieController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoController = VideoPlayerController.network(widget.videoUrl);
    await _videoController.initialize();
    
    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: false,
    );
    
    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Center(child: CircularProgressIndicator());
    }

    return Chewie(controller: _chewieController);
  }
}