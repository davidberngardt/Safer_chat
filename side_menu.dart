import 'package:flutter/material.dart';

class SideMenu extends StatelessWidget {
  final Function(String) onMenuItemClicked;

  const SideMenu({super.key, required this.onMenuItemClicked});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: const Color(0xFFFFFFFF),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFFFFB74D),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child:
                        Icon(Icons.person, size: 40, color: Color(0xFFFFB74D)),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Safer Chat',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Безопасное общение',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            _buildMenuItem(context, Icons.chat, 'Создать чат'),
            _buildMenuItem(context, Icons.settings, 'Профиль'),
            _buildMenuItem(context, Icons.note, 'Настройки'),
            _buildMenuItem(context, Icons.contacts, 'Контакты'),
            _buildMenuItem(context, Icons.download, 'Загрузки'),
            _buildMenuItem(context, Icons.person, 'Заметки'),
            _buildMenuItem(context, Icons.person_add, 'Пригласить'),
            const Divider(),
            _buildMenuItem(context, Icons.logout, 'Выйти'),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFFF9800)),
      title: Text(
        title,
        style: const TextStyle(color: Colors.black87),
      ),
      onTap: () {
        Navigator.pop(context);
        onMenuItemClicked(title);
      },
    );
  }
}
