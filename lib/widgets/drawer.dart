import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:nerds/services/user_pack_service.dart';

class MyDrawer extends StatelessWidget {
  static const TextStyle _menuTextColor = TextStyle(
    color: Colors.teal,
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
  );

  const MyDrawer({super.key});

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListenableBuilder(
        listenable: UserPackService.instance,
        builder: (context, _) {
          final userPacks = UserPackService.instance.packs;
          return ListView(
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
              ),
              ListTile(
                leading: const Icon(Icons.home, color: Colors.blue),
                title: const Text("Home", style: _menuTextColor),
                onTap: () {
                  context.go('/');
                },
              ),
              _sectionHeader(context, 'From server'),
              ListTile(
                leading:
                    const Icon(Icons.folder_special, color: Colors.blue),
                title: const Text("Sticker Packs", style: _menuTextColor),
                onTap: () {
                  final router = GoRouter.of(context);
                  final onStickers =
                      router.state.matchedLocation == '/stickers';
                  Navigator.of(context).pop();
                  if (!onStickers) {
                    router.push('/stickers');
                  }
                },
              ),
              _sectionHeader(context, 'My packs'),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate, color: Colors.teal),
                title: const Text("Create pack", style: _menuTextColor),
                onTap: () {
                  context.push('/user-packs/new');
                },
              ),
              ...userPacks.map(
                (pack) => ListTile(
                  leading: const Icon(Icons.collections, color: Colors.teal),
                  title: Text(pack.name, style: _menuTextColor),
                  onTap: () {
                    context.push('/user-packs/${pack.id}');
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info, color: Colors.orange),
                title: const Text("Information", style: _menuTextColor),
                onTap: () {
                  context.go('/information');
                },
              ),
              if (const bool.fromEnvironment('ENABLE_TEST_NOTIFICATIONS',
                  defaultValue: false))
                ListTile(
                  leading: const Icon(Icons.notifications_active,
                      color: Colors.orange),
                  title:
                      const Text("🧪 Test Notifications", style: _menuTextColor),
                  onTap: () {
                    context.push('/notification-test');
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
