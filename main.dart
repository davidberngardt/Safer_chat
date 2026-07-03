import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'auth_page.dart';
import 'home_page.dart';
import 'providers/chat_provider.dart';
import 'services/openai_service.dart';

void main() async {
  // Загружаем переменные окружения из .env файла
  await dotenv.load(fileName: '.env');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Получаем API ключ из .env файла
    final apiKey = dotenv.get('OPENAI_API_KEY', fallback: '');

    // Проверяем, установлен ли API ключ
    final hasValidApiKey =
        apiKey.isNotEmpty && !apiKey.contains('your-actual-api-key');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Safe Chat',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: AuthPage(
        onLogin: (token) {
          // При успешном логине перезапускаем приложение с HomePage и провайдерами
          runApp(MyLoggedInApp(
              token: token, apiKey: apiKey, hasValidApiKey: hasValidApiKey));
        },
      ),
    );
  }
}

class MyLoggedInApp extends StatelessWidget {
  final String token;
  final String apiKey;
  final bool hasValidApiKey;

  const MyLoggedInApp({
    Key? key,
    required this.token,
    required this.apiKey,
    required this.hasValidApiKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => ChatProvider(
            openAIService: OpenAIService(apiKey: apiKey),
          ),
        ),
        // Здесь можете добавить другие провайдеры, если они у вас есть
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Safe Chat',
        theme: ThemeData(
          primarySwatch: Colors.orange,
          scaffoldBackgroundColor: Colors.white,
        ),
        home: HomePage(
          token: token,
          onLogout: () {
            // При выходе полностью перезапускаем приложение
            runApp(MyApp());
          },
        ),
      ),
    );
  }
}
