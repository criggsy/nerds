import 'package:flutter/material.dart';
import 'package:nerds/Widgets/drawer.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/repo_item.dart';
import 'package:nerds/services/repo_service.dart';
import 'package:nerds/utils/logger.dart';
import 'package:go_router/go_router.dart';

class FolderStickersScreen extends StatefulWidget {
  const FolderStickersScreen({super.key});

  @override
  State<FolderStickersScreen> createState() => _FolderStickersScreenState();
}

class _FolderStickersScreenState extends State<FolderStickersScreen> {
  bool _isLoading = false;
  List<RepoItem> _folders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);

    try {
      await RepoService.instance.loadStickers();
      final folders = await RepoService.instance.getStickerPacks();

      setState(() {
        _folders = folders;
        _isLoading = false;
      });

      log.i("✅ Folders loaded: ${folders.length}");
    } catch (e) {
      setState(() => _isLoading = false);
      log.e("❌ Error loading folders: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sticker Folders"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFolders,
          ),
        ],
      ),
      drawer: const Drawer(child: MyDrawer()),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _folders.length,
              itemBuilder: (context, index) {
                final folder = _folders[index];
                return _buildFolderTile(folder);
              },
            ),
    );
  }

  Widget _buildFolderTile(RepoItem folder) {
    final imageCount = folder.children?.length ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey[200],
          child: Icon(
            Icons.folder,
            color: Colors.blue[600],
          ),
        ),
        title: Text(
          folder.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text("$imageCount stickers"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          context.push(
            '/folder-detail',
            extra: {'folder': folder},
          );
        },
      ),
    );
  }
}
