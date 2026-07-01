import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../models/user_model.dart';
import '../utils/platform_utils.dart';

class CreateGroupModal extends StatefulWidget {
  final List<User> availableUsers;

  const CreateGroupModal({
    super.key,
    this.availableUsers = const [],
  });

  @override
  State<CreateGroupModal> createState() => _CreateGroupModalState();
}

class _CreateGroupModalState extends State<CreateGroupModal> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  Uint8List? avatarBytes;
  Color avatarColor = Colors.blue;
  bool isCreating = false;
  bool showUserSelection = false;
  List<int> selectedUserIds = [];
  List<User> filteredUsers = [];

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
    filteredUsers = widget.availableUsers;
    searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _filterUsers() {
    final query = searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredUsers = widget.availableUsers;
      } else {
        filteredUsers = widget.availableUsers.where((user) {
          return user.name.toLowerCase().contains(query) ||
              user.nickname.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _toggleUserSelection(int userId) {
    setState(() {
      if (selectedUserIds.contains(userId)) {
        selectedUserIds.remove(userId);
      } else {
        selectedUserIds.add(userId);
      }
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

        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.photoSelected),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.photoPickError)),
        );
      }
    }
  }

  void showColorPicker() {
    if (avatarBytes != null) {
      final localizations = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.removePhotoFirst)),
      );
      return;
    }

    final localizations = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(localizations.selectColor),
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 24)
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showUserSelection() {
    setState(() {
      showUserSelection = true;
      searchController.clear();
      filteredUsers = widget.availableUsers;
    });
  }

  void _hideUserSelection() {
    setState(() {
      showUserSelection = false;
      searchController.clear();
    });
  }

  Future<void> onCreate() async {
    if (isCreating) return;

    final trimmedName = nameController.text.trim();
    final localizations = AppLocalizations.of(context)!;

    if (trimmedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.groupNameRequired), // Используем новый ключ
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isCreating = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;

      if (token == null || token.isEmpty) {
        throw Exception(localizations.authTokenMissing);
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:3004/api/groups'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      request.fields['name'] = trimmedName;
      
      if (descriptionController.text.trim().isNotEmpty) {
        request.fields['description'] = descriptionController.text.trim();
      }

      final colorHex = '#${avatarColor.value.toRadixString(16).substring(2).toUpperCase()}';
      request.fields['avatar_color'] = colorHex;

      if (selectedUserIds.isNotEmpty) {
        request.fields['member_ids'] = jsonEncode(selectedUserIds);
      }

      if (avatarBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'avatar',
            avatarBytes!,
            filename: 'group_avatar.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception(localizations.requestTimeout);
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.groupCreated),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop(data['group']);
        }
      } else {
        final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
        throw Exception(errorBody['error'] ?? '${localizations.groupCreateError} (${response.statusCode})');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${localizations.error}: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
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

  Widget buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    int? maxLength,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label, 
          style: TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFFF9800), width: 2),
            ),
            contentPadding: const EdgeInsets.all(18),
            counterText: '',
          ),
        ),
      ],
    );
  }

  Widget _buildCreateGroupView() {
    final localizations = AppLocalizations.of(context)!;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final bool hasPhoto = avatarBytes != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  localizations.createGroup,
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
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: avatarColor,
                    backgroundImage: hasPhoto ? MemoryImage(avatarBytes!) : null,
                    child: hasPhoto
                        ? null
                        : const Icon(Icons.group_rounded, size: 70, color: Colors.white),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: isCreating ? null : pickAvatar,
                        icon: const Icon(Icons.camera_alt_rounded, color: Colors.black87),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Tooltip(
                message: localizations.selectAvatarColor,
                child: IconButton(
                  onPressed: hasPhoto || isCreating ? null : showColorPicker,
                  icon: Icon(
                    Icons.palette_outlined,
                    size: 28,
                    color: hasPhoto
                        ? (isDarkMode ? Colors.grey : Colors.grey)
                        : const Color(0xFFFF9800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildTextField(
                  localizations.groupName,
                  nameController,
                  maxLength: 50,
                ),
                const SizedBox(height: 24),
                buildTextField(
                  localizations.description,
                  descriptionController,
                  maxLines: 3,
                  maxLength: 200,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isCreating ? null : _showUserSelection,
                    icon: const Icon(Icons.person_add_rounded, color: Color(0xFFFF9800)),
                    label: Text(
                      '${localizations.addMembers}${selectedUserIds.isNotEmpty ? ' (${selectedUserIds.length})' : ''}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: isDarkMode ? Colors.white24 : Colors.black12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isCreating ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: BorderSide(
                      color: isDarkMode ? Colors.white24 : Colors.black12,
                    ),
                  ),
                  child: Text(
                    localizations.cancel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: isCreating ? null : onCreate,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: const Color(0xFFFF9800),
                    elevation: isCreating ? 0 : 2,
                  ),
                  child: isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          localizations.create,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserSelectionView() {
    final localizations = AppLocalizations.of(context)!;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              IconButton(
                onPressed: _hideUserSelection,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  localizations.addMembers,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (selectedUserIds.isNotEmpty)
                Text(
                  '${selectedUserIds.length} ${localizations.selected}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: searchController,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: localizations.searchPlaceholder,
              hintStyle: TextStyle(
                color: isDarkMode ? Colors.white38 : Colors.black38,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
              filled: true,
              fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: filteredUsers.isEmpty
              ? Center(
                  child: Text(
                    localizations.noMatches,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDarkMode ? Colors.white54 : Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    final isSelected = selectedUserIds.contains(user.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: user.avatarColor,
                          backgroundImage: user.avatarBytes != null
                              ? MemoryImage(user.avatarBytes!)
                              : null,
                          child: user.avatarBytes == null
                              ? const Icon(Icons.person_rounded, size: 28, color: Colors.white)
                              : null,
                        ),
                        title: Text(
                          user.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          user.nickname,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleUserSelection(user.id),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          activeColor: const Color(0xFFFF9800),
                        ),
                        onTap: () => _toggleUserSelection(user.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    double modalWidth;
    double modalHeight;
    EdgeInsets modalPadding;

    if (screenWidth > 1200) {
      modalWidth = 500;
      modalHeight = screenHeight * 0.7;
      modalPadding = const EdgeInsets.symmetric(horizontal: 40, vertical: 30);
    } else if (screenWidth > 800) {
      modalWidth = 480;
      modalHeight = screenHeight * 0.75;
      modalPadding = const EdgeInsets.symmetric(horizontal: 30, vertical: 25);
    } else if (screenWidth > 600) {
      modalWidth = screenWidth * 0.75;
      modalHeight = screenHeight * 0.8;
      modalPadding = const EdgeInsets.symmetric(horizontal: 24, vertical: 20);
    } else {
      modalWidth = screenWidth * 0.9;
      modalHeight = screenHeight * 0.85;
      modalPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: modalPadding,
      child: Container(
        width: modalWidth,
        height: modalHeight,
        constraints: BoxConstraints(
          maxWidth: modalWidth,
          maxHeight: modalHeight,
        ),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: showUserSelection
            ? _buildUserSelectionView()
            : _buildCreateGroupView(),
      ),
    );
  }
}

Future<Map<String, dynamic>?> showCreateGroupModal(
  BuildContext context, {
  List<User> availableUsers = const [],
}) async {
  return await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CreateGroupModal(availableUsers: availableUsers),
  );
}