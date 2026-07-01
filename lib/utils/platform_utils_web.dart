import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart' as file_picker;

class PlatformUtils {
  // ✅ BASE URL
  static String getDefaultBaseUrl() {
    return 'http://localhost:3004';
  }

  static String getBaseUrl(String? baseUrl) {
    if (baseUrl != null) return baseUrl;
    return getDefaultBaseUrl();
  }

  static void blockContextMenu() {
    html.document.onContextMenu.listen((event) {
      event.preventDefault();
    });
  }

  static void preventDefaultContextMenu() {}

  static Future<bool> downloadFile(String url) async {
    html.window.open(url, '_blank');
    return true;
  }

  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> openUrl(String url) async {
    html.window.open(url, '_blank');
  }

  static Future<List<file_picker.PlatformFile>> pickFiles({
    bool allowMultiple = false,
    List<String>? allowedExtensions,
    file_picker.FileType fileType = file_picker.FileType.any,
  }) async {
    final completer = Completer<List<file_picker.PlatformFile>>();

    final input = html.FileUploadInputElement();
    input.multiple = allowMultiple;

    input.onChange.listen((event) {
      final files = input.files;
      if (files == null || files.isEmpty) {
        completer.complete([]);
        return;
      }

      final result = <file_picker.PlatformFile>[];

      for (final file in files) {
        final reader = html.FileReader();

        reader.onLoadEnd.listen((_) {
          result.add(file_picker.PlatformFile(
            name: file.name,
            size: file.size,
            bytes: reader.result as Uint8List,
          ));

          if (result.length == files.length) {
            completer.complete(result);
          }
        });

        reader.readAsArrayBuffer(file);
      }
    });

    input.click();

    return completer.future;
  }

  static void dispatchCustomEvent(
      String eventName, Map<String, dynamic> detail) {
    final event = html.CustomEvent(eventName, detail: detail);
    html.document.dispatchEvent(event);
  }

  static Offset getMousePositionFromEvent(dynamic event) {
    return Offset(event.client.x.toDouble(), event.client.y.toDouble());
  }

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
      ),
    );
  }

  static Future<bool> showConfirmation({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'OK',
    String cancelText = 'Cancel',
  }) async {
    return true;
  }
}