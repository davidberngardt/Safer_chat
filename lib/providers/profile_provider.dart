import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/profile_models.dart';
import '../services/user_api_service.dart';
import '../services/api_service.dart';

class ProfileProvider extends ChangeNotifier {
  UserApiService _userApiService; // ✅ теперь не final — будем обновлять

  String _displayName = '';
  String _nickname = '';
  DateTime? _birthday;
  Gender? _gender;
  Uint8List? _avatarBytes;
  String? _avatarData;
  Color _avatarColor = Colors.blue;
  bool _isLoading = false;

  String get name => _displayName;
  String get nickname => _nickname.isEmpty ? '' : '@$_nickname';
  DateTime? get birthday => _birthday;
  Gender? get gender => _gender;
  Uint8List? get avatarBytes => _avatarBytes;
  Color get avatarColor => _avatarColor;
  bool get isLoading => _isLoading;

  ProfileProvider({
    required ApiService apiService,
    UserApiService? userApiService,
  }) : _userApiService = userApiService ?? UserApiService(apiService) {
    loadProfile();
  }

  /// ✅ Обновить ApiService (и UserApiService) новым токеном
  void updateApiService(ApiService newApiService) {
    _userApiService = UserApiService(newApiService);
  }

  set name(String value) {
    _displayName = value.trim();
    notifyListeners();
    _saveLocal();
  }

  set nickname(String value) {
    _nickname = value.replaceFirst('@', '').trim();
    notifyListeners();
    _saveLocal();
  }

  set birthday(DateTime? value) {
    _birthday = value;
    notifyListeners();
    _saveLocal();
  }

  set gender(Gender? value) {
    _gender = value;
    notifyListeners();
    _saveLocal();
  }

  set avatarBytes(Uint8List? value) {
    _avatarBytes = value;
    notifyListeners();
  }

  set avatarData(String? value) {
    _avatarData = value;
    if (value != null && value.isNotEmpty) {
      try {
        _avatarBytes = base64Decode(value);
      } catch (_) {
        _avatarBytes = null;
      }
    } else {
      _avatarBytes = null;
    }
    notifyListeners();
  }

  set avatarColor(Color value) {
    _avatarColor = value;
    notifyListeners();
    _saveLocal();
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_display_name', _displayName);
      await prefs.setString('profile_nickname', _nickname);
      await prefs.setString(
          'profile_birthday', _birthday?.toIso8601String() ?? '');
      await prefs.setString('profile_gender', _gender?.name ?? '');
      await prefs.setInt('profile_avatar_color', _avatarColor.value);
    } catch (_) {}
  }

  Future<void> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _displayName = prefs.getString('profile_display_name') ?? '';
      _nickname = prefs.getString('profile_nickname') ?? '';

      final birthdayStr = prefs.getString('profile_birthday');
      if (birthdayStr != null && birthdayStr.isNotEmpty) {
        _birthday = DateTime.parse(birthdayStr);
      }

      final genderStr = prefs.getString('profile_gender');
      if (genderStr != null && genderStr.isNotEmpty) {
        _gender = Gender.values.firstWhere(
          (g) => g.name == genderStr,
          orElse: () => Gender.male,
        );
      }

      final colorValue = prefs.getInt('profile_avatar_color');
      if (colorValue != null) _avatarColor = Color(colorValue);

      notifyListeners();
    } catch (_) {}
  }

  // ================= SERVER =================

  Future<bool> loadProfileFromServer(String token) async {
    _isLoading = true;
    notifyListeners();

    try {
      print('🔄 Loading profile from server...');
      final response = await _userApiService.getUserProfile(forceRefresh: true);
      print('✅ Profile loaded from server: $response');

      if (response != null && response.isNotEmpty) {
        // ✅ Сервер возвращает данные на верхнем уровне (не внутри "user")
        final user = response['user'] != null ? response['user'] : response;

        // Load name field from server
        _displayName = (user['name'] ?? '').toString().trim();

        _nickname =
            (user['nickname'] ?? '').toString().replaceFirst('@', '').trim();

        // ✅ Правильно парсим дату рождения (сервер отдает DD.MM.YYYY или ISO)
        if (user['birthday'] != null) {
          final birthdayStr = user['birthday'].toString();
          _birthday = _parseBirthday(birthdayStr);
        } else {
          _birthday = null;
        }

        if (user['gender'] != null) {
          try {
            _gender = Gender.values.firstWhere((g) => g.name == user['gender']);
          } catch (_) {
            _gender = null;
          }
        }

        // ✅ avatar: сервер может отдавать photo_url или avatar_url
        final avatarUrl = user['avatar_url'] ?? user['photo_url'];
        if (avatarUrl != null && avatarUrl.toString().isNotEmpty) {
          try {
            print('🖼️ Loading avatar from: $avatarUrl');
            final res = await http.get(Uri.parse(avatarUrl.toString()));
            if (res.statusCode == 200) {
              _avatarBytes = res.bodyBytes;
              print('✅ Avatar loaded successfully');
            }
          } catch (e) {
            print('❌ Avatar loading failed: $e');
          }
        } else if (user['avatar_data'] != null) {
          avatarData = user['avatar_data'].toString();
        }

        // ✅ avatar_color с сервера
        if (user['avatar_color'] != null) {
          try {
            _avatarColor = Color(int.parse(user['avatar_color'].toString()));
          } catch (_) {}
        }

        await _saveLocal();
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ Error loading profile from server: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// ✅ Парсит дату в формате DD.MM.YYYY или ISO 8601
  DateTime? _parseBirthday(String str) {
    if (str.isEmpty || str == 'null') return null;
    // Пробуем ISO
    final iso = DateTime.tryParse(str);
    if (iso != null) return iso;
    // Пробуем DD.MM.YYYY (формат сервера)
    try {
      final parts = str.split('.');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}
    // Пробуем DD.MM.YY
    try {
      final parts = str.split('.');
      if (parts.length == 3 && parts[2].length == 2) {
        return DateTime(
          2000 + int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<bool> saveProfileToServer(String token) async {
    _isLoading = true;
    notifyListeners();

    try {
      print('💾 Saving profile to server...');
      final response = await _userApiService.updateUserProfile(
        name: _displayName.isNotEmpty ? _displayName : null,
        nickname: _nickname.isNotEmpty ? _nickname : null,
        birthday: _birthday?.toIso8601String(),
        gender: _gender?.name,
        avatarBytes: _avatarBytes,
      );
      print('✅ Profile saved to server: $response');

      await loadProfileFromServer(token);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ Error saving profile to server: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> checkNicknameAvailability(String nickname, String token) async {
    try {
      print('🔍 Checking nickname availability: $nickname');
      final response = await _userApiService.checkNickname(nickname);
      print('✅ Nickname check result: $response');
      return response['available'] == true;
    } catch (e) {
      print('❌ Error checking nickname: $e');
      return false;
    }
  }

  Future<void> clearLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      _displayName = '';
      _nickname = '';
      _birthday = null;
      _gender = null;
      _avatarBytes = null;

      notifyListeners();
    } catch (_) {}
  }
}
