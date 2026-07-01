import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey;
  final String baseUrl = 'https://api.openai.com/v1/chat/completions';
  
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

  OpenAIService({required this.apiKey});

  Future<String> getBotResponse(String userMessage) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userMessage},
          ],
          'max_tokens': 500,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        return 'Извините, произошла ошибка. Попробуйте позже.';
      }
    } catch (e) {
      return 'Ошибка соединения. Проверьте интернет.';
    }
  }
}