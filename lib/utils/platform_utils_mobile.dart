import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

class PlatformUtils {
  // ✅ BASE URL
  static String getDefaultBaseUrl() {
    return 'http://10.0.2.2:3004';
  }

  static String getBaseUrl(String? baseUrl) {
    if (baseUrl != null) return baseUrl;
    return getDefaultBaseUrl();
  }

  static void blockContextMenu() {}

  static void preventDefaultContextMenu() {}

  static Future<bool> downloadFile(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await copyToClipboard(url);
      }
    } catch (_) {
      await copyToClipboard(url);
    }
  }

  static Future<List<PlatformFile>> pickFiles({
    bool allowMultiple = false,
    List<String>? allowedExtensions,
    FileType fileType = FileType.any,
  }) async {
    // Правильный вызов для file_picker 11.0.2 - статический метод
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: fileType,
      allowMultiple: allowMultiple,
      allowedExtensions: allowedExtensions,
      withData: true,
    );

    return result?.files ?? [];
  }

  static void dispatchCustomEvent(
      String eventName, Map<String, dynamic> detail) {}

  static Offset getMousePositionFromEvent(dynamic event) => Offset.zero;

  static Future<void> showAlert({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<bool> showConfirmation({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Подтвердить',
    String cancelText = 'Отмена',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}