import 'dart:convert';
import '../utils/platform_utils.dart';

class AIMessage {
  final String? id; // Изменено с int? на String?
  final String chatId;
  final String messageId;
  final String text;
  final bool isFromUser;
  final DateTime createdAt;
  final bool isStreaming;

  AIMessage({
    this.id,
    required this.chatId,
    required this.messageId,
    required this.text,
    required this.isFromUser,
    required this.createdAt,
    this.isStreaming = false,
  });

  // Конструктор для сообщений от пользователя
  factory AIMessage.fromUser({
    String? id,
    required String text,
    required DateTime createdAt,
    bool isStreaming = false,
  }) {
    final messageId = id ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    return AIMessage(
      id: messageId,
      chatId: '', // будет установлено позже
      messageId: messageId,
      text: text,
      isFromUser: true,
      createdAt: createdAt,
      isStreaming: isStreaming,
    );
  }

  // Конструктор для сообщений от AI
  factory AIMessage.fromAI({
    String? id,
    required String text,
    required DateTime createdAt,
    bool isStreaming = false,
  }) {
    final messageId = id ?? 'ai_${DateTime.now().millisecondsSinceEpoch}';
    return AIMessage(
      id: messageId,
      chatId: '', // будет установлено позже
      messageId: messageId,
      text: text,
      isFromUser: false,
      createdAt: createdAt,
      isStreaming: isStreaming,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'message_id': messageId,
      'text': text,
      'is_from_user': isFromUser ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'is_streaming': isStreaming ? 1 : 0,
    };
  }

  factory AIMessage.fromMap(Map<String, dynamic> map) {
    return AIMessage(
      id: map['id']?.toString(),
      chatId: map['chat_id'] ?? '',
      messageId: map['message_id']?.toString() ?? '',
      text: map['text'] ?? '',
      isFromUser: map['is_from_user'] == 1,
      createdAt: DateTime.parse(map['created_at']).toLocal(),
      isStreaming: map['is_streaming'] == 1,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AIMessage.fromJson(String source) => 
      AIMessage.fromMap(jsonDecode(source));

  AIMessage copyWith({
    String? id,
    String? chatId,
    String? messageId,
    String? text,
    bool? isFromUser,
    DateTime? createdAt,
    bool? isStreaming,
  }) {
    return AIMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      messageId: messageId ?? this.messageId,
      text: text ?? this.text,
      isFromUser: isFromUser ?? this.isFromUser,
      createdAt: createdAt ?? this.createdAt,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}