import 'dart:convert';
import 'package:http/http.dart' as http;

class OllamaService {
  final String baseUrl = 'http://localhost:11434';
  
  static const String systemPrompt = """
Ты — полезный ассистент в мессенджере. Отвечай кратко и по делу.

Правила:
1. Если спрашивают про погоду - уточни город пользователя и дай ответ
2. Если спрашивают про курс валют - уточни о какой валюте идёт речь и дай ответ
3. Если спрашивают про оружие, наркотики, насилие, преступления- вежливо отказывай в ответе
4. На все остальные вопросы отвечай вежливо и помогай чем можешь
5. Если можешь дать ссылку при ответе- давай
6. Будь дружелюбным, но профессиональным
""";

  OllamaService();

  Future<String> getBotResponse(String userMessage) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/generate'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'openchat:7b', 
          'prompt': '$systemPrompt\n\nПользователь: $userMessage\n\nАссистент:',
          'stream': false,
          'options': {
          'max_tokens': 150,  
          'top_p': 0.9,     
          'top_k': 40, 
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response'].trim();
      } else {
        return 'Извините, произошла ошибка при обращении к Ollama. Проверьте, запущен ли Ollama сервер.';
      }
    } catch (e) {
      return 'Ошибка соединения с Ollama. Проверьте, запущен ли Ollama сервер на localhost:11434.';
    }
  }
}