// create_folder.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../models/chat.dart';
import '../utils/platform_utils.dart'; // Добавлен импорт

class CreateFolderModal extends StatefulWidget {
  final Map<String, dynamic>? folderData; // Для редактирования
  final List<Chat> availableChats;
  final VoidCallback? onFolderCreated;

  const CreateFolderModal({
    super.key,
    this.folderData,
    this.availableChats = const [],
    this.onFolderCreated,
  });

  @override
  State<CreateFolderModal> createState() => _CreateFolderModalState();
}

class _CreateFolderModalState extends State<CreateFolderModal> {
  final TextEditingController nameController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  Uint8List? avatarBytes;
  Color avatarColor = Colors.blue;
  bool isCreating = false;
  bool showChatSelection = false;
  List<String> selectedChatIds = [];
  List<Chat> filteredChats = [];

  final List<Color> palette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.brown,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    // Фильтруем только обычные чаты (не каналы)
    filteredChats = widget.availableChats.where((chat) => !chat.isChannel).toList();
    
    // Если редактируем существующую папку
    if (widget.folderData != null) {
      nameController.text = widget.folderData!['name'] ?? '';
      final colorHex = widget.folderData!['avatar_color'];
      if (colorHex != null) {
        avatarColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
      }
      
      final chatIds = widget.folderData!['chat_ids'] as List<dynamic>?;
      if (chatIds != null) {
        selectedChatIds = chatIds.map((id) => id.toString()).toList();
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void _toggleChatSelection(String chatId) {
    setState(() {
      if (selectedChatIds.contains(chatId)) {
        selectedChatIds.remove(chatId);
      } else {
        selectedChatIds.add(chatId);
      }
    });
  }

  void _removeChat(String chatId) {
    setState(() {
      selectedChatIds.remove(chatId);
    });
  }

  Future<void> pickAvatar() async {
    try {
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (mounted) {
        setState(() {
          avatarBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.failedToSelectPhoto ?? 'Не удалось выбрать фото')),
        );
      }
    }
  }

  void showColorPicker() {
    if (avatarBytes != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.removePhotoFirst ?? 'Сначала удалите фото')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context)!.selectColor ?? 'Выберите цвет'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: palette.map((color) {
              final isSelected = color == avatarColor;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    avatarColor = color;
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 4)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showChatSelection() {
    setState(() {
      showChatSelection = true;
      // Фильтруем только обычные чаты (не каналы)
      filteredChats = widget.availableChats.where((chat) => !chat.isChannel).toList();
    });
  }

  void _hideChatSelection() {
    setState(() {
      showChatSelection = false;
    });
  }

  Future<void> onCreate() async {
    if (isCreating) return;

    final trimmedName = nameController.text.trim();
    final localizations = AppLocalizations.of(context)!;

    if (trimmedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.enterFolderName ?? 'Введите название папки')),
      );
      return;
    }

    setState(() {
      isCreating = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;

      if (token == null) {
        throw Exception('Токен авторизации отсутствует');
      }

      var request = http.MultipartRequest(
        widget.folderData != null ? 'PUT' : 'POST',
        Uri.parse('http://localhost:3004/api/folders${widget.folderData != null ? '/${widget.folderData!['id']}' : ''}'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      request.fields['name'] = trimmedName;
      final colorHex = '#${avatarColor.value.toRadixString(16).substring(2).toUpperCase()}';
      request.fields['avatar_color'] = colorHex;
      
      if (selectedChatIds.isNotEmpty) {
        request.fields['chat_ids'] = jsonEncode(selectedChatIds);
      } else {
        request.fields['chat_ids'] = '[]'; // Пустой массив
      }

      if (avatarBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'avatar',
            avatarBytes!,
            filename: 'folder_avatar.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.folderData != null 
                ? (localizations.folderUpdated ?? 'Папка обновлена')
                : (localizations.folderCreated ?? 'Папка создана')),
              backgroundColor: Colors.green,
            ),
          );
          
          if (widget.onFolderCreated != null) {
            widget.onFolderCreated!();
          }
          
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('Ошибка ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${localizations.error ?? 'Ошибка'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isCreating = false;
        });
      }
    }
  }

  Future<bool?> _showDeleteConfirmation() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteFolder ?? 'Удалить папку'),
        content: Text(AppLocalizations.of(context)!.areYouSureYouWantToDeleteFolder ?? 'Вы уверены, что хотите удалить эту папку?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel ?? 'Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppLocalizations.of(context)!.delete ?? 'Удалить',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateFolderView() {
    final localizations = AppLocalizations.of(context)!;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final bool hasPhoto = avatarBytes != null;
    
    // Получаем только обычные чаты (не каналы) для отображения
    final regularChats = widget.availableChats.where((chat) => !chat.isChannel).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFA000), Color(0xFFFF5722)],
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
                  widget.folderData != null 
                    ? (localizations.editFolder ?? 'Редактировать папку')
                    : (localizations.createFolder ?? 'Создать папку'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: isCreating ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: avatarColor,
                    backgroundImage: hasPhoto ? MemoryImage(avatarBytes!) : null,
                    child: hasPhoto
                        ? null
                        : const Icon(Icons.folder_rounded, size: 70, color: Colors.white),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        onPressed: isCreating ? null : pickAvatar,
                        icon: const Icon(Icons.camera_alt_rounded, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              IconButton(
                onPressed: hasPhoto || isCreating ? null : showColorPicker,
                icon: Icon(
                  Icons.palette_outlined,
                  color: hasPhoto ? Colors.grey : const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: localizations.folderName ?? 'Название папки',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isCreating ? null : _showChatSelection,
                    icon: const Icon(Icons.chat_rounded, color: Color(0xFFFF9800)),
                    label: Text(
                      '${localizations.addChats ?? 'Добавить чаты'}${selectedChatIds.isNotEmpty ? ' (${selectedChatIds.length})' : ''}',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (selectedChatIds.isNotEmpty) 
                  _buildSelectedChatsList(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              if (widget.folderData != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: isCreating ? null : () async {
                      final confirm = await _showDeleteConfirmation();
                      if (confirm == true) {
                        _deleteFolder();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      localizations.delete ?? 'Удалить',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              if (widget.folderData != null) const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton(
                  onPressed: isCreating ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(localizations.cancel ?? 'Отмена'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: isCreating ? null : onCreate,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFFFF9800),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: isCreating
                      ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                      : Text(widget.folderData != null 
                          ? (localizations.save ?? 'Сохранить')
                          : (localizations.create ?? 'Создать')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedChatsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.selectedChats ?? 'Выбранные чаты:',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...selectedChatIds.map((chatId) {
          final chat = widget.availableChats.firstWhere(
            (c) => c.id.toString() == chatId,
            orElse: () => Chat.regular(
              id: 0,
              title: AppLocalizations.of(context)!.chat ?? 'Чат',
              lastMessage: '',
              lastMessageTime: DateTime.now(),
              unreadCount: 0,
              participants: [],
              isMuted: false,
              isPinned: false,
              myUserId: 0,
            ),
          );
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.grey[200],
              child: Text(chat.title[0].toUpperCase()),
            ),
            title: Text(chat.title),
            trailing: IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => _removeChat(chatId),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildChatSelectionView() {
    final localizations = AppLocalizations.of(context)!;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    // Фильтруем только обычные чаты (не каналы)
    final regularChats = widget.availableChats.where((chat) => !chat.isChannel).toList();
    final hasRegularChats = regularChats.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFA000), Color(0xFFFF5722)],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _hideChatSelection,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  localizations.selectChats ?? 'Выберите чаты',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (selectedChatIds.isNotEmpty && hasRegularChats)
                Text(
                  '${selectedChatIds.length} ${localizations.selected ?? 'выбрано'}',
                  style: const TextStyle(color: Colors.white),
                ),
            ],
          ),
        ),
        Expanded(
          child: !hasRegularChats
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      localizations.noActiveChats ?? 'У вас нет ни одного активного чата',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode ? Colors.white54 : Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: regularChats.length,
                  itemBuilder: (context, index) {
                    final chat = regularChats[index];
                    final isSelected = selectedChatIds.contains(chat.id.toString());

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[100],
                      ),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.grey[200],
                              child: Text(chat.title[0].toUpperCase()),
                            ),
                            if (isSelected)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF9800),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        title: Text(chat.title),
                        subtitle: chat.lastMessage != null
                            ? Text(
                                chat.lastMessage!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleChatSelection(chat.id.toString()),
                          activeColor: const Color(0xFFFF9800),
                        ),
                        onTap: () => _toggleChatSelection(chat.id.toString()),
                      ),
                    );
                  },
                ),
        ),
        // Отображаем кнопки только если есть хотя бы один обычный чат
        if (hasRegularChats)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _hideChatSelection,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(localizations.cancel ?? 'Отмена'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _hideChatSelection,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFFFF9800),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(localizations.addAction ?? 'Добавить'),
                  ),
                ),
              ],
            ),
          ),
        // Если нет обычных чатов, добавляем отступ внизу для лучшего внешнего вида
        if (!hasRegularChats)
          const SizedBox(height: 20),
      ],
    );
  }

  Future<void> _deleteFolder() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;
      
      if (token == null) return;
      
      final response = await http.delete(
        Uri.parse('http://localhost:3004/api/folders/${widget.folderData!['id']}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        if (widget.onFolderCreated != null) {
          widget.onFolderCreated!();
        }
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context)!.deleteError ?? 'Ошибка удаления'}: $e'), 
          backgroundColor: Colors.red
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: showChatSelection
            ? _buildChatSelectionView()
            : _buildCreateFolderView(),
      ),
    );
  }
}

Future<bool?> showCreateFolderModal(
  BuildContext context, {
  Map<String, dynamic>? folderData,
  required List<Chat> availableChats,
  VoidCallback? onFolderCreated,
}) async {
  return await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CreateFolderModal(
      folderData: folderData,
      availableChats: availableChats,
      onFolderCreated: onFolderCreated,
    ),
  );
}