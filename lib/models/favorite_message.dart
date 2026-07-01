import 'package:flutter/foundation.dart';
import '../utils/platform_utils.dart';

class FavoriteMessage {
  final int id;
  final int originalMessageId;
  final int chatId;
  final String chatTitle;
  final String text;
  final DateTime createdAt;
  final DateTime savedAt;
  final String? fileUrl;
  final int typeId;
  final int? duration;
  final int originalUserId;

  FavoriteMessage({
    required this.id,
    required this.originalMessageId,
    required this.chatId,
    required this.chatTitle,
    required this.text,
    required this.createdAt,
    required this.savedAt,
    this.fileUrl,
    required this.typeId,
    this.duration,
    required this.originalUserId,
  });

  factory FavoriteMessage.fromMessage({
    required int id,
    required int originalMessageId,
    required int chatId,
    required String chatTitle,
    required String text,
    required DateTime createdAt,
    String? fileUrl,
    required int typeId,
    int? duration,
    required int originalUserId,
  }) {
    return FavoriteMessage(
      id: id,
      originalMessageId: originalMessageId,
      chatId: chatId,
      chatTitle: chatTitle,
      text: text,
      createdAt: createdAt,
      savedAt: DateTime.now(),
      fileUrl: fileUrl,
      typeId: typeId,
      duration: duration,
      originalUserId: originalUserId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'originalMessageId': originalMessageId,
      'chatId': chatId,
      'chatTitle': chatTitle,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'savedAt': savedAt.toIso8601String(),
      'fileUrl': fileUrl,
      'typeId': typeId,
      'duration': duration,
      'originalUserId': originalUserId,
    };
  }

  factory FavoriteMessage.fromMap(Map<String, dynamic> map) {
    return FavoriteMessage(
      id: map['id'],
      originalMessageId: map['originalMessageId'],
      chatId: map['chatId'],
      chatTitle: map['chatTitle'],
      text: map['text'],
      createdAt: DateTime.parse(map['createdAt']),
      savedAt: DateTime.parse(map['savedAt']),
      fileUrl: map['fileUrl'],
      typeId: map['typeId'],
      duration: map['duration'],
      originalUserId: map['originalUserId'],
    );
  }

  FavoriteMessage copyWith({
    int? id,
    int? originalMessageId,
    int? chatId,
    String? chatTitle,
    String? text,
    DateTime? createdAt,
    DateTime? savedAt,
    String? fileUrl,
    int? typeId,
    int? duration,
    int? originalUserId,
  }) {
    return FavoriteMessage(
      id: id ?? this.id,
      originalMessageId: originalMessageId ?? this.originalMessageId,
      chatId: chatId ?? this.chatId,
      chatTitle: chatTitle ?? this.chatTitle,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      savedAt: savedAt ?? this.savedAt,
      fileUrl: fileUrl ?? this.fileUrl,
      typeId: typeId ?? this.typeId,
      duration: duration ?? this.duration,
      originalUserId: originalUserId ?? this.originalUserId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FavoriteMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}