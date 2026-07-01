import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'reset_password_page.dart';

class AuthPage extends StatefulWidget {
  final Function(String token) onLogin;
  final bool useProduction; // новая опция для выбора сервера

  const AuthPage({
    super.key,
    required this.onLogin,
    this.useProduction = true, // по умолчанию используем реальный сервер
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  late final String baseUrl;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  String? _generalError;
  int _remainingAttempts = 5;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();

    // Автоматическое определение baseUrl
    if (widget.useProduction) {
      baseUrl = 'http://localhost:3000';
    } else {
      if (kIsWeb) {
        baseUrl = 'http://localhost:3000';
      } else if (Platform.isAndroid) {
        baseUrl = 'http://10.0.2.2:3000';
      } else {
        baseUrl = 'http://localhost:3000';
      }
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_remainingAttempts <= 0) return;

    setState(() {
      _loading = true;
      _emailError = null;
      _passwordError = null;
      _generalError = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    final passwordLatinRegex = RegExp(r'^[A-Za-z0-9]+$');
    final passwordUppercaseRegex = RegExp(r'[A-Z]');
    final passwordDigitRegex = RegExp(r'\d');

    bool hasError = false;

    if (email.isEmpty) {
      _emailError = 'Введите email';
      hasError = true;
    } else if (!emailRegex.hasMatch(email)) {
      _emailError = 'Введите корректный адрес электронной почты';
      hasError = true;
    }

    if (password.isEmpty) {
      _passwordError = 'Введите пароль';
      hasError = true;
    } else if (!_isLogin) {
      if (password.length < 10) {
        _passwordError = 'Пароль должен содержать минимум 10 символов';
        hasError = true;
      } else if (!passwordUppercaseRegex.hasMatch(password)) {
        _passwordError = 'Пароль должен содержать хотя бы одну заглавную букву';
        hasError = true;
      } else if (!passwordDigitRegex.hasMatch(password)) {
        _passwordError = 'Пароль должен содержать хотя бы одну цифру';
        hasError = true;
      } else if (!passwordLatinRegex.hasMatch(password)) {
        _passwordError = 'Пароль должен состоять только из латинских букв и цифр';
        hasError = true;
      }
    }

    if (hasError) {
      setState(() => _loading = false);
      return;
    }

    // ✅ ИЗМЕНЕНО: добавлен префикс /api
    final endpoint = _isLogin ? '/api/login' : '/api/register';
    final url = Uri.parse('$baseUrl$endpoint');

    print('Sending request to: $url');
    print('Body: ${jsonEncode({'email': email, 'password': password})}');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        if (_isLogin) {
          widget.onLogin(data['token']);
        } else {
          setState(() {
            _isLogin = true;
            _generalError = 'Регистрация прошла успешно. Войдите в аккаунт.';
          });
        }
      } else {
        setState(() {
          if (!_isLogin && data['error'] == 'email_exists') {
            _emailError = 'Пользователь с таким email уже зарегистрирован';
          } else if (_isLogin &&
              (response.statusCode == 401 || data['error'] == 'invalid credentials')) {
            _passwordError = 'Неверный пароль. Попробуйте снова.';
            _remainingAttempts -= 1;
            if (_remainingAttempts <= 0) {
              _generalError =
                  'Вы исчерпали все попытки. Попробуйте позже или восстановите доступ.';
            }
          } else {
            _generalError = data['error'] ?? 'Ошибка авторизации';
          }
        });
      }
    } catch (e) {
      setState(() {
        _generalError = 'Ошибка соединения. Проверьте интернет.';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  ButtonStyle _buttonStyle(Color baseColor, Color hoverColor, Color disabledColor) {
    return ButtonStyle(
      backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
        if (states.contains(MaterialState.disabled)) return disabledColor;
        if (states.contains(MaterialState.hovered)) return hoverColor;
        return baseColor;
      }),
      minimumSize: MaterialStateProperty.all(const Size(double.infinity, 48)),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFFFFCF3);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                SizedBox(
                  height: 250,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/logo.png',
                        height: 190,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 1),
                      AnimatedLightText(
                        text: 'Safer Chat',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFA500),
                        ),
                        animation: _animationController,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    hintText: 'Email',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _emailError,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                if (_remainingAttempts > 0)
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: _isLogin ? 'Пароль' : 'Придумайте пароль',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      errorText: _passwordError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (_generalError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _generalError!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_remainingAttempts > 0)
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: _buttonStyle(
                      Colors.green.shade200,
                      Colors.green.shade400,
                      Colors.green.shade100,
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isLogin ? 'Войти' : 'Зарегистрироваться'),
                  ),
                const SizedBox(height: 12),
                if (_remainingAttempts > 0)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _emailError = null;
                        _passwordError = null;
                        _generalError = null;
                      });
                    },
                    child: Text(
                      _isLogin
                          ? 'Нет аккаунта? Зарегистрироваться'
                          : 'Уже есть аккаунт? Войти',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                if (_remainingAttempts <= 0)
                  ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () {
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
                                      _emailController.clear();
                                      _passwordController.clear();
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                    style: _buttonStyle(
                      Colors.orange.shade200,
                      Colors.orange.shade400,
                      Colors.orange.shade100,
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Восстановить доступ'),
                  ),
              ],
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