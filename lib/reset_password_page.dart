// reset_password_page.dart
import 'package:flutter/material.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'utils/platform_utils.dart'; // Добавлен импорт
import 'widgets/adaptive_logo.dart';

class ResetPasswordPage extends StatefulWidget {
  final String baseUrl;
  final VoidCallback? onLoginPressed;

  const ResetPasswordPage({
    super.key,
    required this.baseUrl,
    this.onLoginPressed,
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _loading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _emailError;
  String? _codeError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _generalError;

  bool _emailSent = false;
  bool _codeVerified = false;

  late final AnimationController _animationController;

  int _resendTimer = 60;
  Timer? _resendCodeTimer;
  bool _canResendCode = false;

  static const Color primaryColor = Color(0xFF4CAF50);
  static const Color primaryDarkColor = Color(0xFF388E3C);
  static const Color primaryLightColor = Color(0xFFA5D6A7);
  static const Color secondaryColor = Color(0xFFFFA500);
  static const Color backgroundColor = Color(0xFFFFFFFF);
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color linkColor = Color(0xFF1976D2);
  static const Color textColor = Color(0xFF333333);
  static const Color lightTextColor = Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    _resendCodeTimer?.cancel();
    super.dispose();
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

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    if (email.isEmpty) {
      setState(() {
        _emailError = AppLocalizations.of(context)!.emailRequired;
      });
      return;
    } else if (!emailRegex.hasMatch(email)) {
      setState(() {
        _emailError = AppLocalizations.of(context)!.invalidEmail;
      });
      return;
    }

    setState(() {
      _loading = true;
      _emailError = null;
      _generalError = null;
    });

    try {
      final url = Uri.parse('${widget.baseUrl}/api/reset-password');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 30));

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;

      setState(() {
        if (response.statusCode == 200 && data['success'] == true) {
          _emailSent = true;
          _emailError = null;
          _generalError = null;
        } else {
          _emailError = data['error']?.toString() ??
              AppLocalizations.of(context)!.userNotFound;
        }
      });

      if (_emailSent) {
        _startResendTimer();
      }
    } catch (e) {
      setState(() => _generalError =
          AppLocalizations.of(context)!.sendingError(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    final email = _emailController.text.trim();

    if (code.isEmpty) {
      setState(() {
        _codeError = AppLocalizations.of(context)!.codeRequired;
      });
      return;
    }

    if (code.length != 4) {
      setState(() {
        _codeError = AppLocalizations.of(context)!.invalidCode;
      });
      return;
    }

    if (email.isEmpty) {
      setState(() {
        _codeError = AppLocalizations.of(context)!.emailRequired;
      });
      return;
    }

    setState(() {
      _loading = true;
      _codeError = null;
      _generalError = null;
    });

    try {
      final url = Uri.parse('${widget.baseUrl}/api/verify-reset-code');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'email': email,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;

      setState(() {
        if (response.statusCode == 200 && data['success'] == true) {
          _codeVerified = true;
          _codeError = null;
          _generalError = null;
          _resendCodeTimer?.cancel();
        } else {
          _codeError = data['error']?.toString() ??
              AppLocalizations.of(context)!.wrongCode;
        }
      });
    } catch (e) {
      setState(() => _generalError =
          AppLocalizations.of(context)!.verificationError(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmNewPassword() async {
    final code = _codeController.text.trim();
    final email = _emailController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    final passwordLatinRegex =
        RegExp(r'^[A-Za-z0-9!@#$%^&*()_+\-=\[\]{};:"\\|,.<>\/?]+$');
    final passwordUppercaseRegex = RegExp(r'[A-Z]');
    final passwordDigitRegex = RegExp(r'\d');

    bool hasError = false;

    // Проверка пароля
    if (newPassword.isEmpty) {
      _passwordError = AppLocalizations.of(context)!.enterPassword;
      hasError = true;
    } else if (newPassword.length < 10) {
      _passwordError = AppLocalizations.of(context)!.passwordMinLength;
      hasError = true;
    } else if (!passwordUppercaseRegex.hasMatch(newPassword)) {
      _passwordError = AppLocalizations.of(context)!.passwordUppercase;
      hasError = true;
    } else if (!passwordDigitRegex.hasMatch(newPassword)) {
      _passwordError = AppLocalizations.of(context)!.passwordDigit;
      hasError = true;
    } else if (!passwordLatinRegex.hasMatch(newPassword)) {
      _passwordError = AppLocalizations.of(context)!.passwordLatinOnly;
      hasError = true;
    }

    // Проверка подтверждения пароля
    if (confirmPassword.isEmpty) {
      _confirmPasswordError = AppLocalizations.of(context)!.confirmPassword;
      hasError = true;
    } else if (newPassword != confirmPassword) {
      _confirmPasswordError = AppLocalizations.of(context)!.passwordsDoNotMatch;
      hasError = true;
    }

    if (hasError) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _generalError = null;
    });

    try {
      final url = Uri.parse('${widget.baseUrl}/api/confirm-reset');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'email': email,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        if (widget.onLoginPressed != null) {
          widget.onLoginPressed!();
        }
      } else {
        setState(() => _generalError = data['error']?.toString() ??
            AppLocalizations.of(context)!.passwordChangeError);
      }
    } catch (e) {
      setState(() => _generalError = AppLocalizations.of(context)!
          .passwordChangeErrorDetailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  ButtonStyle _primaryButtonStyle() {
    return ButtonStyle(
      backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
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

  Widget _buildFormContent() {
    final l10n = AppLocalizations.of(context)!;

    if (!_emailSent && !_codeVerified) {
      return Column(
        key: const ValueKey('emailForm'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.passwordRecoveryEmailPrompt,
            style: TextStyle(
              fontSize: 14,
              color: lightTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              hintText: l10n.email,
              hintStyle: const TextStyle(color: lightTextColor),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            style: const TextStyle(color: textColor),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _sendResetEmail,
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
                    l10n.sendCode,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      );
    }

    if (_emailSent && !_codeVerified) {
      return Column(
        key: const ValueKey('codeForm'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.enterCode,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
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
                    l10n.codeSent(_emailController.text),
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
            controller: _codeController,
            decoration: InputDecoration(
              hintText: l10n.code,
              hintStyle: const TextStyle(color: lightTextColor),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              errorText: _codeError,
              errorMaxLines: 2,
              errorStyle: const TextStyle(color: errorColor),
            ),
            keyboardType: TextInputType.number,
            maxLength: 4,
            buildCounter: (context,
                    {required currentLength, required isFocused, maxLength}) =>
                null,
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
                    l10n.confirmCode,
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
                '${l10n.didNotReceive} ',
                style: TextStyle(color: lightTextColor),
              ),
              TextButton(
                onPressed: _canResendCode ? _sendResetEmail : null,
                style: _textButtonStyle().copyWith(
                  foregroundColor:
                      MaterialStateProperty.resolveWith<Color>((states) {
                    if (states.contains(MaterialState.disabled))
                      return lightTextColor;
                    return linkColor;
                  }),
                ),
                child: Text(
                  l10n.sendNewCode,
                ),
              ),
              if (!_canResendCode) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: lightTextColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$_resendTimer ${l10n.seconds}',
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
      );
    }

    return Column(
      key: const ValueKey('passwordForm'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.createNewPassword,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
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
                  l10n.codeVerified,
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
          controller: _newPasswordController,
          obscureText: _obscureNewPassword,
          decoration: InputDecoration(
            hintText: l10n.newPassword,
            hintStyle: const TextStyle(color: lightTextColor),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                color: lightTextColor,
              ),
              onPressed: () {
                setState(() {
                  _obscureNewPassword = !_obscureNewPassword;
                });
              },
            ),
          ),
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: textColor),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            hintText: l10n.confirmPassword,
            hintStyle: const TextStyle(color: lightTextColor),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
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
          onSubmitted: (_) => _confirmNewPassword(),
          style: const TextStyle(color: textColor),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _loading ? null : _confirmNewPassword,
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
                  l10n.savePassword,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
                    height: 180,
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
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: secondaryColor,
                          ),
                          animation: _animationController,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildFormContent(),
                  ),
                  const SizedBox(height: 8),
                  if (_generalError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: errorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: errorColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          _generalError!,
                          style: TextStyle(color: errorColor, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            Navigator.pop(context);
                          },
                    style: _textButtonStyle(),
                    child: Text(
                      l10n.backToLogin,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
