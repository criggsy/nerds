import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MyDrawer extends StatelessWidget {
  static const TextStyle _menuTextColor = TextStyle(
    color: Colors.teal,
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
  );

  const MyDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(0),
        children: <Widget>[
          const UserAccountsDrawerHeader(
            accountName: Text(
              "Nerds Stickers",
              style: TextStyle(
                fontSize: 20.0,
              ),
            ),
            accountEmail: Text("Sticker Bait Central"),
//          currentAccountPicture: Image.asset('assets/images/avatar.png'),
          ),
          ListTile(
            leading: const Icon(Icons.home, color: Colors.blue),
            title: const Text("Home", style: _menuTextColor),
            onTap: () {
              context.go('/');
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_special, color: Colors.blue),
            title: const Text("Sticker Packs", style: _menuTextColor),
            onTap: () {
              context.go('/stickers');
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder, color: Colors.green),
            title: const Text("Folder View", style: _menuTextColor),
            onTap: () {
              context.go('/folder-stickers');
            },
          ),
          ListTile(
            leading: const Icon(Icons.info, color: Colors.orange),
            title: const Text("Information", style: _menuTextColor),
            onTap: () {
              context.go('/information');
            },
          ),
          // Add notification testing option (only in debug mode)
          if (const bool.fromEnvironment('ENABLE_TEST_NOTIFICATIONS',
              defaultValue: false))
            ListTile(
              leading:
                  const Icon(Icons.notifications_active, color: Colors.orange),
              title: const Text("🧪 Test Notifications", style: _menuTextColor),
              onTap: () {
                context.push('/notification-test');
              },
            ),
        ],
      ),
    );
  }
}
