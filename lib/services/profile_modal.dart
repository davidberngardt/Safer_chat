import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import '../models/profile_models.dart';
import '../providers/profile_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import 'package:flutter/foundation.dart';
import '../utils/platform_utils.dart';
import 'api_service.dart';
import 'user_api_service.dart';

enum BirthdayVisibility { nobody, contacts, everyone }

class ProfileViewModal extends StatefulWidget {
  const ProfileViewModal({super.key});

  @override
  State<ProfileViewModal> createState() => _ProfileViewModalState();
}

class _ProfileViewModalState extends State<ProfileViewModal> {
  bool isLoading = true;
  String name = '';
  String nickname = '';
  String email = '';
  DateTime? birthday;
  Gender? gender;
  Uint8List? avatarBytes;
  Color avatarColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final profileProvider =
          Provider.of<ProfileProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      print('🔄 Loading profile data...');

      // Use ApiService (provided in widget tree) to fetch fresh profile with correct token
      final api = Provider.of<ApiService>(context, listen: false);
      Map<String, dynamic> resp = {};
      try {
        print('📡 Making GET /api/user request...');
        resp = await api.get('api/user', useCache: false);
        print('✅ GET /api/user response: $resp');
      } catch (e) {
        // fallback to provider data if api call fails
        print('❌ Ошибка получения профиля через ApiService: $e');
      }

      String userEmail = '';
      if (resp.isNotEmpty) {
        // ✅ Сервер возвращает данные на верхнем уровне, но поддерживаем и вложенный user
        final user = resp['user'] != null ? resp['user'] : resp;
        userEmail = (user['email'] ?? '') as String;
        if (mounted) {
          setState(() {
            name = (user['name'] ?? '').toString();
            nickname = (user['nickname'] ?? '')
                .toString()
                .replaceFirst('@', '')
                .trim();
            email = userEmail;

            // ✅ Правильный парсинг дня рождения (сервер отдает DD.MM.YYYY или ISO)
            if (user['birthday'] != null) {
              birthday = _parseBirthday(user['birthday'].toString());
            } else {
              birthday = profileProvider.birthday;
            }

            try {
              gender = user['gender'] != null
                  ? Gender.values.firstWhere((g) => g.name == user['gender'])
                  : profileProvider.gender;
            } catch (_) {
              gender = profileProvider.gender;
            }

            // ✅ avatar_url или photo_url
            final avatarUrl = user['avatar_url'] ?? user['photo_url'];
            if (avatarUrl != null && avatarUrl.toString().isNotEmpty) {
              _loadAvatarBytes(avatarUrl.toString());
            }

            avatarBytes = profileProvider.avatarBytes;
            // ✅ avatar_color с сервера
            if (user['avatar_color'] != null) {
              try {
                avatarColor = Color(int.parse(user['avatar_color'].toString()));
              } catch (_) {
                avatarColor = profileProvider.avatarColor;
              }
            } else {
              avatarColor = profileProvider.avatarColor;
            }
            isLoading = false;
          });
        }
      } else {
        // fallback to provider-stored values
        // try to use email from auth provider first (saved from token/login)
        final fetchedEmail =
            authProvider.email != null && authProvider.email!.isNotEmpty
                ? authProvider.email!
                : await _fetchUserEmail(authProvider.token ?? '');
        if (mounted) {
          setState(() {
            name = profileProvider.name ?? '';
            nickname = profileProvider.nickname ?? '';
            email = fetchedEmail;
            birthday = profileProvider.birthday;
            gender = profileProvider.gender;
            avatarBytes = profileProvider.avatarBytes;
            avatarColor = profileProvider.avatarColor;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Ошибка загрузки профиля: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// ✅ Парсит дату в формате DD.MM.YYYY или ISO 8601
  DateTime? _parseBirthday(String str) {
    if (str.isEmpty || str == 'null') return null;
    final iso = DateTime.tryParse(str);
    if (iso != null) return iso;
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
    return null;
  }

  /// ✅ Загружает аватар по URL
  Future<void> _loadAvatarBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          avatarBytes = res.bodyBytes;
        });
      }
    } catch (_) {}
  }

  Future<String> _fetchUserEmail(String token) async {
    try {
      // Use ApiService from Provider to ensure correct baseUrl and token
      final api = Provider.of<ApiService>(context, listen: false);
      print('📡 Making GET /api/user request for email...');
      final resp = await api.get('api/user', useCache: false);
      print('✅ GET /api/user response for email: $resp');
      if (resp != null && resp.isNotEmpty) {
        // ✅ Сервер возвращает данные на верхнем уровне
        final user = resp['user'] != null ? resp['user'] : resp;
        return (user['email'] ?? '') as String;
      }
      return '';
    } catch (e) {
      print('❌ Ошибка получения email: $e');
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;

    double modalWidth;
    if (screenWidth > 1200) {
      modalWidth = 600;
    } else if (screenWidth > 800) {
      modalWidth = 500;
    } else if (screenWidth > 600) {
      modalWidth = 450;
    } else {
      modalWidth = screenWidth * 0.9;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: modalWidth,
        constraints: BoxConstraints(
          maxWidth: modalWidth,
          maxHeight: 650,
        ),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFA000),
                    Color(0xFFFF5722),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      localizations.profile,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          Center(
                            child: CircleAvatar(
                              radius: 55,
                              backgroundColor: avatarColor,
                              backgroundImage: avatarBytes != null
                                  ? MemoryImage(avatarBytes!)
                                  : null,
                              child: avatarBytes == null
                                  ? const Icon(Icons.person_rounded,
                                      size: 60, color: Colors.white)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            name.isEmpty ? localizations.name : name,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          if (nickname.isNotEmpty) ...[
                            Text(
                              nickname,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            email.isNotEmpty
                                ? email
                                : localizations.notSpecified,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDarkMode
                                  ? Colors.white60
                                  : Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 36),
                          buildProfileField(
                            context,
                            Icons.email_rounded,
                            'Email',
                            email.isNotEmpty
                                ? email
                                : localizations.notSpecified,
                            isDarkMode,
                          ),
                          buildProfileField(
                            context,
                            Icons.cake_rounded,
                            localizations.birthday,
                            birthday != null
                                ? '${birthday!.day.toString().padLeft(2, '0')}.${birthday!.month.toString().padLeft(2, '0')}.${birthday!.year}'
                                : localizations.notSpecified,
                            isDarkMode,
                          ),
                          buildProfileField(
                            context,
                            Icons.person_outline_rounded,
                            localizations.gender,
                            gender == Gender.male
                                ? localizations.male
                                : gender == Gender.female
                                    ? localizations.female
                                    : localizations.other,
                            isDarkMode,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => openSettings(context),
                              icon: const Icon(Icons.edit_rounded),
                              label: Text(
                                localizations.editProfile,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildProfileField(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    bool isDarkMode,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isDarkMode ? Colors.white70 : Colors.grey[600],
              size: 24,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDarkMode ? Colors.white54 : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void openSettings(BuildContext context) {
    Navigator.of(context).pop();
    showProfileSettingsModal(context);
  }
}

class ProfileSettingsModal extends StatefulWidget {
  final String? initialEmail;
  final bool isRequired;

  const ProfileSettingsModal({
    super.key,
    this.initialEmail,
    this.isRequired = false,
  });

  @override
  State<ProfileSettingsModal> createState() => _ProfileSettingsModalState();
}

class _ProfileSettingsModalState extends State<ProfileSettingsModal> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController nicknameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController verificationCodeController =
      TextEditingController();

  DateTime? birthday;
  Gender? gender;
  BirthdayVisibility birthdayVisibility = BirthdayVisibility.contacts;
  bool blockCalls = false;
  bool blockVoice = false;
  bool blockGroups = false;

  final ImagePicker picker = ImagePicker();
  Uint8List? avatarBytes;
  Color avatarColor = Colors.blue;

  final List<Color> palette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.brown,
    Colors.pink,
  ];

  bool isSaving = false;
  String? nicknameError;
  bool isCheckingNickname = false;
  Timer? _debounce;
  String? generalError;
  String? originalEmail;
  bool _isEmailVerificationSent = false;
  bool _isEmailVerified = false;
  String? emailError;
  String? verificationCodeError;
  int _resendTimer = 60;
  Timer? _resendCodeTimer;
  bool _canResendCode = false;
  bool _isFormValid = false;
  bool _showEmailValidationError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final profileProvider =
          Provider.of<ProfileProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // ✅ Загружаем профиль с сервера (токен из auth провайдера)
      final loaded =
          await profileProvider.loadProfileFromServer(authProvider.token ?? '');

      String userEmail;
      if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
        userEmail = widget.initialEmail!;
        _isEmailVerified = true;
      } else {
        // ✅ Сначала пробуем получить email из AuthProvider, потом с сервера
        userEmail = authProvider.email ?? '';
        if (userEmail.isEmpty) {
          userEmail = await _fetchUserEmail(authProvider.token ?? '');
        }
        // ✅ Если все еще пустой, пробуем получить из ответа сервера при загрузке профиля
        if (userEmail.isEmpty && loaded) {
          try {
            final api = Provider.of<ApiService>(context, listen: false);
            final freshResp = await api.get('api/user', useCache: false);
            final user =
                freshResp['user'] != null ? freshResp['user'] : freshResp;
            userEmail = (user['email'] ?? '') as String;
          } catch (e) {
            print('❌ Дополнительная попытка получить email: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          // ✅ Имя: из профиля, если загрузилось
          final profileName = profileProvider.name ?? '';
          nameController.text = profileName.isNotEmpty ? profileName : '';

          // ✅ Никнейм: геттер добавляет @, убираем его для контроллера
          final serverNickname =
              profileProvider.nickname?.replaceAll('@', '').trim() ?? '';
          nicknameController.text = serverNickname;

          emailController.text = userEmail;
          originalEmail = userEmail;

          birthday = profileProvider.birthday;
          gender = profileProvider.gender;
          avatarBytes = profileProvider.avatarBytes;
          avatarColor = profileProvider.avatarColor;

          // ✅ Для первого входа принудительно разрешаем сохранить (даже без заполнения)
          // кнопка будет доступна, onSave проверит обязательные поля
          _checkFormValidity();

          print(
              '🔄 Modal initialized: name="${nameController.text}", nickname="${nicknameController.text}", email="$userEmail", isRequired=${widget.isRequired}, loaded=$loaded');
        });
      }
    });
  }

  Future<String> _fetchUserEmail(String token) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      print('📡 Making GET /api/user request for email (settings)...');
      final resp = await api.get('api/user', useCache: false);
      print('✅ GET /api/user response for email (settings): $resp');
      if (resp != null && resp.isNotEmpty) {
        // ✅ Сервер возвращает данные на верхнем уровне
        final user = resp['user'] != null ? resp['user'] : resp;
        final email = (user['email'] ?? '') as String;
        print('📧 Извлечен email: "$email"');
        return email;
      }
      print('⚠️ Пустой ответ от сервера при получении email');
      return '';
    } catch (e) {
      print('❌ Ошибка получения email: $e');
      return '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _resendCodeTimer?.cancel();
    nameController.dispose();
    nicknameController.dispose();
    emailController.dispose();
    verificationCodeController.dispose();
    super.dispose();
  }

  void _checkFormValidity() {
    final localizations = AppLocalizations.of(context)!;
    final trimmedName = nameController.text.trim();
    final trimmedNickname = nicknameController.text.trim();
    final email = emailController.text.trim();
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    bool isValid = true;

    // ✅ Для isRequired НЕ отключаем кнопку только из-за пустых полей —
    // валидация будет в onSave() с показом ошибки пользователю
    if (!widget.isRequired && trimmedName.isEmpty && trimmedNickname.isEmpty) {
      // Только для необязательного режима: если ничего не меняли — OK, иначе требуем
      // Ничего не делаем, isValid остаётся true
    }

    if (_showEmailValidationError &&
        email.isNotEmpty &&
        !emailRegex.hasMatch(email)) {
      isValid = false;
    }

    // ✅ Убираем проверку nicknameError из _checkFormValidity
    // Валидацию никнейма делаем только при сохранении
    // if (nicknameError != null && nicknameError!.isNotEmpty) {
    //   isValid = false;
    // }

    if (email != originalEmail && !_isEmailVerified) {
      isValid = false;
    }

    setState(() {
      _isFormValid = isValid;
    });
  }

  /// ✅ Парсит дату в формате DD.MM.YYYY или ISO 8601
  DateTime? _parseBirthday(String str) {
    if (str.isEmpty || str == 'null') return null;
    final iso = DateTime.tryParse(str);
    if (iso != null) return iso;
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
    return null;
  }

  Future<bool> _checkNicknameAvailability(String nickname) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      print('📡 Checking nickname availability: $nickname');
      final resp = await api
          .post('api/user/check-nickname', data: {'nickname': nickname.trim()});
      print('✅ Nickname check response: $resp');
      return resp != null && resp['available'] == true;
    } catch (e) {
      print('❌ Ошибка проверки никнейма: $e');
      return false;
    }
  }

  void _onNicknameChanged(String value) {
    // ✅ Убираем автоматическую проверку никнейма при вводе
    // Проверка будет происходить только при сохранении
    setState(() {
      nicknameError = null; // Сбрасываем старую ошибку
    });
    _checkFormValidity();
  }

  void _onNameChanged(String value) {
    _checkFormValidity();
  }

  void _onEmailChanged(String value) {
    setState(() {
      _isEmailVerificationSent = false;
      _isEmailVerified = false;
      emailError = null;
      verificationCodeController.clear();
      _showEmailValidationError = false;
    });
    _checkFormValidity();
  }

  Future<void> _checkNickname(String value) async {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      if (mounted) {
        setState(() {
          nicknameError = null;
          isCheckingNickname = false;
        });
      }
      _checkFormValidity();
      return;
    }

    final profileProvider =
        Provider.of<ProfileProvider>(context, listen: false);
    final currentNickname =
        profileProvider.nickname?.replaceFirst('@', '') ?? '';

    if (trimmed == currentNickname) {
      if (mounted) {
        setState(() {
          nicknameError = null;
          isCheckingNickname = false;
        });
      }
      _checkFormValidity();
      return;
    }

    if (mounted) {
      setState(() {
        nicknameError = null;
        isCheckingNickname = true;
      });
    }

    final available = await _checkNicknameAvailability(trimmed);

    if (mounted) {
      final localizations = AppLocalizations.of(context)!;
      setState(() {
        isCheckingNickname = false;
        nicknameError = !available ? localizations.nicknameTaken : null;
      });
    }
    _checkFormValidity();
  }

  void _startResendTimer() {
    _canResendCode = false;
    _resendTimer = 60;
    _resendCodeTimer?.cancel();
    _resendCodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        setState(() {
          _resendTimer--;
        });
      } else {
        timer.cancel();
        setState(() {
          _canResendCode = true;
        });
      }
    });
  }

  Future<void> _sendEmailVerificationCode() async {
    final newEmail = emailController.text.trim();
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    if (newEmail.isEmpty) {
      setState(() {
        emailError = AppLocalizations.of(context)!.enterEmail;
        _showEmailValidationError = true;
      });
      _checkFormValidity();
      return;
    }

    if (!emailRegex.hasMatch(newEmail)) {
      setState(() {
        emailError = AppLocalizations.of(context)!.enterValidEmail;
        _showEmailValidationError = true;
      });
      _checkFormValidity();
      return;
    }

    if (newEmail == originalEmail) {
      setState(() {
        emailError = null;
        _isEmailVerified = true;
        _showEmailValidationError = false;
      });
      _checkFormValidity();
      return;
    }

    setState(() {
      isSaving = true;
      emailError = null;
      generalError = null;
      _showEmailValidationError = false;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      print('📡 Sending email verification code to: $newEmail');
      final resp = await api.post('api/send-verification-code',
          data: {'email': newEmail, 'isEmailChange': true},
          customTimeout: const Duration(seconds: 30));
      print('✅ Email verification code response: $resp');
      // assume success if no exception
      setState(() {
        _isEmailVerificationSent = true;
        _isEmailVerified = false;
        emailError = null;
      });
      _startResendTimer();
      _checkFormValidity();
    } catch (e) {
      setState(() {
        emailError = '${AppLocalizations.of(context)!.codeSendError}: $e';
      });
      _checkFormValidity();
    } finally {
      setState(() {
        isSaving = false;
      });
    }
  }

  Future<void> _verifyEmailCode() async {
    final code = verificationCodeController.text.trim();
    final newEmail = emailController.text.trim();

    if (code.isEmpty) {
      setState(() {
        verificationCodeError =
            AppLocalizations.of(context)!.enterVerificationCode;
      });
      return;
    }

    if (code.length != 4) {
      setState(() {
        verificationCodeError = AppLocalizations.of(context)!.codeMustBe4Digits;
      });
      return;
    }

    setState(() {
      isSaving = true;
      verificationCodeError = null;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      print('📡 Verifying email code: $code for $newEmail');
      final resp = await api.post('api/verify-email-code',
          data: {'email': newEmail, 'code': code, 'isEmailChange': true},
          customTimeout: const Duration(seconds: 30));
      print('✅ Email verification response: $resp');
      if (resp != null &&
          (resp['success'] == true || resp['verified'] == true)) {
        setState(() {
          _isEmailVerified = true;
          verificationCodeError = null;
          _resendCodeTimer?.cancel();
          originalEmail = newEmail;
        });
        _checkFormValidity();
      } else {
        setState(() {
          verificationCodeError = resp != null
              ? (resp['error'] ??
                  AppLocalizations.of(context)!.invalidVerificationCode)
              : AppLocalizations.of(context)!.invalidVerificationCode;
        });
      }
    } catch (e) {
      setState(() {
        verificationCodeError =
            '${AppLocalizations.of(context)!.codeVerificationError}: $e';
      });
    } finally {
      setState(() {
        isSaving = false;
      });
    }
  }

  Future<void> pickAvatar() async {
    try {
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      Uint8List bytes;
      if (kIsWeb) {
        bytes = await picked.readAsBytes();
      } else {
        final ImageCropper cropper = ImageCropper();
        final CroppedFile? cropped = await cropper.cropImage(
          sourcePath: picked.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: AppLocalizations.of(context)!.cropPhoto,
              toolbarColor: Theme.of(context).primaryColor,
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: false,
            ),
            IOSUiSettings(
              minimumAspectRatio: 1.0,
            ),
          ],
        );

        if (cropped == null) return;
        bytes = await File(cropped.path).readAsBytes();
      }

      if (mounted) {
        setState(() {
          avatarBytes = bytes;
        });
      }
    } catch (e) {
      print('Ошибка pickAvatar: $e');
    }
  }

  Future<void> pickBirthday() async {
    final now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: birthday ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked != null) {
      setState(() {
        birthday = picked;
      });
    }
  }

  void showColorPicker() {
    if (avatarBytes != null) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context)!.selectColor),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: palette.map((color) {
              final isSelected = color == avatarColor;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    avatarColor = color;
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 4)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 24)
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> onSave() async {
    if (isSaving) return;

    print('🚀 onSave() вызван');
    print(
        '📝 Данные формы: name="$nameController.text", nickname="$nicknameController.text", email="$emailController.text"');

    final localizations = AppLocalizations.of(context)!;
    final trimmedName = nameController.text.trim();
    final trimmedNickname = nicknameController.text.trim();
    final newEmail = emailController.text.trim();
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    print(
        '📋 Обработанные данные: name="$trimmedName", nickname="$trimmedNickname", email="$newEmail"');

    if (widget.isRequired && trimmedName.isEmpty && trimmedNickname.isEmpty) {
      setState(() {
        generalError = localizations.fillAtLeastOneField;
      });
      return;
    }

    if (newEmail.isNotEmpty && !emailRegex.hasMatch(newEmail)) {
      setState(() {
        generalError = localizations.enterValidEmail;
        _showEmailValidationError = true;
      });
      _checkFormValidity();
      return;
    }

    // ✅ Проверяем никнейм только если он указан
    if (trimmedNickname.isNotEmpty) {
      try {
        print('🔍 Проверяем доступность никнейма: "$trimmedNickname"');
        final isAvailable = await _checkNicknameAvailability(trimmedNickname);
        if (!isAvailable) {
          setState(() {
            generalError = 'Никнейм "$trimmedNickname" уже занят';
          });
          return;
        }
        print('✅ Никнейм доступен');
      } catch (e) {
        print('❌ Ошибка проверки никнейма: $e');
        setState(() {
          generalError = 'Ошибка проверки никнейма: ${e.toString()}';
        });
        return;
      }
    }

    if (newEmail != originalEmail && !_isEmailVerified) {
      setState(() {
        generalError = localizations.confirmNewEmail;
      });
      return;
    }

    setState(() {
      generalError = null;
      isSaving = true;
    });

    final profileProvider =
        Provider.of<ProfileProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      // update local provider immediately
      profileProvider.name = trimmedName;
      profileProvider.nickname = trimmedNickname;
      profileProvider.birthday = birthday;
      profileProvider.gender = gender;
      profileProvider.avatarBytes = avatarBytes;
      profileProvider.avatarColor = avatarColor;

      // Use ApiService from Provider (it contains correct token)
      final api = Provider.of<ApiService>(context, listen: false);

      Map<String, dynamic> resp = {};

      final includeEmail =
          newEmail.isNotEmpty && newEmail != originalEmail && _isEmailVerified;

      print('🔄 Saving profile data...');
      print(
          '📝 Data: name="$trimmedName", nickname="$trimmedNickname", hasAvatar=${avatarBytes != null}');

      if (avatarBytes != null && avatarBytes!.isNotEmpty) {
        // upload with avatar using multipart form data
        print('📡 Making PUT /api/user request with avatar...');
        resp = await api
            .uploadFile('api/user', avatarBytes!, 'avatar.jpg', fields: {
          if (trimmedName.isNotEmpty) 'name': trimmedName,
          if (trimmedNickname.isNotEmpty) 'nickname': trimmedNickname,
          if (birthday != null) 'birthday': birthday!.toIso8601String(),
          if (gender != null) 'gender': gender!.name,
          if (includeEmail) 'email': newEmail,
        });
        print('✅ PUT /api/user response with avatar: $resp');
      } else {
        // simple update using PUT method
        print('📡 Making PUT /api/user request...');
        resp = await api.put('api/user', data: {
          if (trimmedName.isNotEmpty) 'name': trimmedName,
          if (trimmedNickname.isNotEmpty) 'nickname': trimmedNickname,
          if (birthday != null) 'birthday': birthday!.toIso8601String(),
          if (gender != null) 'gender': gender!.name,
          if (includeEmail) 'email': newEmail,
        });
        print('✅ PUT /api/user response: $resp');
      }

      // Invalidate cached /user entry
      try {
        api.invalidateCacheForPath('api/user');
      } catch (_) {}

      // Fetch fresh profile from server and apply to provider
      try {
        print('📡 Fetching fresh profile after save...');
        final fresh = await api.get('api/user', useCache: false);
        print('✅ Fresh profile response: $fresh');
        if (fresh != null && fresh.isNotEmpty) {
          final user = fresh['user'] != null ? fresh['user'] : fresh;
          profileProvider.name =
              (user['name'] ?? profileProvider.name) as String;
          profileProvider.nickname =
              (user['nickname'] ?? profileProvider.nickname)
                  .toString()
                  .replaceFirst('@', '');
          // ✅ Правильно парсим дату (сервер отдает DD.MM.YYYY)
          if (user['birthday'] != null) {
            profileProvider.birthday =
                _parseBirthday(user['birthday'].toString());
          }
          try {
            profileProvider.gender = user['gender'] != null
                ? Gender.values.firstWhere((g) => g.name == user['gender'])
                : profileProvider.gender;
          } catch (_) {}
          if (user['avatar_url'] != null || user['photo_url'] != null) {
            try {
              final url = (user['avatar_url'] ?? user['photo_url']).toString();
              final res = await http.get(Uri.parse(url));
              if (res.statusCode == 200)
                profileProvider.avatarBytes = res.bodyBytes;
            } catch (_) {}
          } else if (user['avatar_data'] != null) {
            profileProvider.avatarData = user['avatar_data'].toString();
          }
          // Update auth provider email if server returned email and it differs
          try {
            final authProvider =
                Provider.of<AuthProvider>(context, listen: false);
            final serverEmail = (user['email'] ?? '') as String;
            if (serverEmail.isNotEmpty && authProvider.token != null) {
              // keep userId as is
              final uid = authProvider.userId ?? authProvider.userId ?? 0;
              try {
                authProvider.setAuthData(authProvider.token!, serverEmail, uid);
              } catch (_) {}
            }
          } catch (_) {}
        }
      } catch (freshError) {
        print('❌ Ошибка обновления данных после сохранения: $freshError');
        // Не блокируем успешное завершение из-за ошибки обновления
      }

      // ✅ Если дошли до этого места без исключений - сохранение прошло успешно
      if (mounted) {
        print('✅ Профиль успешно сохранен, закрываем модальное окно');
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ Критическая ошибка сохранения профиля: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() {
          generalError = 'Ошибка сохранения: ${e.toString()}';
        });
      }
    }

    if (mounted) {
      setState(() {
        isSaving = false;
      });
    }
  }

  Widget buildTextField(String label, TextEditingController controller,
      {String? prefix, int? maxLength, ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLength: maxLength,
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixText: prefix,
            hintText: label.toLowerCase(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.all(18),
            counterText: '',
          ),
        ),
      ],
    );
  }

  Widget buildNicknameField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextField(
              controller: nicknameController,
              maxLength: 30,
              onChanged: _onNicknameChanged,
              decoration: InputDecoration(
                prefixText: '@',
                hintText: label.toLowerCase(),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                contentPadding: const EdgeInsets.all(18),
                counterText: '',
                errorText: nicknameError,
                errorStyle: const TextStyle(fontSize: 14, color: Colors.red),
              ),
            ),
            if (isCheckingNickname)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget buildEmailField(String label) {
    final bool emailChanged = emailController.text.trim() != originalEmail;
    final bool showError =
        _showEmailValidationError && emailController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: emailController,
                enabled: !_isEmailVerificationSent,
                onChanged: _onEmailChanged,
                decoration: InputDecoration(
                  hintText: 'example@mail.com',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                  contentPadding: const EdgeInsets.all(18),
                  errorText: showError ? emailError : null,
                  errorStyle: const TextStyle(fontSize: 14, color: Colors.red),
                  suffixIcon: _isEmailVerified
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            if (emailChanged && !_isEmailVerified) ...[
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isSaving ? null : _sendEmailVerificationCode,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(AppLocalizations.of(context)!.code),
              ),
            ],
          ],
        ),
        if (_isEmailVerificationSent && !_isEmailVerified) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: verificationCodeController,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.codeFromEmail,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    contentPadding: const EdgeInsets.all(18),
                    errorText: verificationCodeError,
                    counterText: '',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, letterSpacing: 4),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isSaving ? null : _verifyEmailCode,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _canResendCode ? _sendEmailVerificationCode : null,
                child: Text(
                  _canResendCode
                      ? AppLocalizations.of(context)!.resendCode
                      : '${AppLocalizations.of(context)!.resendIn} $_resendTimer ${AppLocalizations.of(context)!.seconds}',
                  style: TextStyle(
                    fontSize: 14,
                    color: _canResendCode
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget buildDateField(String label) {
    return GestureDetector(
      onTap: isSaving ? null : pickBirthday,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              birthday != null
                  ? '${birthday!.day.toString().padLeft(2, '0')}.${birthday!.month.toString().padLeft(2, '0')}.${birthday!.year}'
                  : '',
            ),
          ),
        ],
      ),
    );
  }

  Widget buildGenderField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        DropdownButtonFormField<Gender?>(
          value: gender,
          decoration: InputDecoration(
            hintText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.all(18),
          ),
          items: [
            DropdownMenuItem(
                value: null,
                child: Text(AppLocalizations.of(context)!.notSpecified)),
            DropdownMenuItem(
                value: Gender.male,
                child: Text(AppLocalizations.of(context)!.male)),
            DropdownMenuItem(
                value: Gender.female,
                child: Text(AppLocalizations.of(context)!.female)),
          ],
          onChanged: isSaving
              ? null
              : (value) {
                  setState(() {
                    gender = value;
                  });
                  _checkFormValidity();
                },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final bool hasPhoto = avatarBytes != null;
    final screenWidth = MediaQuery.of(context).size.width;

    double modalWidth;
    if (screenWidth > 1200) {
      modalWidth = 650;
    } else if (screenWidth > 800) {
      modalWidth = 550;
    } else if (screenWidth > 600) {
      modalWidth = 500;
    } else {
      modalWidth = screenWidth * 0.9;
    }

    return WillPopScope(
      onWillPop: () async {
        if (widget.isRequired && !_isFormValid) {
          setState(() {
            generalError = localizations.fillAtLeastOneField;
          });
          return false;
        }
        return true;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: modalWidth,
          constraints: BoxConstraints(
            maxWidth: modalWidth,
            maxHeight: 800,
          ),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFFA000),
                      Color(0xFFFF5722),
                    ],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isRequired
                            ? localizations.completeProfile
                            : localizations.profileSettings,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed:
                          (widget.isRequired && !_isFormValid) || isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isRequired) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.orange.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  localizations.completeProfileInfo,
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (generalError != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  generalError!,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Center(
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 60,
                                  backgroundColor: avatarColor,
                                  backgroundImage: hasPhoto
                                      ? MemoryImage(avatarBytes!)
                                      : null,
                                  child: hasPhoto
                                      ? null
                                      : const Icon(Icons.person_rounded,
                                          size: 70, color: Colors.white),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: IconButton(
                                      onPressed: isSaving ? null : pickAvatar,
                                      icon: const Icon(Icons.camera_alt_rounded,
                                          color: Colors.black87),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 44, minHeight: 44),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            IconButton(
                              onPressed:
                                  hasPhoto || isSaving ? null : showColorPicker,
                              icon: Icon(
                                Icons.palette_outlined,
                                size: 28,
                                color: hasPhoto
                                    ? theme.disabledColor
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      buildTextField(
                        localizations.name,
                        nameController,
                        maxLength: 50,
                        onChanged: _onNameChanged,
                      ),
                      const SizedBox(height: 24),
                      buildNicknameField(localizations.nickname),
                      const SizedBox(height: 24),
                      buildEmailField('Email'),
                      const SizedBox(height: 24),
                      buildDateField(localizations.birthday),
                      const SizedBox(height: 24),
                      buildGenderField(localizations.gender),
                      const SizedBox(height: 40),
                      if (!widget.isRequired) ...[
                        Text(
                          localizations.privacySettings,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 20),
                        SwitchListTile(
                          title: Text(localizations.blockCalls),
                          value: blockCalls,
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setState(() {
                                    blockCalls = value;
                                  });
                                },
                          activeColor: theme.colorScheme.primary,
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          title: Text(localizations.blockVoiceMessages),
                          value: blockVoice,
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setState(() {
                                    blockVoice = value;
                                  });
                                },
                          activeColor: theme.colorScheme.primary,
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          title: Text(localizations.blockGroups),
                          value: blockGroups,
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setState(() {
                                    blockGroups = value;
                                  });
                                },
                          activeColor: theme.colorScheme.primary,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Row(
                  children: [
                    if (!widget.isRequired)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(localizations.cancel),
                        ),
                      ),
                    if (!widget.isRequired) const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (!_isFormValid || isSaving) ? null : onSave,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: (!_isFormValid || isSaving) ? 0 : 2,
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Text(
                                widget.isRequired
                                    ? localizations.continueText
                                    : localizations.save,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showProfileViewModal(
  BuildContext context, {
  String name = '',
  String nickname = '',
  String email = '',
  DateTime? birthday,
  Gender? gender,
  Uint8List? avatarBytes,
  Color avatarColor = Colors.blue,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => MultiProvider(
      providers: [
        // ✅ Передаём ApiService и другие провайдеры в модальное окно
        Provider<ApiService>.value(
            value: Provider.of<ApiService>(context, listen: false)),
        ChangeNotifierProvider<ProfileProvider>.value(
            value: Provider.of<ProfileProvider>(context, listen: false)),
        ChangeNotifierProvider<AuthProvider>.value(
            value: Provider.of<AuthProvider>(context, listen: false)),
        ChangeNotifierProvider<ThemeProvider>.value(
            value: Provider.of<ThemeProvider>(context, listen: false)),
      ],
      child: const ProfileViewModal(),
    ),
  );
}

Future<void> showProfileSettingsModal(
  BuildContext context, {
  String? initialEmail,
  bool isRequired = false,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: !isRequired,
    builder: (_) => MultiProvider(
      providers: [
        // ✅ Передаём ApiService и другие провайдеры в модальное окно
        Provider<ApiService>.value(
            value: Provider.of<ApiService>(context, listen: false)),
        ChangeNotifierProvider<ProfileProvider>.value(
            value: Provider.of<ProfileProvider>(context, listen: false)),
        ChangeNotifierProvider<AuthProvider>.value(
            value: Provider.of<AuthProvider>(context, listen: false)),
        ChangeNotifierProvider<ThemeProvider>.value(
            value: Provider.of<ThemeProvider>(context, listen: false)),
      ],
      child: ProfileSettingsModal(
        initialEmail: initialEmail,
        isRequired: isRequired,
      ),
    ),
  );
}
