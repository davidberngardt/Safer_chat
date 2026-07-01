import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/services/auth_service.dart';
import 'package:safer_chat/auth_page.dart';
import 'package:safer_chat/home_page.dart';
import 'package:safer_chat/providers/chat_provider.dart';
import 'package:safer_chat/services/ollama_service.dart';
import 'providers/font_scale_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/language_provider.dart';
import 'providers/blocked_users_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service_v2.dart';
import 'services/connection_quality_service.dart';
import 'services/websocket_service.dart';
import 'providers/optimized_chat_provider.dart';
import 'services/api_service.dart';
// ✨ ЗАКОММЕНТИРОВАНО: splash_video_screen больше не используется
// import 'splash_video_screen.dart';
import 'widgets/adaptive_logo.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
    print('✅ .env файл загружен');
  } catch (e) {
    print('⚠️ .env файл не найден, используем значения по умолчанию');
  }

  runApp(const SaferChatApp());
}

class SaferChatApp extends StatefulWidget {
  const SaferChatApp({Key? key}) : super(key: key);

  @override
  State<SaferChatApp> createState() => _SaferChatAppState();
}

class _SaferChatAppState extends State<SaferChatApp>
    with WidgetsBindingObserver {
  late Future<void> _initializationFuture;
  final NotificationService _notificationService = NotificationService();
  final ConnectionQualityService _connectionQuality =
      ConnectionQualityService();
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializationFuture = _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationService.dispose();
    _connectionQuality.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 App resumed');
        _isAppActive = true;
        _notificationService.setAppVisibility(true);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        print('📱 App paused');
        _isAppActive = false;
        _notificationService.setAppVisibility(false);
        break;
      case AppLifecycleState.detached:
        print('📱 App detached');
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _initializeApp() async {
    try {
      await _connectionQuality.initialize();
      print('✅ ConnectionQualityService initialized');

      final languageProvider = LanguageProvider();
      await languageProvider.initialize();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('profile_name');
      await prefs.remove('profile_nickname');

      print('✅ App initialization complete');
    } catch (e) {
      print('❌ App initialization error: $e');
    }
    return;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Не рисуем дополнительный MaterialApp-сплэш — основной сплэш в AuthPageWrapper
          return const SizedBox.shrink();
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Text('Ошибка инициализации: ${snapshot.error}'),
              ),
            ),
          );
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            ChangeNotifierProvider<LanguageProvider>(
                create: (_) => LanguageProvider()),
            ChangeNotifierProvider<FontScaleProvider>(
                create: (_) => FontScaleProvider()),
            ChangeNotifierProvider<FavoritesProvider>(
                create: (_) => FavoritesProvider()),
            ChangeNotifierProvider<BlockedUsersProvider>(
                create: (_) => BlockedUsersProvider()),
            ChangeNotifierProvider<ThemeProvider>(
                create: (_) => ThemeProvider()),
            ChangeNotifierProvider<ProfileProvider>(
              create: (_) => ProfileProvider(
                apiService: ApiService(
                  baseUrl: dotenv.env['API_URL'] ?? 'http://localhost:3004',
                  token: '',
                  connectionQuality: _connectionQuality,
                ),
              ),
            ),
            ChangeNotifierProvider<ChatProvider>(
              create: (context) => ChatProvider(
                ollamaService: OllamaService(),
              ),
            ),
            ChangeNotifierProvider<ConnectionQualityService>.value(
                value: _connectionQuality),
            Provider<NotificationService>.value(value: _notificationService),
          ],
          child: const _AppContent(),
        );
      },
    );
  }
}

class _AppContent extends StatefulWidget {
  const _AppContent({Key? key}) : super(key: key);

  @override
  State<_AppContent> createState() => _AppContentState();
}

class _AppContentState extends State<_AppContent> {
  late LanguageProvider _languageProvider;
  late ConnectionQualityService _connectionQuality;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      _languageProvider.addListener(_onLanguageChanged);

      _connectionQuality =
          Provider.of<ConnectionQualityService>(context, listen: false);
      _connectionQuality.qualityStream.listen((quality) {
        print('📶 Connection quality changed to: $quality');
        if (mounted) {
          _showQualityBannerIfNeeded(quality);
        }
      });
    });
  }

  void _showQualityBannerIfNeeded(ConnectionQuality quality) {
    if (quality == ConnectionQuality.poor ||
        quality == ConnectionQuality.offline) {
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text(
            quality == ConnectionQuality.offline
                ? 'Нет подключения к интернету'
                : 'Медленное соединение',
            style: const TextStyle(color: Colors.white),
          ),
          leading: Icon(
            quality == ConnectionQuality.offline ? Icons.wifi_off : Icons.speed,
            color: Colors.white,
          ),
          backgroundColor:
              quality == ConnectionQuality.offline ? Colors.red : Colors.orange,
          actions: [
            TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  void _onLanguageChanged() {
    print('_AppContentState: язык изменен, перестраиваем MaterialApp');
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _languageProvider.removeListener(_onLanguageChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final currentLocale = languageProvider.currentLocale;
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      key: ValueKey('material_app_${currentLocale.languageCode}'),
      debugShowCheckedModeBanner: false,
      title: 'Safer Chat',
      theme: themeProvider.currentTheme.copyWith(
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(color: Colors.transparent),
          textStyle: const TextStyle(fontSize: 0, color: Colors.transparent),
        ),
      ),
      darkTheme: themeProvider.isDarkMode
          ? themeProvider.currentTheme.copyWith(
              tooltipTheme: TooltipThemeData(
                decoration: BoxDecoration(color: Colors.transparent),
                textStyle:
                    const TextStyle(fontSize: 0, color: Colors.transparent),
              ),
            )
          : null,
      locale: currentLocale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru'),
        Locale('en'),
        Locale('es'),
        Locale('zh'),
        Locale('ko'),
        Locale('fr'),
        Locale('he'),
        Locale('hi'),
        Locale('ar'),
        Locale('it'),
        Locale('de'),
      ],
      home: const AuthPageWrapper(),
    );
  }
}

class AuthPageWrapper extends StatefulWidget {
  const AuthPageWrapper({Key? key}) : super(key: key);

  @override
  State<AuthPageWrapper> createState() => _AuthPageWrapperState();
}

class _AuthPageWrapperState extends State<AuthPageWrapper>
    with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  final WebSocketService _webSocketService = WebSocketService();
  late Future<bool> _authCheckFuture;
  bool _isFirstLogin = false;
  bool _isAuthenticated = false;
  String? _authToken;
  int? _userId;
  String? _userEmail;
  String? _baseUrl;

  late ConnectionQualityService _connectionQuality;
  ApiService? _apiService;

  bool _isAppActive = true;
  Timer? _backgroundSyncTimer;

  // Всегда показываем логотип при запуске (без видео)
  bool _showSplashScreen = true;
  bool _initialCheckComplete = false;
  bool _isLoggedIn = false;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notificationService.onNotificationTap = _handleNotificationTap;
    _connectionQuality =
        Provider.of<ConnectionQualityService>(context, listen: false);

    _authCheckFuture = _checkAuthStatus();

    _initializeSplashAndAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationService.dispose();
    _webSocketService.dispose();
    _backgroundSyncTimer?.cancel();
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 AuthPageWrapper: app resumed');
        _isAppActive = true;
        _backgroundSyncTimer?.cancel();
        if (_isAuthenticated && _authToken != null) {
          _ensureWebSocketConnection();
        }
        break;
      case AppLifecycleState.paused:
        print('📱 AuthPageWrapper: app paused');
        _isAppActive = false;
        _startBackgroundSync();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _initializeSplashAndAuth() async {
    final isLoggedIn = await _authService.isLoggedIn();

    setState(() {
      _isLoggedIn = isLoggedIn;
      _initialCheckComplete = true;
    });

    if (isLoggedIn) {
      _preloadUserData();
    }

    // Запускаем таймер для автоматического закрытия splash screen через 3 секунды
    _splashTimer = Timer(const Duration(seconds: 3), () {
      _onSplashComplete();
    });
  }

  Future<void> _preloadUserData() async {
    try {
      final token = await _authService.getToken();
      if (token != null) {
        setState(() {
          _authToken = token;
        });

        final userId = _getUserIdFromToken(token);
        final email = _getUserEmailFromTokenSync(token) ?? '';
        final baseUrl = _getBaseUrl();

        setState(() {
          _userId = userId;
          _userEmail = email;
          _baseUrl = baseUrl;
        });

        _apiService = ApiService(
          baseUrl: baseUrl,
          token: token,
          connectionQuality: _connectionQuality,
        );
      }
    } catch (e) {
      print('❌ Error preloading user data: $e');
    }
  }

  // ✅ Callback после завершения сплэш-экрана
  void _onSplashComplete() {
    if (mounted) {
      setState(() {
        _showSplashScreen = false;
      });
    }
  }

  void _onSplashError() {
    print('⚠️ Splash error, skipping to content');
    if (mounted) {
      setState(() {
        _showSplashScreen = false;
      });
    }
  }

  void _startBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!_isAppActive && _isAuthenticated && _apiService != null) {
        print('🔄 Background sync: checking for new messages');
        _checkForNewMessages();
      }
    });
  }

  Future<void> _checkForNewMessages() async {
    try {
      final response = await _apiService!
          .get('/chats/unread-counts', priority: RequestPriority.low);
    } catch (e) {
      print('Background sync error: $e');
    }
  }

  Future<void> _ensureWebSocketConnection() async {
    if (_authToken != null && _baseUrl != null && _userId != null) {
      if (_webSocketService.status != ConnectionStatus.connected) {
        await _webSocketService.connect(
          token: _authToken!,
          baseUrl: _baseUrl!,
          userId: _userId,
        );
      }
    }
  }

  void _handleNotificationTap(Map<String, dynamic> payload) {
    print('📱 Notification tapped: $payload');
  }

  Future<bool> _checkAuthStatus() async {
    return await _authService.isLoggedIn();
  }

  Future<String?> _getUserEmailFromToken(String token) async {
    try {
      final decoded = JwtDecoder.decode(token);
      return decoded['email']?.toString();
    } catch (e) {
      print('Ошибка при получении email из токена: $e');
      return null;
    }
  }

  String? _getUserEmailFromTokenSync(String token) {
    try {
      final decoded = JwtDecoder.decode(token);
      return decoded['email']?.toString();
    } catch (e) {
      print('Ошибка при получении email из токена: $e');
      return null;
    }
  }

  int _getUserIdFromToken(String token) {
    try {
      final decoded = JwtDecoder.decode(token);
      return int.parse(decoded['userId'].toString());
    } catch (e) {
      print('Ошибка при получении userId из токена: $e');
      return 1;
    }
  }

  String _getBaseUrl() {
    return dotenv.env['API_URL'] ?? 'http://localhost:3004';
  }

  Future<void> _initializeBlockedUsers() async {
    final blockedUsersProvider =
        Provider.of<BlockedUsersProvider>(context, listen: false);
    await blockedUsersProvider.loadFromStorage();
  }

  Future<void> _initializeProfileProvider(String token) async {
    final profileProvider =
        Provider.of<ProfileProvider>(context, listen: false);
    // ✅ Сначала обновляем ApiService у провайдера, чтобы token был актуален
    if (_apiService != null) {
      profileProvider.updateApiService(_apiService!);
    }
    await profileProvider.loadProfileFromServer(token);
  }

  Future<void> _initializeAuthProvider(String token) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = _getUserIdFromToken(token);
    final userEmail =
        _getUserEmailFromTokenSync(token) ?? await _authService.getUserEmail();
    authProvider.setAuthData(token, userEmail ?? '', userId);
  }

  Future<void> _initializeNotificationService(
      String token, String baseUrl, int userId) async {
    try {
      await _notificationService.initialize(
        token: token,
        baseUrl: baseUrl,
        myUserId: userId,
      );
      print('✅ Notification service initialized for user $userId');
    } catch (e) {
      print('❌ Failed to initialize notification service: $e');
    }
  }

  Future<void> _initializeWebSocketService(
      String token, String baseUrl, int userId) async {
    try {
      await _webSocketService.connect(
        token: token,
        baseUrl: baseUrl,
        userId: userId,
      );

      _webSocketService.onStatusChange.listen((status) {
        // WebSocket status changes are frequent; avoid noisy logging in production.
        // If needed, enable detailed logging temporarily for debugging.
        if (status == ConnectionStatus.connected) {
        } else if (status == ConnectionStatus.disconnected ||
            status == ConnectionStatus.error) {
          if (_isAppActive && mounted) {
            _showConnectionWarning();
          }
        }
      });

      _webSocketService.onMessage.listen((message) {
        _handleWebSocketMessage(message);
      });
    } catch (e) {
      print('❌ Failed to initialize WebSocket service: $e');
    }
  }

  void _handleWebSocketMessage(Map<String, dynamic> message) {
    if (!_isAppActive) {
      if (message['type'] == 'new_message') {}
    }
  }

  void _showConnectionWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
                child: Text(
                    'Проблемы с соединением. Сообщения могут доставляться с задержкой.')),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _handleLogin(String token,
      {bool isFirstLogin = false, String? userEmail}) async {
    print('✅ Login successful, token received');
    print('📧 User email: $userEmail');
    print('🆔 Is first login: $isFirstLogin');

    await _authService.saveToken(token);
    await _authService.saveUserDataFromToken(token);

    if (userEmail != null && userEmail.isNotEmpty) {
      await _authService.saveUserEmail(userEmail);
    }

    final email = userEmail ?? _getUserEmailFromTokenSync(token) ?? '';
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = _getUserIdFromToken(token);
    final baseUrl = _getBaseUrl();

    authProvider.setAuthData(
      token,
      email,
      userId,
    );

    _authToken = token;
    _userId = userId;
    _userEmail = email;
    _baseUrl = baseUrl;

    _apiService = ApiService(
      baseUrl: baseUrl,
      token: token,
      connectionQuality: _connectionQuality,
    );

    await Future.wait([
      _initializeNotificationService(token, baseUrl, userId),
      _initializeWebSocketService(token, baseUrl, userId),
    ]);

    if (mounted) {
      setState(() {
        _isAuthenticated = true;
        _isFirstLogin = isFirstLogin;
        _isLoggedIn = true;
        _authCheckFuture = Future.value(true);
      });
    }
  }

  Future<void> _handleLogout() async {
    print('🚪 Выполняется logout');

    _webSocketService.disconnect();
    _webSocketService.clearQueue();

    _notificationService.clearActiveChat();

    final profileProvider =
        Provider.of<ProfileProvider>(context, listen: false);
    await profileProvider.clearLocalCache();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.clearAuthData();

    await _authService.deleteToken();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    _apiService = null;

    if (mounted) {
      setState(() {
        _isFirstLogin = false;
        _isAuthenticated = false;
        _isLoggedIn = false;
        _authToken = null;
        _userId = null;
        _userEmail = null;
        _baseUrl = null;
        _authCheckFuture = Future.value(false);
      });
    }

    print('✅ Logout завершен');
  }

  Widget _buildHomePage(String token) {
    final myUserId = _getUserIdFromToken(token);
    final userEmail = _userEmail ?? _getUserEmailFromTokenSync(token);
    final baseUrl = _baseUrl ?? _getBaseUrl();
    final connectionQuality =
        Provider.of<ConnectionQualityService>(context, listen: false);

    _apiService ??= ApiService(
      baseUrl: baseUrl,
      token: token,
      connectionQuality: connectionQuality,
    );

    return FutureBuilder(
      future: Future.wait([
        _initializeBlockedUsers(),
        _initializeAuthProvider(token),
        _initializeProfileProvider(token),
      ]),
      builder: (context, initSnapshot) {
        if (initSnapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen(context);
        }

        return MultiProvider(
          providers: [
            Provider<WebSocketService>.value(value: _webSocketService),
            Provider<ApiService>.value(value: _apiService!),
            ChangeNotifierProvider<OptimizedChatProvider>(
              create: (_) => OptimizedChatProvider(
                apiService: _apiService!,
                userId: myUserId,
              ),
            ),
          ],
          child: HomePage(
            token: token,
            onLogout: _handleLogout,
            myUserId: myUserId,
            isFirstLogin: _isFirstLogin,
            userEmail: userEmail,
            baseUrl: baseUrl,
            webSocketService: _webSocketService,
            apiService: _apiService!,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Показываем простой сплэш с логотипом и лоадером (видео отключено)
    if (_showSplashScreen) {
      return _buildSimpleSplashScreen();
    }

    if (_initialCheckComplete) {
      return _buildAuthContent();
    }

    return _buildLoadingScreen(context);
  }

  Widget _buildAuthContent() {
    if (_isAuthenticated && _authToken != null) {
      return _buildHomePage(_authToken!);
    }

    return FutureBuilder<bool>(
      future: _authCheckFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen(context);
        }

        if (snapshot.hasData && snapshot.data == true) {
          return FutureBuilder<String?>(
            future: _authService.getToken(),
            builder: (context, tokenSnapshot) {
              if (tokenSnapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingScreen(context);
              }

              if (tokenSnapshot.hasData && tokenSnapshot.data != null) {
                final token = tokenSnapshot.data!;
                return _buildHomePage(token);
              } else {
                return AuthPage(
                  onLogin: _handleLogin,
                );
              }
            },
          );
        } else {
          return AuthPage(
            onLogin: _handleLogin,
          );
        }
      },
    );
  }

  Widget _buildSimpleSplashScreen() {
    // Простой splash экран без видео - только логотип и лоадер
    const splashBgColor = Color(0xFFFFFCF3);

    return Scaffold(
      backgroundColor: splashBgColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AdaptiveLogo(
              backgroundColor: splashBgColor,
              size: LogoSize.large,
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Color(0xFF4CAF50)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: themeProvider.currentTheme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AdaptiveLogo(
              backgroundColor:
                  themeProvider.currentTheme.scaffoldBackgroundColor,
              size: LogoSize.large,
            ),
            const SizedBox(height: 30),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(
                  themeProvider.currentTheme.primaryColor),
            ),
          ],
        ),
      ),
    );
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}
