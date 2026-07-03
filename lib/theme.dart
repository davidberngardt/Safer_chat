import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safer_chat/providers/font_scale_provider.dart';

class MessengerTheme {
  // Light Theme Colors
  static const Color lightBgPrimary = Color(0xFFFFFFFF);
  static const Color lightBgSecondary = Color(0xFFFFFFFF);
  static const Color lightBgTertiary = Color(0xFFF0F2F5);
  static const Color lightTextPrimary = Color(0xFF0A0E27);
  static const Color lightTextSecondary = Color(0xFF65676B);
  static const Color lightTextTertiary = Color(0xFF8A8D91);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color lightAccent = Color(0xFFFF8C42);
  static const Color lightAccentHover = Color(0xFFE67A2A);
  static const Color lightSuccess = Color(0xFF31A24C);
  static const Color lightWarning = Color(0xFFF57C00);
  static const Color lightError = Color(0xFFE74C3C);

  // Dark Theme Colors
  static const Color darkBgPrimary = Color(0xFF0A0E27);
  static const Color darkBgSecondary = Color(0xFF1A1F3A);
  static const Color darkBgTertiary = Color(0xFF242D4A);
  static const Color darkTextPrimary = Color(0xFFE8EAED);
  static const Color darkTextSecondary = Color(0xFFB0B3B8);
  static const Color darkTextTertiary = Color(0xFF8A8D91);
  static const Color darkBorder = Color(0xFF2D3748);
  static const Color darkAccent = Color(0xFFFF8C42);
  static const Color darkAccentHover = Color(0xFFFF9D5C);
  static const Color darkSuccess = Color(0xFF4CAF50);
  static const Color darkWarning = Color(0xFFFF9800);
  static const Color darkError = Color(0xFFF44336);

  // Common colors
  static const Color accentGradientEnd = Color(0xFF00D4FF);

  // Spacing
  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 12.0;
  static const double spacingLG = 16.0;
  static const double spacingXL = 24.0;
  static const double spacing2XL = 32.0;

  // Border Radius
  static const double radiusSM = 4.0;
  static const double radiusMD = 8.0;
  static const double radiusLG = 12.0;
  static const double radiusXL = 16.0;
  static const double radiusFull = 9999.0;

  // Shadows
  static final BoxShadow shadowSM = BoxShadow(
    color: Colors.black.withOpacity(0.05),
    blurRadius: 1,
    offset: const Offset(0, 1),
  );
  static final BoxShadow shadowMD = BoxShadow(
    color: Colors.black.withOpacity(0.1),
    blurRadius: 4,
    offset: const Offset(0, 4),
  );
  static final BoxShadow shadowLG = BoxShadow(
    color: Colors.black.withOpacity(0.1),
    blurRadius: 10,
    offset: const Offset(0, 10),
  );

  // Transitions
  static const Duration transitionFast = Duration(milliseconds: 150);
  static const Duration transitionNormal = Duration(milliseconds: 300);
  static const Duration transitionSlow = Duration(milliseconds: 500);

  // Font Sizes (базовые значения, которые будут умножаться на масштаб)
  static const double fontSizeXS = 12.0;
  static const double fontSizeSM = 13.0;
  static const double fontSizeBase = 14.0;
  static const double fontSizeLG = 16.0;
  static const double fontSizeXL = 18.0;
  static const double fontSize2XL = 20.0;

  // Метод для получения масштабированного размера шрифта
  static double scaledFontSize(BuildContext context, double baseSize) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return baseSize * fontSizeScale;
  }

  // Home Page Specific Styles
  static TextStyle homeSectionTitle(BuildContext context) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return TextStyle(
      fontSize: fontSizeSM * fontSizeScale,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
      letterSpacing: 0.5,
    );
  }

  static TextStyle homeChatName(BuildContext context) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return TextStyle(
      fontSize: fontSizeBase * fontSizeScale,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  static TextStyle homeChatPreview(BuildContext context) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return TextStyle(
      fontSize: fontSizeSM * fontSizeScale,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
    );
  }

  static TextStyle homeChatTime(BuildContext context) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return TextStyle(
      fontSize: fontSizeXS * fontSizeScale,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
    );
  }

  static TextStyle homeSearchHint(BuildContext context) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return TextStyle(
      fontSize: fontSizeBase * fontSizeScale,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
    );
  }

  // Chat Item Container Style - ТОНЬШЕ ГРАНИЦЫ
  static BoxDecoration homeChatItemDecoration(BuildContext context,
      {bool isHovered = false}) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(
        color: Theme.of(context).dividerColor.withOpacity(0.3),
        width: 0.5,
      ),
      borderRadius: BorderRadius.circular(radiusLG),
      boxShadow: isHovered ? [shadowSM] : [],
    );
  }

  // Search Container Style
  static BoxDecoration homeSearchDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
      borderRadius: BorderRadius.circular(radiusFull),
    );
  }

  // Badge Style for Unread Messages
  static BoxDecoration homeBadgeDecoration(BuildContext context) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return BoxDecoration(
      color: lightAccent,
      shape: BoxShape.circle,
    );
  }

  static TextStyle homeBadgeText(BuildContext context) {
    final fontSizeScale =
        Provider.of<FontScaleProvider>(context, listen: false).fontSizeScale;
    return TextStyle(
      fontSize: 11.0 * fontSizeScale,
      color: Colors.white,
      fontWeight: FontWeight.w600,
    );
  }

  // Avatar Gradients for different chat types
  static LinearGradient getAvatarGradient(int seed) {
    final colors = [
      const Color(0xFF4CAF50),
      const Color(0xFFF44336),
      const Color(0xFF2196F3),
      const Color(0xFF9C27B0),
      const Color(0xFF607D8B),
    ];
    return LinearGradient(
      colors: [colors[seed % colors.length], accentGradientEnd],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  // Pinned Icon Style
  static BoxDecoration homePinnedIconDecoration() {
    return const BoxDecoration(
      color: lightAccent,
      shape: BoxShape.circle,
      border: Border.fromBorderSide(
        BorderSide(color: Colors.white, width: 1.5),
      ),
    );
  }

  // Theme Data
  static ThemeData lightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBgPrimary,
      appBarTheme: AppBarTheme(
        backgroundColor: lightAccent,
        foregroundColor: Colors.white,
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.1),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontSize: fontSizeLG,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          fontFamily: 'Inter',
        ),
      ),
      cardTheme: CardThemeData(
        color: lightBgSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLG),
          side: const BorderSide(color: lightBorder, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          borderSide: const BorderSide(color: lightBorder, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          borderSide: const BorderSide(color: lightBorder, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          borderSide: const BorderSide(color: lightAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingLG,
          vertical: spacingMD,
        ),
        hintStyle: TextStyle(
          color: lightTextTertiary,
          fontSize: fontSizeBase,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: spacingLG,
            vertical: spacingMD,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLG),
          ),
          elevation: 0,
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: fontSizeBase,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightAccent,
        ),
      ),
      iconTheme: const IconThemeData(
        color: lightTextPrimary,
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 0.5,
        space: 1,
      ),
      colorScheme: ColorScheme.light(
        primary: lightAccent,
        secondary: accentGradientEnd,
        background: lightBgPrimary,
        surface: lightBgSecondary,
        onBackground: lightTextPrimary,
        onSurface: lightTextPrimary,
        error: lightError,
      ),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBgPrimary,
      appBarTheme: AppBarTheme(
        backgroundColor: darkAccent,
        foregroundColor: Colors.white,
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.3),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontSize: fontSizeLG,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          fontFamily: 'Inter',
        ),
      ),
      cardTheme: CardThemeData(
        color: darkBgSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLG),
          side: const BorderSide(color: darkBorder, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkBgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          borderSide: const BorderSide(color: darkBorder, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          borderSide: const BorderSide(color: darkBorder, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          borderSide: const BorderSide(color: darkAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingLG,
          vertical: spacingMD,
        ),
        hintStyle: TextStyle(
          color: darkTextTertiary,
          fontSize: fontSizeBase,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: spacingLG,
            vertical: spacingMD,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLG),
          ),
          elevation: 0,
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: fontSizeBase,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkAccent,
        ),
      ),
      iconTheme: const IconThemeData(
        color: darkTextPrimary,
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 0.5,
        space: 1,
      ),
      colorScheme: ColorScheme.dark(
        primary: darkAccent,
        secondary: accentGradientEnd,
        background: darkBgPrimary,
        surface: darkBgSecondary,
        onBackground: darkTextPrimary,
        onSurface: darkTextPrimary,
        error: darkError,
      ),
    );
  }
}
