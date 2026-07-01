// invite_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import '../providers/theme_provider.dart';
import '../providers/font_scale_provider.dart';
import '../utils/platform_utils.dart'; // Добавлен импорт

class InviteModal extends StatefulWidget {
  final String? inviteLink;

  const InviteModal({
    Key? key,
    this.inviteLink,
  }) : super(key: key);

  @override
  State<InviteModal> createState() => _InviteModalState();
}

class _InviteModalState extends State<InviteModal> {
  bool _isCopied = false;

  // ИСПРАВЛЕНО: Используем PlatformUtils для копирования
  void _copyToClipboard() {
    if (widget.inviteLink != null) {
      PlatformUtils.copyToClipboard(widget.inviteLink!);
      setState(() {
        _isCopied = true;
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isCopied = false;
          });
        }
      });
    }
  }

  void _shareViaMessenger(String messenger) {
    // TODO: Реализовать поделиться через мессенджер
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Поделиться через $messenger будет реализовано'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontScaleProvider = Provider.of<FontScaleProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final fontSizeScale = fontScaleProvider.fontSizeScale;
    final appLocalizations = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    // Генерация дефолтной ссылки, если не передана
    final link = widget.inviteLink ?? 'https://saferchat.app/invite/default';

    // Адаптивная ширина
    double modalWidth;
    if (screenWidth > 1200) {
      modalWidth = 450;
    } else if (screenWidth > 800) {
      modalWidth = 420;
    } else if (screenWidth > 600) {
      modalWidth = screenWidth * 0.7;
    } else {
      modalWidth = screenWidth * 0.9;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
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
                      appLocalizations?.invite ?? 'Пригласить друга',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (22 * fontSizeScale).clamp(18, 26),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Контент
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    // QR код
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: link,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Описание
                    Text(
                      'Поделитесь этой ссылкой или QR-кодом с друзьями',
                      style: TextStyle(
                        fontSize: (16 * fontSizeScale).clamp(14, 18),
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // Ссылка для приглашения
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDarkMode 
                            ? const Color(0xFF2A2A2A) 
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDarkMode 
                              ? const Color(0xFF444444) 
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              link,
                              style: TextStyle(
                                fontSize: (14 * fontSizeScale).clamp(12, 16),
                                color: isDarkMode 
                                    ? Colors.white70 
                                    : Colors.black87,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              _isCopied ? Icons.check : Icons.copy,
                              color: _isCopied 
                                  ? const Color(0xFF4CAF50) 
                                  : const Color(0xFFFF9800),
                              size: 20,
                            ),
                            onPressed: _copyToClipboard,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: appLocalizations?.copyLink ?? 'Копировать ссылку',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Заголовок "Поделиться через"
                    Text(
                      'Поделиться через',
                      style: TextStyle(
                        fontSize: (16 * fontSizeScale).clamp(14, 18),
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Кнопки для поделиться
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildShareButton(
                          icon: Icons.telegram,
                          label: 'Telegram',
                          color: const Color(0xFF0088CC),
                          onTap: () => _shareViaMessenger('Telegram'),
                        ),
                        _buildShareButton(
                          icon: Icons.chat_bubble_outline,
                          label: 'WhatsApp',
                          color: const Color(0xFF25D366),
                          onTap: () => _shareViaMessenger('WhatsApp'),
                        ),
                        _buildShareButton(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          color: const Color(0xFFEA4335),
                          onTap: () => _shareViaMessenger('Email'),
                        ),
                      ],
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

  Widget _buildShareButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontScaleProvider = Provider.of<FontScaleProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final fontSizeScale = fontScaleProvider.fontSizeScale;

    return Column(
      children: [
        Material(
          color: color.withOpacity(0.15),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Icon(
                icon,
                color: color,
                size: (28 * fontSizeScale).clamp(24, 32),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: (13 * fontSizeScale).clamp(11, 15),
            color: isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }
}

void showInviteModal(BuildContext context, {String? inviteLink}) {
  showDialog(
    context: context,
    builder: (context) => InviteModal(inviteLink: inviteLink),
  );
}