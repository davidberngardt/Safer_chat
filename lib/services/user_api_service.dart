import 'dart:typed_data';
import 'api_service.dart';

class UserApiService {
  final ApiService _apiService;

  Map<String, dynamic>? _cachedProfile;
  DateTime? _profileCacheTime;
  static const int profileCacheDuration = 300; // seconds

  UserApiService(this._apiService);

  // ==================== UPDATE PROFILE ====================

  Future<Map<String, dynamic>> updateUserProfile({
    String? name,
    String? nickname,
    String? birthday,
    String? gender,
    Uint8List? avatarBytes,
  }) async {
    if (name != null && name.trim().isEmpty) {
      throw ValidationException('Имя не может быть пустым');
    }

    if (nickname != null && nickname.trim().isEmpty) {
      throw ValidationException('Никнейм не может быть пустым');
    }

    if (avatarBytes != null && avatarBytes.length > 50 * 1024 * 1024) {
      throw ValidationException('Файл слишком большой (макс 50MB)');
    }

    print('🔄 Updating user profile...');
    print(
        '📝 Data: name=$name, nickname=$nickname, hasAvatar=${avatarBytes != null}');

    // Если есть файл → upload
    if (avatarBytes != null && avatarBytes.isNotEmpty) {
      print('📡 Making PUT /api/user request with avatar upload...');
      final response = await _apiService.uploadFile(
        'api/user',
        avatarBytes,
        'avatar.jpg',
        fields: {
          if (name != null) 'name': name.trim(),
          if (nickname != null) 'nickname': nickname.trim(),
          if (birthday != null) 'birthday': birthday,
          if (gender != null) 'gender': gender,
        },
      );
      print('✅ PUT /api/user response with avatar: $response');

      _invalidateCache();
      return response;
    }

    // Обычный update
    print('📡 Making PUT /api/user request...');
    final response = await _apiService.put(
      'api/user',
      data: {
        if (name != null) 'name': name.trim(),
        if (nickname != null) 'nickname': nickname.trim(),
        if (birthday != null) 'birthday': birthday,
        if (gender != null) 'gender': gender,
      },
    );
    print('✅ PUT /api/user response: $response');

    _invalidateCache();
    return response;
  }

  // ==================== GET PROFILE ====================

  Future<Map<String, dynamic>?> getUserProfile({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _isCacheValid()) {
      print('💾 Using cached profile data');
      return _cachedProfile;
    }

    print('📡 Making GET /api/user request...');
    final res = await _apiService.get('api/user');
    print('✅ GET /api/user response: $res');

    _cacheProfile(res);
    return res;
  }

  // ==================== CHECK NICKNAME ====================

  Future<Map<String, dynamic>> checkNickname(String nickname) async {
    if (nickname.trim().isEmpty) {
      return {'available': false, 'error': 'Пустой ник'};
    }

    print('📡 Making POST /api/user/check-nickname request...');
    final response = await _apiService.post(
      'api/user/check-nickname',
      data: {'nickname': nickname.trim()},
    );
    print('✅ POST /api/user/check-nickname response: $response');
    return response;
  }

  // ==================== CACHE ====================

  void _cacheProfile(Map<String, dynamic> data) {
    _cachedProfile = data;
    _profileCacheTime = DateTime.now();
  }

  bool _isCacheValid() {
    if (_cachedProfile == null || _profileCacheTime == null) return false;

    return DateTime.now().difference(_profileCacheTime!).inSeconds <
        profileCacheDuration;
  }

  void _invalidateCache() {
    _cachedProfile = null;
    _profileCacheTime = null;
  }

  void dispose() {
    _invalidateCache();
  }
}

// ==================== EXCEPTIONS ====================

class ValidationException implements Exception {
  final String message;
  ValidationException(this.message);
}
