import 'package:flutter/material.dart';

/// Адаптивный виджет логотипа с консистентными размерами и устранением артефактов фона
class AdaptiveLogo extends StatelessWidget {
  final Color? backgroundColor;
  final String? assetPath;
  final LogoSize size;

  const AdaptiveLogo({
    Key? key,
    this.backgroundColor,
    this.assetPath,
    this.size = LogoSize.medium,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bgColor =
        backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    final logoAsset = assetPath ?? 'assets/logo.png';

    double logoSize = _calculateSize(screenWidth, size);

    // Просто отображаем картинку без какой-либо подложки.
    // PNG имеет настоящую прозрачность — сквозь прозрачные пиксели будет
    // виден фон Scaffold (splashBgColor), а не клетчатый паттерн.
    return SizedBox(
      width: logoSize,
      height: logoSize,
      child: Image.asset(
        logoAsset,
        width: logoSize,
        height: logoSize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }

  double _calculateSize(double screenWidth, LogoSize sizeType) {
    double logoSize;

    switch (sizeType) {
      case LogoSize.small:
        if (screenWidth > 768) {
          logoSize = 80.0;
        } else if (screenWidth > 480) {
          logoSize = screenWidth * 0.15;
        } else {
          logoSize = screenWidth * 0.18;
        }
        return logoSize.clamp(60.0, 100.0);

      case LogoSize.medium:
        if (screenWidth > 768) {
          logoSize = 100.0;
        } else if (screenWidth > 480) {
          logoSize = screenWidth * 0.18;
        } else {
          logoSize = screenWidth * 0.20;
        }
        return logoSize.clamp(80.0, 120.0);

      case LogoSize.large:
        if (screenWidth > 768) {
          logoSize = 140.0;
        } else if (screenWidth > 480) {
          logoSize = screenWidth * 0.25;
        } else {
          logoSize = screenWidth * 0.28;
        }
        return logoSize.clamp(100.0, 160.0);
    }
  }
}

/// Размеры логотипа для разных контекстов
enum LogoSize {
  small, // Для компактных интерфейсов
  medium, // Для страниц авторизации
  large, // Для splash screen и основных экранов загрузки
}
