import 'package:flutter/material.dart';
import 'dart:typed_data';

class User {
  final int id;
  final String name;
  final String nickname;
  final Color avatarColor;
  final Uint8List? avatarBytes;

  User({
    required this.id,
    required this.name,
    required this.nickname,
    required this.avatarColor,
    this.avatarBytes,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      name: map['name'] ?? '',
      nickname: map['nickname'] ?? '',
      avatarColor: _parseColor(map['avatar_color']),
      avatarBytes: map['avatar_bytes'] != null
          ? Uint8List.fromList(List<int>.from(map['avatar_bytes']))
          : null,
    );
  }

  static Color _parseColor(String? colorString) {
    if (colorString == null) return Colors.blue;
    try {
      if (colorString.startsWith('#')) {
        return Color(int.parse(colorString.substring(1), radix: 16) + 0xFF000000);
      }
      return Colors.blue;
    } catch (e) {
      return Colors.blue;
    }
  }
}