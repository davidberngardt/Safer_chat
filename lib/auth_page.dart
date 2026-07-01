// auth_page.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:safer_chat/services/auth_service.dart';
import 'reset_password_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'utils/platform_utils.dart'; // Добавлен импорт
import 'widgets/adaptive_logo.dart';

class AuthPage extends StatefulWidget {
  final Function(String token, {bool isFirstLogin, String? userEmail}) onLogin;
  final bool useProduction;

  const AuthPage({
    super.key,
    required this.onLogin,
    this.useProduction = true,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  late final String baseUrl;
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _verificationCodeController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;

  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _verificationCodeError;
  String? _generalError;

  int _remainingAttempts = 5;
  bool _showAttemptsCounter = false;

  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  final FocusNode _verificationCodeFocusNode = FocusNode();

  bool _isEmailVerificationSent = false;
  int _codeExpiryTime = 0;
  Timer? _codeExpiryTimer;
  bool _isVerificationSuccessful = false;

  int _resendTimer = 60;
  Timer? _resendCodeTimer;
  bool _canResendCode = false;

  late AnimationController _animationController;

  static const Color primaryColor = Color(0xFF4CAF50);
  static const Color primaryDarkColor = Color(0xFF388E3C);
  static const Color primaryLightColor = Color(0xFFA5D6A7);
  static const Color secondaryColor = Color(0xFFFFA500);
  static const Color backgroundColor = Color(0xFFFFFCF3);
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color warningColor = Color(0xFFF57C00);
  static const Color linkColor = Color(0xFF1976D2);
  static const Color textColor = Color(0xFF333333);
  static const Color lightTextColor = Color(0xFF666666);

  // Регулярные выражения для валидации
  static const String _emailPattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
  static const String _passwordPattern = r'^[A-Za-z0-9!@#$%^&*()_+\-=\[\]{};:"\\|,.<>\/?]+$';
  static const String _codePattern = r'^\d{4}$'; // Только 4 цифры
  static const String _alphanumericPattern = r'^[a-zA-Z0-9@._%+-]+$'; // Для email локальной части

  @override
  void initState() {
    super.initState();
    if (widget.useProduction) {
      baseUrl = 'http://localhost:3004';
    } else {
      if (kIsWeb) {
        baseUrl = 'https://test.saferchat.me:3004';
      } else if (Platform.isAndroid) {
        baseUrl = 'https://10.0.2.2:3004';
      } else if (Platform.isIOS) {
        baseUrl = 'http://localhost:3004';
      } else {
        baseUrl = 'http://localhost:3004';
      }
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _checkIfLoggedIn();
  }

  Future<void> _checkIfLoggedIn() async {
    bool isLoggedIn = await _authService.isLoggedIn();
    if (isLoggedIn && mounted) {
      String? token = await _authService.getToken();
      if (token != null) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          widget.onLogin(token, isFirstLogin: false);
        }
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _verificationCodeController.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _verificationCodeFocusNode.dispose();
    _codeExpiryTimer?.cancel();
    _resendCodeTimer?.cancel();
    super.dispose();
  }

  // Санитизация входных данных
  String _sanitizeInput(String input) {
    // Удаляем управляющие символы и лишние пробелы
    return input.trim().replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  }

  // Валидация email
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(_emailPattern);
    if (!emailRegex.hasMatch(email)) return false;
    
    // Проверяем, что локальная часть содержит только допустимые символы
    final localPart = email.split('@')[0];
    final localPartRegex = RegExp(_alphanumericPattern);
    return localPartRegex.hasMatch(localPart);
  }

  // Валидация пароля (безопасность + предотвращение инъекций)
  bool _isValidPassword(String password) {
    if (password.length < 10) return false;
    if (!RegExp(r'[A-Z]').hasMatch(password)) return false;
    if (!RegExp(r'\d').hasMatch(password)) return false;
    if (!RegExp(_passwordPattern).hasMatch(password)) return false;
    return true;
  }

  // Валидация кода подтверждения
  bool _isValidVerificationCode(String code) {
    return RegExp(_codePattern).hasMatch(code);
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

  Future<void> _sendVerificationCode() async {
    final rawEmail = _emailController.text;
    final email = _sanitizeInput(rawEmail);

    if (email.isEmpty) {
      setState(() {
        _emailError = AppLocalizations.of(context)!.enterEmail;
      });
      return;
    } else if (!_isValidEmail(email)) {
      setState(() {
        _emailError = AppLocalizations.of(context)!.enterValidEmail;
      });
      return;
    }

    setState(() {
      _loading = true;
      _emailError = null;
      _generalError = null;
    });

    try {
      final url = Uri.parse('$baseUrl/api/send-verification-code');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email, // Отправляем уже санитизированный email
        }),
      ).timeout(const Duration(seconds: 30));

      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final expiresIn = data['expiresIn'] as int? ?? 300;
        _codeExpiryTime = DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;

        setState(() {
          _isEmailVerificationSent = true;
          _generalError = null;
        });

        _startCodeExpiryTimer();
        _startResendTimer();
      } else {
        setState(() {
          if (data['error'] == 'email_exists') {
            _emailError = AppLocalizations.of(context)!.emailAlreadyRegistered;
          } else {
            _generalError = data['error']?.toString() ?? AppLocalizations.of(context)!.failedToSendCode;
          }
        });
      }
    } catch (e) {
      setState(() {
        _generalError = '${AppLocalizations.of(context)!.codeSendError}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final rawCode = _verificationCodeController.text;
    final code = _sanitizeInput(rawCode);

    if (code.isEmpty) {
      setState(() {
        _verificationCodeError = AppLocalizations.of(context)!.enterVerificationCode;
      });
      return;
    }

    if (!_isValidVerificationCode(code)) {
      setState(() {
        _verificationCodeError = AppLocalizations.of(context)!.codeMustBe4Digits;
      });
      return;
    }

    setState(() {
      _loading = true;
      _verificationCodeError = null;
      _generalError = null;
    });

    try {
      final email = _sanitizeInput(_emailController.text);
      final url = Uri.parse('$baseUrl/api/verify-email-code');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
        }),
      ).timeout(const Duration(seconds: 30));

      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _verificationCodeError = null;
          _isVerificationSuccessful = true;
          _codeExpiryTimer?.cancel();
          _resendCodeTimer?.cancel();
        });
      } else {
        setState(() {
          _verificationCodeError = data['error']?.toString() ?? AppLocalizations.of(context)!.invalidVerificationCode;
        });
      }
    } catch (e) {
      setState(() {
        _verificationCodeError = '${AppLocalizations.of(context)!.codeVerificationError}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _startCodeExpiryTimer() {
    _codeExpiryTimer?.cancel();
    _codeExpiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (currentTime > _codeExpiryTime) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isEmailVerificationSent = false;
            if (!_isVerificationSuccessful) {
              _generalError = AppLocalizations.of(context)!.codeExpired;
            }
          });
        }
      }
    });
  }

  void _resetVerification() {
    setState(() {
      _isEmailVerificationSent = false;
      _isVerificationSuccessful = false;
      _verificationCodeController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _codeExpiryTimer?.cancel();
      _resendCodeTimer?.cancel();
      _canResendCode = false;
      _resendTimer = 60;
    });
  }

  Future<void> _openDocument(String documentType) async {
    final urls = {
      'privacy': 'https://saferchat.me/privacy-policy',
      'terms': 'https://saferchat.me/terms-of-service',
    };

    final url = urls[documentType] ?? 'https://saferchat.me';

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Widget _buildClickableText(String text, String documentType) {
    return GestureDetector(
      onTap: () => _openDocument(documentType),
      child: Text(
        text,
        style: const TextStyle(
          color: linkColor,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Future<void> _submitRegistration() async {
    if (!_isVerificationSuccessful) {
      setState(() {
        _generalError = AppLocalizations.of(context)!.confirmEmailFirst;
      });
      return;
    }

    final rawEmail = _emailController.text;
    final rawPassword = _passwordController.text;
    final rawConfirmPassword = _confirmPasswordController.text;
    final rawCode = _verificationCodeController.text;

    final email = _sanitizeInput(rawEmail);
    final password = _sanitizeInput(rawPassword);
    final confirmPassword = _sanitizeInput(rawConfirmPassword);
    final code = _sanitizeInput(rawCode);

    bool hasError = false;

    // Валидация email
    if (!_isValidEmail(email)) {
      _emailError = AppLocalizations.of(context)!.enterValidEmail;
      hasError = true;
    }

    // Валидация пароля
    if (!_isValidPassword(password)) {
      if (password.length < 10) {
        _passwordError = AppLocalizations.of(context)!.passwordMinLength;
      } else if (!RegExp(r'[A-Z]').hasMatch(password)) {
        _passwordError = AppLocalizations.of(context)!.passwordUppercase;
      } else if (!RegExp(r'\d').hasMatch(password)) {
        _passwordError = AppLocalizations.of(context)!.passwordDigit;
      } else {
        _passwordError = AppLocalizations.of(context)!.passwordInvalid;
      }
      hasError = true;
    }

    // Проверка совпадения паролей
    if (password != confirmPassword) {
      _confirmPasswordError = AppLocalizations.of(context)!.passwordsDoNotMatch;
      hasError = true;
    }

    // Валидация кода
    if (!_isValidVerificationCode(code)) {
      _verificationCodeError = AppLocalizations.of(context)!.codeMustBe4Digits;
      hasError = true;
    }

    if (hasError) {
      setState(() {});
      return;
    }

    setState(() {
      _loading = true;
      _generalError = null;
    });

    final url = Uri.parse('$baseUrl/api/register');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'verificationCode': code,
        }),
      ).timeout(const Duration(seconds: 30));

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception(AppLocalizations.of(context)!.invalidServerResponse);
      }

      if (response.statusCode == 200 && data['success'] == true) {
        final loginResponse = await http.post(
          Uri.parse('$baseUrl/api/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        ).timeout(const Duration(seconds: 30));

        if (loginResponse.statusCode == 200) {
          final loginData = jsonDecode(loginResponse.body) as Map<String, dynamic>;
          if (loginData['success'] == true) {
            final token = loginData['token'] as String;
            await _authService.saveToken(token);
            
            final userEmail = loginData['email'] as String? ?? email;
            widget.onLogin(token, isFirstLogin: true, userEmail: userEmail);
          } else {
            setState(() {
              _isLogin = true;
              _generalError = AppLocalizations.of(context)!.registrationSuccessfulLogin;
            });
          }
        } else {
          setState(() {
            _isLogin = true;
            _generalError = AppLocalizations.of(context)!.registrationSuccessfulLogin;
          });
        }
      } else {
        setState(() {
          if (data['error'] == 'email_exists') {
            _emailError = AppLocalizations.of(context)!.emailAlreadyRegistered;
            _resetVerification();
          } else if (data['error'] == 'invalid_code') {
            _verificationCodeError = AppLocalizations.of(context)!.invalidVerificationCode;
            _resetVerification();
          } else if (data['error'] != null) {
            _generalError = data['error'] as String;
          } else {
            _generalError = '${AppLocalizations.of(context)!.registrationError} (${AppLocalizations.of(context)!.code}: ${response.statusCode})';
          }
        });
      }
    } catch (e) {
      setState(() {
        _generalError = '${AppLocalizations.of(context)!.registrationError}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitLogin() async {
    if (_remainingAttempts <= 0) return;

    final rawEmail = _emailController.text;
    final rawPassword = _passwordController.text;

    final email = _sanitizeInput(rawEmail);
    final password = _sanitizeInput(rawPassword);

    setState(() {
      _loading = true;
      _emailError = null;
      _passwordError = null;
      _generalError = null;
      _showAttemptsCounter = false;
    });

    bool hasError = false;

    if (email.isEmpty) {
      _emailError = AppLocalizations.of(context)!.enterEmail;
      hasError = true;
    } else if (!_isValidEmail(email)) {
      _emailError = AppLocalizations.of(context)!.enterValidEmail;
      hasError = true;
    }

    if (password.isEmpty) {
      _passwordError = AppLocalizations.of(context)!.enterPassword;
      hasError = true;
    } else if (password.length < 10) {
      // Простая проверка длины, но не показываем ошибку для логина
      // Просто предупреждаем
    }

    if (hasError) {
      setState(() => _loading = false);
      return;
    }

    final url = Uri.parse('$baseUrl/api/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 30));

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception(AppLocalizations.of(context)!.invalidServerResponse);
      }

      if (response.statusCode == 200 && data['success'] == true) {
        final token = data['token'] as String;
        await _authService.saveToken(token);
        
        final userEmail = data['email'] as String? ?? email;
        widget.onLogin(token, isFirstLogin: false, userEmail: userEmail);
      } else {
        setState(() {
          if (response.statusCode == 401 || data['error'] == 'invalid credentials') {
            _passwordError = AppLocalizations.of(context)!.incorrectPassword;
            _remainingAttempts -= 1;
            _showAttemptsCounter = true;
            if (_remainingAttempts <= 0) {
              _generalError = AppLocalizations.of(context)!.attemptsExhausted;
            }
          } else if (data['error'] != null) {
            _generalError = data['error'] as String;
            _showAttemptsCounter = false;
          } else {
            _generalError = '${AppLocalizations.of(context)!.authError} (${AppLocalizations.of(context)!.code}: ${response.statusCode})';
            _showAttemptsCounter = false;
          }
        });
      }
    } catch (e) {
      setState(() {
        _generalError = '${AppLocalizations.of(context)!.authError}: $e';
        _showAttemptsCounter = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  ButtonStyle _primaryButtonStyle() {
    return ButtonStyle(
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) return primaryLightColor;
        if (states.contains(MaterialState.hovered)) return primaryDarkColor;
        if (states.contains(MaterialState.pressed)) return primaryDarkColor;
        return primaryColor;
      }),
      foregroundColor: MaterialStateProperty.all(Colors.white),
      minimumSize: MaterialStateProperty.all(const Size(double.infinity, 48)),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevation: MaterialStateProperty.all(2),
      overlayColor: MaterialStateProperty.all(Colors.white.withOpacity(0.1)),
      shadowColor: MaterialStateProperty.all(primaryColor.withOpacity(0.3)),
    );
  }

  ButtonStyle _textButtonStyle() {
    return TextButton.styleFrom(
      foregroundColor: primaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  void _navigateToResetPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResetPasswordPage(
          baseUrl: baseUrl,
          onLoginPressed: () {
            Navigator.pop(context);
            setState(() {
              _remainingAttempts = 5;
              _isLogin = true;
              _generalError = null;
              _showAttemptsCounter = false;
              _resetVerification();
              _emailController.clear();
              _passwordController.clear();
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 250,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const AdaptiveLogo(
                          backgroundColor: backgroundColor,
                          size: LogoSize.medium,
                        ),
                        const SizedBox(height: 1),
                        AnimatedLightText(
                          text: 'Safer Chat',
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: secondaryColor,
                          ),
                          animation: _animationController,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ========== ЭКРАН ВХОДА ==========
                  if (_isLogin) ...[
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: appLocalizations.email,
                        hintStyle: const TextStyle(color: lightTextColor),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryColor, width: 2),
                        ),
                        errorText: _emailError,
                        errorMaxLines: 2,
                        errorStyle: const TextStyle(color: errorColor),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                      style: const TextStyle(color: textColor),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: appLocalizations.password,
                        hintStyle: const TextStyle(color: lightTextColor),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryColor, width: 2),
                        ),
                        errorText: _passwordError,
                        errorMaxLines: 2,
                        errorStyle: const TextStyle(color: errorColor),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: lightTextColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitLogin(),
                      style: const TextStyle(color: textColor),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loading ? null : _submitLogin,
                      style: _primaryButtonStyle(),
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              appLocalizations.login,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading ? null : _navigateToResetPassword,
                      style: _textButtonStyle().copyWith(
                        foregroundColor: MaterialStateProperty.all(linkColor),
                      ),
                      child: Text(
                        appLocalizations.forgotPassword,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],

                  // ========== ЭКРАН ВВОДА EMAIL ДЛЯ РЕГИСТРАЦИИ ==========
                  if (!_isLogin && !_isEmailVerificationSent && !_isVerificationSuccessful) ...[
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: appLocalizations.email,
                        hintStyle: const TextStyle(color: lightTextColor),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryColor, width: 2),
                        ),
                        errorText: _emailError,
                        errorMaxLines: 2,
                        errorStyle: const TextStyle(color: errorColor),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (_agreedToTerms && !_loading) {
                          _sendVerificationCode();
                        }
                      },
                      style: const TextStyle(color: textColor),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _agreedToTerms,
                            onChanged: (bool? value) {
                              setState(() {
                                _agreedToTerms = value ?? false;
                                _generalError = null;
                              });
                            },
                            activeColor: primaryColor,
                            checkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${appLocalizations.agreeWith} ',
                                  style: const TextStyle(color: textColor),
                                ),
                                _buildClickableText(appLocalizations.dataProcessing, 'privacy'),
                                Text(' ${appLocalizations.and} '),
                                _buildClickableText(appLocalizations.termsOfService, 'terms'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: (_loading || !_agreedToTerms) ? null : _sendVerificationCode,
                      style: _primaryButtonStyle(),
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              appLocalizations.getCode,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],

                  // ========== ЭКРАН ВВОДА КОДА ПОДТВЕРЖДЕНИЯ ==========
                  if (!_isLogin && _isEmailVerificationSent && !_isVerificationSuccessful) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: primaryColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.email, color: primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              appLocalizations.codeSentToEmail,
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _verificationCodeController,
                      focusNode: _verificationCodeFocusNode,
                      decoration: InputDecoration(
                        hintText: null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryColor, width: 2),
                        ),
                        errorText: _verificationCodeError,
                        errorMaxLines: 2,
                        errorStyle: const TextStyle(color: errorColor),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        color: textColor,
                        fontSize: 18,
                        letterSpacing: 8,
                      ),
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _verifyCode(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loading ? null : _verifyCode,
                      style: _primaryButtonStyle(),
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              appLocalizations.verifyCode,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${appLocalizations.didntReceiveCode} ',
                          style: TextStyle(color: lightTextColor),
                        ),
                        TextButton(
                          onPressed: _canResendCode ? _sendVerificationCode : null,
                          style: _textButtonStyle().copyWith(
                            foregroundColor: MaterialStateProperty.resolveWith((states) {
                              if (states.contains(MaterialState.disabled)) return lightTextColor;
                              return linkColor;
                            }),
                          ),
                          child: Text(
                            appLocalizations.sendNewCode,
                          ),
                        ),
                        if (!_canResendCode) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: lightTextColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$_resendTimer ${appLocalizations.seconds}',
                              style: TextStyle(
                                color: lightTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // ========== ЭКРАН ВВОДА ПАРОЛЯ ==========
                  if (!_isLogin && _isVerificationSuccessful) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: primaryColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              appLocalizations.emailVerified,
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: appLocalizations.createPassword,
                        hintStyle: const TextStyle(color: lightTextColor),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryColor, width: 2),
                        ),
                        errorText: _passwordError,
                        errorMaxLines: 2,
                        errorStyle: const TextStyle(color: errorColor),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: lightTextColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _confirmPasswordFocusNode.requestFocus(),
                      style: const TextStyle(color: textColor),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      focusNode: _confirmPasswordFocusNode,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        hintText: appLocalizations.repeatPassword,
                        hintStyle: const TextStyle(color: lightTextColor),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryColor, width: 2),
                        ),
                        errorText: _confirmPasswordError,
                        errorMaxLines: 2,
                        errorStyle: const TextStyle(color: errorColor),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                            color: lightTextColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitRegistration(),
                      style: const TextStyle(color: textColor),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loading ? null : _submitRegistration,
                      style: _primaryButtonStyle(),
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              appLocalizations.completeRegistration,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  if (_generalError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: errorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: errorColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          _generalError!,
                          style: TextStyle(color: errorColor, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  if (!_isVerificationSuccessful) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _isLogin = !_isLogin;
                                _emailError = null;
                                _passwordError = null;
                                _confirmPasswordError = null;
                                _verificationCodeError = null;
                                _generalError = null;
                                _showAttemptsCounter = false;
                                _agreedToTerms = false;
                                _resetVerification();
                                _passwordController.clear();
                                _confirmPasswordController.clear();
                                _verificationCodeController.clear();
                              });
                            },
                      style: _textButtonStyle(),
                      child: Text(
                        _isLogin
                            ? appLocalizations.noAccountRegister
                            : appLocalizations.alreadyHaveAccountLogin,
                      ),
                    ),
                  ],

                  if (_remainingAttempts > 0 && _isLogin && _showAttemptsCounter)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${appLocalizations.attemptsLeft}: $_remainingAttempts',
                        style: TextStyle(
                          color: _remainingAttempts <= 2 ? warningColor : lightTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ),

                  if (_remainingAttempts <= 0) ...[
                    const SizedBox(height: 16),
                    Text(
                      appLocalizations.accessTemporarilyBlocked,
                      style: TextStyle(
                        color: warningColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appLocalizations.tooManyFailedAttempts,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loading ? null : _navigateToResetPassword,
                      style: _primaryButtonStyle().copyWith(
                        backgroundColor: MaterialStateProperty.resolveWith((states) {
                          if (states.contains(MaterialState.disabled)) return warningColor.withOpacity(0.5);
                          if (states.contains(MaterialState.hovered)) return warningColor.withOpacity(0.8);
                          if (states.contains(MaterialState.pressed)) return warningColor.withOpacity(0.8);
                          return warningColor;
                        }),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              appLocalizations.recoverAccess,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =======================
// AnimatedLightText
// =======================
class AnimatedLightText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Animation<double> animation;

  const AnimatedLightText({
    super.key,
    required this.text,
    required this.style,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final width = bounds.width;
            final height = bounds.height;
            final gradient = LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withOpacity(0.02),
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.65),
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.02),
                Colors.transparent,
              ],
              stops: const [0.0, 0.1, 0.45, 0.5, 0.55, 0.9, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              tileMode: TileMode.clamp,
            );

            final gradientWidth = width * 3;
            final gradientHeight = height * 3;
            final offsetX = (gradientWidth - width) * animation.value;
            final offsetY = (gradientHeight - height) * animation.value;

            return gradient.createShader(
              Rect.fromLTWH(-offsetX, -offsetY, gradientWidth, gradientHeight),
            );
          },
          blendMode: BlendMode.lighten,
          child: Text(
            text,
            style: style,
            maxLines: 1,
          ),
        );
      },
    );
  }
}