import 'dart:typed_data';
import 'package:flutter/material.dart';

class GroupMember {
  final int id;
  final int userId;
  final String name;
  final String nickname;
  final Uint8List? avatarBytes;
  final Color avatarColor;
  final String? contactName;
  final String role; // 'admin', 'member'
  final DateTime joinedAt;

  GroupMember({
    required this.id,
    required this.userId,
    required this.name,
    required this.nickname,
    this.avatarBytes,
    this.avatarColor = Colors.blue,
    this.contactName,
    required this.role,
    required this.joinedAt,
  });

  String get displayName => contactName ?? name;

  factory GroupMember.fromMap(Map<String, dynamic> map) {
    return GroupMember(
      id: map['id'],
      userId: map['user_id'],
      name: map['name'] ?? '',
      nickname: map['nickname'] ?? '',
      avatarColor: Color(int.parse(map['avatar_color']?.replaceFirst('#', '0xFF') ?? '0xFF2196F3')),
      contactName: map['contact_name'],
      role: map['role'] ?? 'member',
      joinedAt: DateTime.parse(map['joined_at']),
    );
  }
}