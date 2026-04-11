import 'package:flutter/material.dart';
import 'package:nerds/Widgets/drawer.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nerds Stickers"),
        centerTitle: true,
      ),
      drawer: const Drawer(child: MyDrawer()),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // App logo/icon
            const Icon(
              Icons.sticky_note_2,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 32),

            // Welcome text
            const Text(
              "Welcome to Nerds Stickers!",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              "Choose how you'd like to browse stickers:",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            // Navigation buttons
            _buildNavigationCard(
              context,
              title: "Sticker Packs",
              subtitle: "Browse organized sticker packs",
              icon: Icons.folder_special,
              color: Colors.blue,
              onTap: () => context.go('/stickers'),
            ),
            const SizedBox(height: 16),
            _buildNavigationCard(
              context,
              title: "Folder View",
              subtitle: "Browse stickers by folders",
              icon: Icons.folder,
              color: Colors.green,
              onTap: () => context.go('/folder-stickers'),
            ),
            const SizedBox(height: 16),
            _buildNavigationCard(
              context,
              title: "Information",
              subtitle: "About the app and usage",
              icon: Icons.info,
              color: Colors.orange,
              onTap: () => context.go('/information'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
