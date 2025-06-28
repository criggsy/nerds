import 'package:flutter/material.dart';
import 'package:nerds/screens/notification_test_screen.dart';

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
          const ListTile(
            title: Text("Nothin doing here blud", style: _menuTextColor),
          ),
          // Add notification testing option (only in debug mode)
          if (const bool.fromEnvironment('ENABLE_TEST_NOTIFICATIONS',
              defaultValue: false))
            ListTile(
              leading:
                  const Icon(Icons.notifications_active, color: Colors.orange),
              title: const Text("🧪 Test Notifications", style: _menuTextColor),
              onTap: () {
                Navigator.pushNamed(context, NotificationTestScreen.routeName);
              },
            ),
        ],
      ),
    );
  }
}
