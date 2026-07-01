import 'dart:async';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'widgets/adaptive_logo.dart';
// цвета заданы явно, чтобы не связывать сплэш с AuthPage
// ✨ ФАЙЛ ПОЛНОСТЬЮ ЗАКОММЕНТИРОВАН: video_player и весь video функционал отключен
// ✨ ИСПОЛЬЗУЕТСЯ ТОЛЬКО ДЛЯ СОХРАНЕНИЯ КОДА, НО НЕ АКТИВЕН
// import 'package:video_player/video_player.dart';

class SplashVideoScreen extends StatefulWidget {
  final VoidCallback onVideoComplete;
  final VoidCallback? onError;
  // ✨ ЗАКОММЕНТИРОВАНО: showVideo больше не используется
  // final bool showVideo;

  const SplashVideoScreen({
    Key? key,
    required this.onVideoComplete,
    this.onError,
    // ✨ ЗАКОММЕНТИРОВАНО: showVideo больше не используется
    // this.showVideo = true,
  }) : super(key: key);

  @override
  State<SplashVideoScreen> createState() => _SplashVideoScreenState();
}

class _SplashVideoScreenState extends State<SplashVideoScreen> {
  // ✨ ЗАКОММЕНТИРОВАНО: video_player временно отключен
  // late VideoPlayerController _controller;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  Timer? _timeoutTimer;

  static const int _timeoutSeconds = 3; // Уменьшено с 5 до 3 секунд

  @override
  void initState() {
    super.initState();

    // ✨ ЗАКОММЕНТИРОВАНО: Весь функционал видео отключен, всегда показываем только логотип
    // if (!widget.showVideo) {
    //   _startLogoTransition();
    //   return;
    // }

    // Всегда показываем только простой сплэш с логотипом (видео полностью отключено)
    _startLogoTransition();
  }

  void _startLogoTransition() {
    setState(() {
      _isVideoInitialized = true;
    });

    // Показываем логотип минимум на _timeoutSeconds, затем переходим
    _timeoutTimer = Timer(const Duration(seconds: _timeoutSeconds), () {
      if (mounted) {
        _completeSplash();
      }
    });
  }

  // ✨ ЗАКОММЕНТИРОВАНО: инициализация видео
  /*
  void _initializeVideo() {
    try {
      _controller = VideoPlayerController.asset('assets/videos/splash_video.mp4');

      _controller.initialize().then((_) {
        if (mounted) {
          setState(() {
            _isVideoInitialized = true;
          });

          _controller.play();

          _timeoutTimer = Timer(const Duration(seconds: _timeoutSeconds), () {
            if (mounted && !_hasError) {
              print('⚠️ Video timeout - forcing navigation');
              _completeSplash();
            }
          });

          _controller.addListener(() {
            if (mounted && _controller.value.position >= _controller.value.duration) {
              _completeSplash();
            }
          });
        }
      }).catchError((error) {
        print('❌ Error initializing video: $error');
        _handleError();
      });
    } catch (e) {
      print('❌ Exception initializing video: $e');
      _handleError();
    }
  }
  */

  void _handleError() {
    if (mounted) {
      setState(() {
        _hasError = true;
      });

      widget.onError?.call();

      Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          _completeSplash();
        }
      });
    }
  }

  void _completeSplash() {
    _timeoutTimer?.cancel();
    // ✨ ЗАКОММЕНТИРОВАНО: очистка видео контроллера
    // _controller.dispose();
    widget.onVideoComplete();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    // ✨ ЗАКОММЕНТИРОВАНО: очистка видео контроллера
    // _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✨ ЗАКОММЕНТИРОВАНО: Весь функционал видео отключен
    // Всегда показываем только простой сплэш с логотипом и лоадером
    return _buildSimpleSplash();
  }

  // ✨ ЗАКОММЕНТИРОВАНО: Метод больше не используется, только для сохранения кода
  Widget _buildLoadingIndicator() {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text(
              'Загрузка...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleSplash() {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF3),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AdaptiveLogo(
              backgroundColor: Color(0xFFFFFCF3),
              size: LogoSize.large,
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Color(0xFF4CAF50)),
          ],
        ),
      ),
    );
  }
}