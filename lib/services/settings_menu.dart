import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/font_scale_provider.dart';
import '../providers/language_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import 'profile_modal.dart';
import '../providers/profile_provider.dart';
import '../models/profile_models.dart';
import 'invite_modal.dart';
import '../utils/platform_utils.dart';

class SettingsMenu extends StatefulWidget {
  final VoidCallback? onBackToMainMenu;

  const SettingsMenu({Key? key, this.onBackToMainMenu}) : super(key: key);

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  Timer? _debounceTimer;
  double _tempScale = 1.0;
  bool _isSliding = false;
  bool _showLanguageExpanded = false;
  bool _showAboutExpanded = false;
  String _selectedLanguageDisplay = '';
  bool _isSupportSent = false;
  bool _isSending = false;
  String _ticketNumber = '';

  final Map<String, String> _languages = {
    'ru': 'Русский',
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'zh': '中文',
    'ko': '한국어',
    'it': 'Italiano',
    'ja': '日本語',
    'hi': 'हिन्दी',
    'ar': 'العربية',
    'he': 'עִברִית',
  };

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _problemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  void _loadCurrentLanguage() {
    final languageProvider =
        Provider.of<LanguageProvider>(context, listen: false);
    final currentLangCode = languageProvider.currentLocale.languageCode;
    final displayName =
        _languages[currentLangCode] ?? currentLangCode.toUpperCase();
    if (mounted) {
      setState(() {
        _selectedLanguageDisplay = displayName;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCurrentLanguage();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _problemController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _sendSupportTicket({
    required String name,
    required String message,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:3004/api/support-ticket'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'name': name,
          'message': message,
        }),
      );

      final responseData = json.decode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        return responseData;
      } else {
        return {
          'success': false,
          'error': responseData['error'] ?? 'Неизвестная ошибка',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  void _onScaleChanged(double value, FontScaleProvider provider) {
    _tempScale = value;
    _isSliding = true;
    setState(() {});

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      provider.setFontSizeScale(value);
      _isSliding = false;
      if (mounted) setState(() {});
    });
  }

  void _showPrivacyPolicy() {
    final appLocalizations = AppLocalizations.of(context);
    _showModalDialog(
      appLocalizations?.privacyPolicy ?? 'Политика конфиденциальности',
      appLocalizations?.privacyPolicyContent ??
          'Текст политики конфиденциальности будет здесь...',
    );
  }

  void _showTermsOfService() {
    final appLocalizations = AppLocalizations.of(context);
    _showModalDialog(
      appLocalizations?.termsOfService ?? 'Пользовательское соглашение',
      appLocalizations?.termsOfServiceContent ??
          'Текст пользовательского соглашения будет здесь...',
    );
  }

  void _showSupportDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final appLocalizations = AppLocalizations.of(context)!;
    final isDarkMode = themeProvider.isDarkMode;

    if (authProvider.token == null || authProvider.userEmail == null) {
      _showErrorDialog(appLocalizations.errorAuthRequired);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Заголовок с градиентом
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
                            'Обращение в поддержку',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            if (!_isSending) {
                              Navigator.of(context).pop();
                            }
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  // Контент
                  Expanded(
                    child: _isSupportSent
                        ? Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF4CAF50),
                                  size: 70,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Обращение принято',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Ответ поступит в ближайшее время',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Colors.grey[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 25),
                                Text(
                                  'С уважением,\nкоманда Safer Chat ❤️',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDarkMode
                                        ? Colors.white60
                                        : Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appLocalizations.nameField,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode
                                        ? Colors.white
                                        : const Color(0xFF424242),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _nameController,
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: appLocalizations.nameHint,
                                    hintStyle: TextStyle(
                                      color: isDarkMode
                                          ? Colors.white54
                                          : Colors.grey[500],
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: isDarkMode
                                            ? const Color(0xFF444444)
                                            : Colors.grey[300]!,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFFF9800),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: isDarkMode
                                            ? const Color(0xFF444444)
                                            : Colors.grey[300]!,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: isDarkMode
                                        ? const Color(0xFF2D2D2D)
                                        : Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  appLocalizations.problemField,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode
                                        ? Colors.white
                                        : const Color(0xFF424242),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 120,
                                  child: TextField(
                                    controller: _problemController,
                                    style: TextStyle(
                                      color: isDarkMode
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical: TextAlignVertical.top,
                                    decoration: InputDecoration(
                                      hintText: appLocalizations.problemHint,
                                      hintStyle: TextStyle(
                                        color: isDarkMode
                                            ? Colors.white54
                                            : Colors.grey[500],
                                      ),
                                      contentPadding: const EdgeInsets.all(12),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: isDarkMode
                                              ? const Color(0xFF444444)
                                              : Colors.grey[300]!,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFFF9800),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: isDarkMode
                                              ? const Color(0xFF444444)
                                              : Colors.grey[300]!,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: isDarkMode
                                          ? const Color(0xFF2D2D2D)
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  // Кнопки
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: _isSupportSent
                        ? SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                setState(() {
                                  _isSupportSent = false;
                                  _ticketNumber = '';
                                  _nameController.clear();
                                  _problemController.clear();
                                  _isSending = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF9800),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                appLocalizations.close,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSending
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: BorderSide(
                                      color: _isSending
                                          ? (isDarkMode
                                              ? Colors.white30
                                              : Colors.grey[400]!)
                                          : const Color(0xFFFF9800),
                                    ),
                                  ),
                                  child: Text(
                                    appLocalizations.cancel,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: _isSending
                                          ? (isDarkMode
                                              ? Colors.white30
                                              : Colors.grey[400])
                                          : const Color(0xFFFF9800),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isSending
                                      ? null
                                      : () async {
                                          if (_nameController.text
                                                  .trim()
                                                  .isNotEmpty &&
                                              _problemController.text
                                                  .trim()
                                                  .isNotEmpty) {
                                            setState(() {
                                              _isSending = true;
                                            });

                                            try {
                                              final response =
                                                  await _sendSupportTicket(
                                                name:
                                                    _nameController.text.trim(),
                                                message: _problemController.text
                                                    .trim(),
                                                token: authProvider.token!,
                                              );

                                              if (response['success'] == true) {
                                                setState(() {
                                                  _isSupportSent = true;
                                                  _ticketNumber = response[
                                                          'ticketNumber'] ??
                                                      '';
                                                  _isSending = false;
                                                });
                                              } else {
                                                _showErrorDialog(
                                                    response['error'] ??
                                                        appLocalizations
                                                            .errorUnknown);
                                                setState(() {
                                                  _isSending = false;
                                                });
                                              }
                                            } catch (e) {
                                              _showErrorDialog(
                                                  '${appLocalizations.errorNetwork}: $e');
                                              setState(() {
                                                _isSending = false;
                                              });
                                            }
                                          } else {
                                            _showErrorDialog(appLocalizations
                                                .errorFillAllFields);
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isSending
                                        ? const Color(0xFFFF9800)
                                            .withOpacity(0.5)
                                        : const Color(0xFFFF9800),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                  child: _isSending
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          appLocalizations.send,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showErrorDialog(String message) {
    final appLocalizations = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appLocalizations.error),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(appLocalizations.ok),
          ),
        ],
      ),
    );
  }

  void _showModalDialog(String title, String content) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final appLocalizations = AppLocalizations.of(context)!;
    final isDarkMode = themeProvider.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
        backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: isDarkMode ? Colors.white70 : Colors.grey[700],
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDarkMode ? const Color(0xFF444444) : Colors.grey[300],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.white70 : Colors.grey[700],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9800),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      appLocalizations.close,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeAppLanguage(
      String languageCode, String displayName) async {
    final languageProvider =
        Provider.of<LanguageProvider>(context, listen: false);
    await languageProvider.setLanguage(languageCode);
    setState(() {
      _selectedLanguageDisplay = displayName;
      _showLanguageExpanded = false;
    });
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;

    return Material(
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * fontSizeScale,
            vertical: 14 * fontSizeScale,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFFFF9800),
                size: 24 * fontSizeScale,
              ),
              SizedBox(width: 16 * fontSizeScale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16 * fontSizeScale,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (subtitle != null) SizedBox(height: 2 * fontSizeScale),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14 * fontSizeScale,
                          color: isDarkMode ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
              if (trailing == null)
                Icon(
                  Icons.chevron_right,
                  color: isDarkMode ? Colors.white70 : Colors.grey,
                  size: 20 * fontSizeScale,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required String languageCode,
    required String languageName,
    required bool isSelected,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;

    return Material(
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: InkWell(
        onTap: () {
          _changeAppLanguage(languageCode, languageName);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 56 * fontSizeScale,
            vertical: 12 * fontSizeScale,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  languageName,
                  style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: isSelected
                        ? const Color(0xFFFF9800)
                        : (isDarkMode ? Colors.white : Colors.black87),
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check,
                  color: const Color(0xFFFF9800),
                  size: 20 * fontSizeScale,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;

    return Material(
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 56 * fontSizeScale,
            vertical: 12 * fontSizeScale,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFFFF9800),
                size: 20 * fontSizeScale,
              ),
              SizedBox(width: 12 * fontSizeScale),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeatureDialog(String feature) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final appLocalizations = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Text(
          feature,
          style: TextStyle(fontSize: 18 * fontSizeScale),
        ),
        content: Text(
          appLocalizations.featureInDevelopment(feature),
          style: TextStyle(fontSize: 15 * fontSizeScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              appLocalizations.ok,
              style: TextStyle(
                fontSize: 16 * fontSizeScale,
                color: const Color(0xFFFF9800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _getLocalizedLanguages() {
    return _languages;
  }

  Widget _buildThemeMenuItem() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;
    final appLocalizations = AppLocalizations.of(context);

    return Material(
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: InkWell(
        onTap: () {
          themeProvider.toggleTheme();
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * fontSizeScale,
            vertical: 14 * fontSizeScale,
          ),
          child: Row(
            children: [
              Icon(
                isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: const Color(0xFFFF9800),
                size: 24 * fontSizeScale,
              ),
              SizedBox(width: 16 * fontSizeScale),
              Expanded(
                child: Text(
                  isDarkMode
                      ? appLocalizations?.darkMode ?? 'Ночной режим'
                      : appLocalizations?.lightMode ?? 'Дневной режим',
                  style: TextStyle(
                    fontSize: 16 * fontSizeScale,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Switch(
                value: isDarkMode,
                onChanged: (value) {
                  themeProvider.toggleTheme();
                },
                activeColor: const Color(0xFFFF9800),
                activeTrackColor: const Color(0xFFFF9800).withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScaleMenuItem() {
    final fontScaleProvider = Provider.of<FontScaleProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale = fontScaleProvider.fontSizeScale;
    final isDarkMode = themeProvider.isDarkMode;

    if (!_isSliding) {
      _tempScale = fontSizeScale;
    }

    return Material(
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * fontSizeScale,
          vertical: 14 * fontSizeScale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.zoom_in_outlined,
                  color: const Color(0xFFFF9800),
                  size: 24 * fontSizeScale,
                ),
                SizedBox(width: 16 * fontSizeScale),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.interfaceScale ?? 'Масштаб ',
                    style: TextStyle(
                      fontSize: 16 * fontSizeScale,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12 * fontSizeScale),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4 * fontSizeScale,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: 12 * fontSizeScale,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 0,
                ),
                activeTrackColor: const Color(0xFFFF9800),
                inactiveTrackColor:
                    isDarkMode ? const Color(0xFF444444) : Colors.grey[300],
                thumbColor: const Color(0xFFFF9800),
                overlayColor: Colors.transparent,
              ),
              child: Slider(
                value: _tempScale,
                min: 0.8,
                max: 1.3,
                divisions: null,
                onChanged: (value) {
                  _onScaleChanged(value, fontScaleProvider);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    final profileProvider = Provider.of<ProfileProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final appLocalizations = AppLocalizations.of(context);
    final localizedLanguages = _getLocalizedLanguages();

    if (_selectedLanguageDisplay.isEmpty) {
      final currentLangCode =
          Provider.of<LanguageProvider>(context).currentLocale.languageCode;
      _selectedLanguageDisplay =
          localizedLanguages[currentLangCode] ?? currentLangCode.toUpperCase();
    }

    // Определяем отображаемое имя
    String displayName =
        profileProvider.nickname ?? profileProvider.name ?? 'User';
    if (displayName.startsWith('@')) {
      displayName = displayName;
    } else if (profileProvider.nickname != null &&
        profileProvider.nickname!.isNotEmpty) {
      displayName = '@${profileProvider.nickname}';
    }

    return Container(
      color: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      child: Column(
        children: [
          // Шапка с именем пользователя и кнопкой назад
          Container(
            height: 140,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFA000),
                  Color(0xFFFF5722),
                ],
              ),
            ),
            padding:
                const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 20),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: profileProvider.avatarBytes != null
                          ? Colors.transparent
                          : profileProvider.avatarColor,
                      backgroundImage: profileProvider.avatarBytes != null
                          ? MemoryImage(profileProvider.avatarBytes!)
                          : null,
                      child: profileProvider.avatarBytes == null
                          ? const Icon(Icons.person_rounded,
                              size: 36, color: Colors.white)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Кнопка возврата в главное меню
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: widget.onBackToMainMenu,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Назад в меню',
                ),
              ],
            ),
          ),

          // Список настроек
          Expanded(
            child: ListView(
              shrinkWrap: true,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  icon: Icons.person_outline,
                  title: appLocalizations?.profile ?? 'Профиль',
                  onTap: () async {
                    Navigator.of(context).pop();

                    // ✅ Обновляем профиль с сервера перед показом
                    final profileProvider =
                        Provider.of<ProfileProvider>(context, listen: false);
                    final authProvider =
                        Provider.of<AuthProvider>(context, listen: false);

                    try {
                      await profileProvider
                          .loadProfileFromServer(authProvider.token ?? '');
                    } catch (e) {
                      print('❌ Ошибка загрузки профиля: $e');
                    }

                    showProfileViewModal(
                      context,
                      name: profileProvider.name ?? '',
                      nickname: profileProvider.nickname ?? '',
                      birthday: profileProvider.birthday,
                      gender: profileProvider.gender,
                      avatarBytes: profileProvider.avatarBytes,
                      avatarColor: profileProvider.avatarColor,
                    );
                  },
                ),
                Column(
                  children: [
                    _buildMenuItem(
                      icon: Icons.language_outlined,
                      title: appLocalizations?.language ?? 'Язык',
                      subtitle: _selectedLanguageDisplay,
                      trailing: Icon(
                        _showLanguageExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: isDarkMode ? Colors.white70 : Colors.grey,
                        size: 20 * fontSizeScale,
                      ),
                      onTap: () {
                        setState(() {
                          _showLanguageExpanded = !_showLanguageExpanded;
                        });
                      },
                    ),
                    if (_showLanguageExpanded)
                      ...localizedLanguages.entries.map((entry) {
                        final languageCode = entry.key;
                        final languageName = entry.value;
                        return _buildLanguageOption(
                          languageCode: languageCode,
                          languageName: languageName,
                          isSelected: _selectedLanguageDisplay == languageName,
                        );
                      }).toList(),
                  ],
                ),
                // Пункт "Настройки чата" удалён
                _buildThemeMenuItem(),
                _buildScaleMenuItem(),
                Column(
                  children: [
                    _buildMenuItem(
                      icon: Icons.info_outlined,
                      title: appLocalizations?.aboutApp ?? 'О приложении',
                      trailing: Icon(
                        _showAboutExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: isDarkMode ? Colors.white70 : Colors.grey,
                        size: 20 * fontSizeScale,
                      ),
                      onTap: () {
                        setState(() {
                          _showAboutExpanded = !_showAboutExpanded;
                        });
                      },
                    ),
                    if (_showAboutExpanded) ...[
                      _buildAboutOption(
                        icon: Icons.privacy_tip,
                        title: appLocalizations?.privacyPolicy ??
                            'Политика конфиденциальности',
                        onTap: _showPrivacyPolicy,
                      ),
                      _buildAboutOption(
                        icon: Icons.description,
                        title: appLocalizations?.termsOfService ??
                            'Пользовательское соглашение',
                        onTap: _showTermsOfService,
                      ),
                    ],
                  ],
                ),
                _buildMenuItem(
                  icon: Icons.support_agent,
                  title:
                      appLocalizations?.supportTitle ?? 'Обращение в поддержку',
                  onTap: _showSupportDialog,
                ),
                Padding(
                  padding: EdgeInsets.only(
                      top: 24 * fontSizeScale, bottom: 16 * fontSizeScale),
                  child: Center(
                    child: Text(
                      '${appLocalizations?.version ?? 'Версия'} 1.0.0',
                      style: TextStyle(
                        fontSize: 14 * fontSizeScale,
                        color: isDarkMode ? Colors.white70 : Colors.grey,
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 32 * fontSizeScale,
                  color: isDarkMode
                      ? const Color(0xFF121212)
                      : const Color(0xFFF5F5F5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
