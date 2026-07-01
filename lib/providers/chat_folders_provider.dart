import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatFoldersProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _folders = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get folders => _folders;
  bool get isLoading => _isLoading;

  Future<void> loadFolders(String token, String baseUrl) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/folders'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _folders = List<Map<String, dynamic>>.from(data['folders']);
        }
      }
    } catch (e) {
      print('Error loading folders: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createFolder({
    required String token,
    required String baseUrl,
    required String name,
    required Color color,
    List<String>? chatIds,
    Uint8List? avatarBytes,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/folders'));
      request.headers['Authorization'] = 'Bearer $token';

      request.fields['name'] = name;
      request.fields['avatar_color'] = '#${color.value.toRadixString(16).substring(2)}';
      
      if (chatIds != null && chatIds.isNotEmpty) {
        request.fields['chat_ids'] = jsonEncode(chatIds);
      }

      if (avatarBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'avatar',
            avatarBytes,
            filename: 'folder_avatar.jpg',
          ),
        );
      }

      final response = await request.send();
      return response.statusCode == 201;
    } catch (e) {
      print('Error creating folder: $e');
      return false;
    }
  }

  Future<bool> deleteFolder(String token, String baseUrl, int folderId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/folders/$folderId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting folder: $e');
      return false;
    }
  }

  void clearFolders() {
    _folders.clear();
    notifyListeners();
  }
}