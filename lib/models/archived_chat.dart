import 'package:flutter/material.dart';
import 'chat.dart';
import '../utils/platform_utils.dart';

class ArchivedChat extends Chat {
  final DateTime archivedAt;
  
  ArchivedChat({
    required super.id,
    required super.title,
    required super.lastMessage,
    required super.lastMessageTime,
    required super.unreadCount,
    required super.participants,
    required super.isMuted,
    required super.isPinned,
    required this.archivedAt,
    required super.myUserId,
  }) : super(
          isAIChat: false,
          isArchived: true,
        );

  factory ArchivedChat.fromChat(Chat chat) {
    return ArchivedChat(
      id: chat.id,
      title: chat.title,
      lastMessage: chat.lastMessage,
      lastMessageTime: chat.lastMessageTime,
      unreadCount: chat.unreadCount,
      participants: chat.participants,
      isMuted: chat.isMuted,
      isPinned: chat.isPinned,
      archivedAt: DateTime.now(),
      myUserId: chat.myUserId,
    );
  }

  @override
  Chat copyWith({
    int? id,
    String? title,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    List<int>? participants,
    bool? isAIChat,
    bool? isMuted,
    bool? isPinned,
    bool? isArchived,
    DateTime? archivedAt,
    int? myUserId,
  }) {
    return ArchivedChat(
      id: id ?? this.id,
      title: title ?? this.title,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      participants: participants ?? this.participants,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      archivedAt: archivedAt ?? this.archivedAt,
      myUserId: myUserId ?? this.myUserId,
    );
  }
}