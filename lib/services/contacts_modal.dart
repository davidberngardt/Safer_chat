// contacts_modal.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers/theme_provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import '../utils/platform_utils.dart'; // Добавлен импорт

class ContactsModal extends StatefulWidget {
  final String? token;
  final String? baseUrl;
  final int myUserId;
  final Function(int userId, String contactName)? onOpenChat;

  const ContactsModal({
    Key? key,
    this.token,
    this.baseUrl,
    required this.myUserId,
    this.onOpenChat,
  }) : super(key: key);

  @override
  State<ContactsModal> createState() => _ContactsModalState();
}

class _ContactsModalState extends State<ContactsModal> {
  final TextEditingController searchController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  List<Map<String, dynamic>> allContacts = [];
  List<Map<String, dynamic>> filteredContacts = [];
  bool isLoading = true;
  int? expandedContactId;
  bool showAddContactForm = false;
  bool isCreatingContact = false;
  String? emailError;

  @override
  void initState() {
    super.initState();
    loadContacts();
    searchController.addListener(_onSearchChanged);
    emailController.addListener(_validateEmail);
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchChanged);
    emailController.removeListener(_validateEmail);
    searchController.dispose();
    nameController.dispose();
    emailController.dispose();
    noteController.dispose();
    super.dispose();
  }

  void _validateEmail() {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        emailError = null;
      });
      return;
    }

    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    setState(() {
      emailError = emailRegex.hasMatch(email) ? null : 'invalidEmail';
    });
  }

  void _onSearchChanged() {
    final query = searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredContacts = List.from(allContacts);
      } else {
        filteredContacts = allContacts.where((contact) {
          final name = (contact['contact_name'] ?? '').toString().toLowerCase();
          final nickname = (contact['nickname'] ?? '').toString().toLowerCase();
          final email = (contact['contact_email'] ?? '').toString().toLowerCase();
          return name.contains(query) || nickname.contains(query) || email.contains(query);
        }).toList();
      }
      expandedContactId = null;
    });
  }

  Future<void> loadContacts() async {
    if (widget.token == null || widget.baseUrl == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/contacts'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['contacts'] != null) {
          final contacts = List<Map<String, dynamic>>.from(data['contacts']);
          final validContacts = contacts.where((contact) {
            return contact['id'] != null;
          }).toList();

          setState(() {
            allContacts = validContacts;
            filteredContacts = List.from(validContacts);
            isLoading = false;
          });
          print('✅ Загружено контактов: ${validContacts.length}');
        } else {
          setState(() {
            isLoading = false;
          });
        }
      } else {
        print('Error loading contacts: ${response.statusCode}');
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Exception loading contacts: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> createContact() async {
    final localizations = AppLocalizations.of(context)!;
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final note = noteController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.contactNameRequired ?? 'contactNameRequired'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.contactEmailRequired ?? 'contactEmailRequired'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (emailError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.validEmailRequired ?? 'validEmailRequired'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isCreatingContact = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/api/contacts'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contact_name': name,
          'contact_email': email,
          'note': note.isNotEmpty ? note : null,
        }),
      );

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        
        if (responseData['success'] == true && responseData['contact'] != null) {
          final newContact = Map<String, dynamic>.from(responseData['contact']);
          
          newContact['is_registered'] = newContact['contact_user_id'] != null;
          
          setState(() {
            allContacts.insert(0, newContact);
            filteredContacts = List.from(allContacts);
            
            nameController.clear();
            emailController.clear();
            noteController.clear();
            emailError = null;
            
            showAddContactForm = false;
            isCreatingContact = false;
          });
          
          print('✅ Контакт создан и добавлен в список: ${newContact['contact_name']}');
        } else {
          loadContacts();
        }
      } else {
        final errorData = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorData['error'] ?? localizations.error ?? 'error'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('Exception creating contact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.error ?? 'error'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isCreatingContact = false;
        });
      }
    }
  }

  Future<void> deleteContact(int contactId, String contactName) async {
    final appLocalizations = AppLocalizations.of(context);
    if (appLocalizations == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final themeProvider = Provider.of<ThemeProvider>(context);
        final isDarkMode = themeProvider.isDarkMode;

        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            appLocalizations.deleteContact ?? 'deleteContact',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            '${appLocalizations.deleteContactConfirm ?? 'deleteContactConfirm'} $contactName?',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(appLocalizations.cancel ?? 'cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: Text(appLocalizations.delete ?? 'delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        final response = await http.delete(
          Uri.parse('${widget.baseUrl}/api/contacts/$contactId'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          print('✅ $contactName удален');
          
          setState(() {
            allContacts.removeWhere((contact) => contact['id'] == contactId);
            filteredContacts.removeWhere((contact) => contact['id'] == contactId);
            expandedContactId = null;
          });
        } else {
          print('❌ Ошибка удаления: ${response.statusCode}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appLocalizations.deleteContactError ?? 'deleteContactError'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        print('Exception deleting contact: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appLocalizations.deleteContactError ?? 'deleteContactError'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void editContact(int contactId, String currentName, String currentNote) async {
    print('🔵 [Edit] Редактирование контакта ID: $contactId');
    
    final result = await showEditContactModal(
      context,
      widget.token,
      widget.baseUrl,
      contactId,
      currentName,
      currentNote,
    );
    
    if (result != null && result['name'] != null) {
      print('✅ Контакт обновлён: ${result['name']}');
      
      final index = allContacts.indexWhere((contact) => contact['id'] == contactId);
      if (index != -1) {
        setState(() {
          allContacts[index]['contact_name'] = result['name'];
          allContacts[index]['note'] = result['note'];
          
          final filterIndex = filteredContacts.indexWhere((contact) => contact['id'] == contactId);
          if (filterIndex != -1) {
            filteredContacts[filterIndex]['contact_name'] = result['name'];
            filteredContacts[filterIndex]['note'] = result['note'];
          }
        });
      }
    }
  }

  void openChat(int userId) {
    print('🔵 [1] openChat вызван с userId: $userId');
    final contact = filteredContacts.firstWhere(
      (c) => c['contact_user_id'] == userId,
      orElse: () => {'contact_name': 'Контакт'},
    );
    final contactName = contact['contact_name'] ?? 'Контакт';
    print('🔵 [2] Найден контакт: $contactName');

    if (widget.onOpenChat != null) {
      print('🔵 [3] Используем onOpenChat колбэк');
      Navigator.pop(context);
      widget.onOpenChat?.call(userId, contactName);
    } else {
      print('🔵 [3] Возвращаем данные через Navigator.pop');
      Navigator.pop(context, {
        'userId': userId,
        'contactName': contactName,
      });
    }

    print('🔵 [5] openChat завершён');
  }

  void showAddContactScreen() {
    setState(() {
      showAddContactForm = true;
      searchController.clear();
      nameController.clear();
      emailController.clear();
      noteController.clear();
      emailError = null;
    });
  }

  void hideAddContactScreen() {
    setState(() {
      showAddContactForm = false;
      nameController.clear();
      emailController.clear();
      noteController.clear();
      emailError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final appLocalizations = AppLocalizations.of(context);
    final isDarkMode = themeProvider.isDarkMode;

    if (appLocalizations == null) {
      return const Dialog(
        child: Center(child: CircularProgressIndicator()),
      );
    }

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
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      if (showAddContactForm)
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: hideAddContactScreen,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      if (showAddContactForm) const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          showAddContactForm
                              ? (appLocalizations.newContact ?? 'newContact')
                              : (appLocalizations.contacts ?? 'contacts'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!showAddContactForm)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ),
                if (showAddContactForm)
                  _buildAddContactForm(isDarkMode, appLocalizations)
                else
                  _buildContactsList(isDarkMode, appLocalizations),
              ],
            ),
            if (!showAddContactForm)
              Positioned(
                right: 20,
                bottom: 20,
                child: FloatingActionButton(
                  onPressed: showAddContactScreen,
                  backgroundColor: const Color(0xFFFF9800),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddContactForm(bool isDarkMode, AppLocalizations localizations) {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.contactName ?? 'contactName',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              localizations.contactEmail ?? 'contactEmail',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: emailError != null ? Colors.red : Colors.transparent,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: emailError != null ? Colors.red : Colors.transparent,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: emailError != null ? Colors.red : const Color(0xFFFF9800),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            if (emailError != null) ...[
              const SizedBox(height: 6),
              Text(
                localizations.invalidEmail ?? 'invalidEmail',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              localizations.note ?? 'note',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isCreatingContact ? null : hideAddContactScreen,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: isDarkMode ? Colors.white24 : Colors.black12,
                      ),
                    ),
                    child: Text(
                      localizations.cancel ?? 'cancel',
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
                    onPressed: isCreatingContact ? null : createContact,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: const Color(0xFFFF9800),
                    ),
                    child: isCreatingContact
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            localizations.createContact ?? 'createContact',
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
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList(bool isDarkMode, AppLocalizations localizations) {
    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: localizations.searchContacts ?? 'searchContacts',
                hintStyle: TextStyle(
                  color: isDarkMode ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
                filled: true,
                fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredContacts.isEmpty
                    ? Center(
                        child: Text(
                          searchController.text.isEmpty
                              ? (localizations.noContacts ?? 'noContacts')
                              : (localizations.contactsNotFound ?? 'contactsNotFound'),
                          style: TextStyle(
                            color: isDarkMode ? Colors.white54 : Colors.black54,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom: 80,
                        ),
                        itemCount: filteredContacts.length,
                        itemBuilder: (context, index) {
                          final contact = filteredContacts[index];
                          final contactId = contact['id'];
                          if (contactId == null) {
                            return const SizedBox.shrink();
                          }

                          final isExpanded = expandedContactId == contactId;
                          return _buildContactItem(
                            contact,
                            isDarkMode,
                            isExpanded,
                            localizations,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(
    Map<String, dynamic> contact,
    bool isDarkMode,
    bool isExpanded,
    AppLocalizations localizations,
  ) {
    final contactId = contact['id'];
    final contactUserId = contact['contact_user_id'];
    if (contactId == null) {
      return const SizedBox.shrink();
    }

    final name = contact['contact_name'] ?? 'Unknown';
    final nickname = contact['nickname'] ?? '';
    final email = contact['contact_email'] ?? '';
    final isRegistered = contact['contact_user_id'] != null;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: isRegistered ? const Color(0xFFFF9800) : Colors.grey,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (!isRegistered)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      localizations.notRegistered ?? 'notRegistered',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDarkMode ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nickname.isNotEmpty)
                  Text(
                    nickname,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.white54 : Colors.black54,
                    ),
                  ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                    ),
                  ),
              ],
            ),
            onTap: () {
              setState(() {
                expandedContactId = isExpanded ? null : contactId as int;
              });
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (isRegistered && contactUserId != null)
                    _buildActionButton(
                      icon: Icons.chat_bubble_outline,
                      color: const Color(0xFF4CAF50),
                      label: localizations.chat ?? 'chat',
                      isDarkMode: isDarkMode,
                      onTap: () => openChat(contactUserId as int),
                    ),
                  
                  _buildActionButton(
                    icon: Icons.edit_outlined,
                    color: const Color(0xFF2196F3),
                    label: localizations.edit ?? 'edit',
                    isDarkMode: isDarkMode,
                    onTap: () => editContact(contactId as int, name, contact['note'] ?? ''),
                  ),
                  
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    color: Colors.red,
                    label: localizations.delete ?? 'delete',
                    isDarkMode: isDarkMode,
                    onTap: () => deleteContact(contactId as int, name),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: color.withOpacity(0.15),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }
}

Future<Map<String, dynamic>?> showContactsModal(
  BuildContext context,
  String? token,
  String? baseUrl,
  int myUserId,
  Function(int userId, String contactName)? onOpenChat,
) async {
  return await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => ContactsModal(
      token: token,
      baseUrl: baseUrl,
      myUserId: myUserId,
      onOpenChat: onOpenChat,
    ),
  );
}

// Модалка для редактирования контакта
class EditContactModal extends StatefulWidget {
  final String? token;
  final String? baseUrl;
  final int contactId;
  final String initialName;
  final String initialNote;

  const EditContactModal({
    Key? key,
    this.token,
    this.baseUrl,
    required this.contactId,
    required this.initialName,
    required this.initialNote,
  }) : super(key: key);

  @override
  State<EditContactModal> createState() => _EditContactModalState();
}

class _EditContactModalState extends State<EditContactModal> {
  late TextEditingController nameController;
  late TextEditingController noteController;
  bool isUpdating = false;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.initialName);
    noteController = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    nameController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> updateContact() async {
    final localizations = AppLocalizations.of(context)!;
    final name = nameController.text.trim();
    final note = noteController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.contactNameRequired ?? 'contactNameRequired'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isUpdating = true;
    });

    try {
      final response = await http.put(
        Uri.parse('${widget.baseUrl}/api/contacts/${widget.contactId}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contact_name': name,
          'note': note.isNotEmpty ? note : null,
        }),
      );

      if (response.statusCode == 200) {
        Navigator.pop(context, {
          'name': name,
          'note': note,
        });
      } else {
        final errorData = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorData['error'] ?? localizations.error ?? 'error'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('Exception updating contact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.error ?? 'error'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localizations = AppLocalizations.of(context);
    final isDarkMode = themeProvider.isDarkMode;

    if (localizations == null) {
      return const Dialog(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    double modalWidth;
    double modalHeight;
    EdgeInsets modalPadding;

    if (screenWidth > 1200) {
      modalWidth = 500;
      modalHeight = screenHeight * 0.5;
      modalPadding = const EdgeInsets.symmetric(horizontal: 40, vertical: 30);
    } else if (screenWidth > 800) {
      modalWidth = 480;
      modalHeight = screenHeight * 0.55;
      modalPadding = const EdgeInsets.symmetric(horizontal: 30, vertical: 25);
    } else if (screenWidth > 600) {
      modalWidth = screenWidth * 0.75;
      modalHeight = screenHeight * 0.6;
      modalPadding = const EdgeInsets.symmetric(horizontal: 24, vertical: 20);
    } else {
      modalWidth = screenWidth * 0.9;
      modalHeight = screenHeight * 0.65;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      localizations.editContact ?? 'editContact',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
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

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.contactName ?? 'contactName',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      localizations.note ?? 'note',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isUpdating ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: isDarkMode ? Colors.white24 : Colors.black12,
                              ),
                            ),
                            child: Text(
                              localizations.cancel ?? 'cancel',
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
                            onPressed: isUpdating ? null : updateContact,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: const Color(0xFFFF9800),
                            ),
                            child: isUpdating
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Text(
                                    localizations.save ?? 'save',
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> showEditContactModal(
  BuildContext context,
  String? token,
  String? baseUrl,
  int contactId,
  String initialName,
  String initialNote,
) async {
  return await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => EditContactModal(
      token: token,
      baseUrl: baseUrl,
      contactId: contactId,
      initialName: initialName,
      initialNote: initialNote,
    ),
  );
}